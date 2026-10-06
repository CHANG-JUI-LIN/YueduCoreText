import Foundation
import SwiftSoup

/// Structured reason a chapter was rejected by the capability scanner.
/// Never carries book titles, chapter text, or URLs — only the feature name.
public enum UnsupportedFeature: Equatable, Sendable, CustomStringConvertible {
    case verticalWritingMode
    case ruby
    case float
    case table
    case flexGrid
    case positioned            // absolute / fixed / sticky
    case mathML
    case scriptedInteractive
    case unsupportedSVG
    case mediaQueries           // @media (layout-affecting)
    case calcOrModernFunctions  // calc() / min() / max() / clamp()
    case textIndent             // outside the Phase 4E1 resolved subset
    case unparseableLayoutCSS   // CSS we cannot parse that could affect layout
    case unknownBlockDisplay    // display: flex/grid/table/… mapped here too

    public var description: String {
        switch self {
        case .verticalWritingMode: return "vertical-writing-mode"
        case .ruby: return "ruby"
        case .float: return "float"
        case .table: return "table"
        case .flexGrid: return "flex-grid"
        case .positioned: return "positioned"
        case .mathML: return "mathml"
        case .scriptedInteractive: return "scripted-interactive"
        case .unsupportedSVG: return "unsupported-svg"
        case .mediaQueries: return "media-queries"
        case .calcOrModernFunctions: return "calc-modern-functions"
        case .textIndent: return "text-indent"
        case .unparseableLayoutCSS: return "unparseable-layout-css"
        case .unknownBlockDisplay: return "unknown-block-display"
        }
    }
}

/// One face tuple from the production computed-style cascade. Families include
/// authored glyph fallbacks; consumers must prepare them before measuring text.
public struct BrowserFontRequest: Hashable, Sendable {
    public let family: String
    public let weight: Int
    public let italic: Bool

    public init(family: String, weight: Int, italic: Bool) {
        self.family = family
        self.weight = weight
        self.italic = italic
    }
}

public struct BrowserLayoutCapabilityResult: Equatable, Sendable {
    public let supported: Bool
    public let unsupportedFeatures: [UnsupportedFeature]
    /// Resolved, selector-matched usage from the same computed-style tree the
    /// scanner already builds. Corpus diagnostics consume this so they do not
    /// parse a second full DOM merely to classify text-indent.
    public let textIndentUsage: HorizontalTextIndentUsage
    /// Includes inherited/block strut styles, visible descendants, ruby and
    /// materialized first-letter styles from the tree already built by admission.
    public let fontRequests: Set<BrowserFontRequest>

    public init(
        supported: Bool,
        unsupportedFeatures: [UnsupportedFeature],
        textIndentUsage: HorizontalTextIndentUsage = .none,
        fontRequests: Set<BrowserFontRequest> = []
    ) {
        self.supported = supported
        self.unsupportedFeatures = unsupportedFeatures
        self.textIndentUsage = textIndentUsage
        self.fontRequests = fontRequests
    }

    public static let supported = BrowserLayoutCapabilityResult(supported: true, unsupportedFeatures: [])
}

/// DOM-aware capability scanner. Runs BEFORE any browser-engine layout and
/// decides, per chapter, whether the browser engine can render it correctly.
///
/// Phase 4B accepts: horizontal reflowable EPUB, block/inline, supported CSS Float
/// (replaced images, explicit/percent width boxes, clear: left/right/both),
/// supported box model, supported white-space, plain text, links, anchors, basic images.
///
/// These entry points parse the chapter for one verdict and discard the parse.
/// Production admission goes through `BrowserChapterDocument.evaluate`, which
/// judges the same facts and keeps the style tree for the layout that follows.
public enum BrowserLayoutCapabilityScanner {

    public static func scan(input: CSSFrontendInput, writingMode: ReaderWritingMode = .horizontal) -> BrowserLayoutCapabilityResult {
        scan(input: input, writingMode: writingMode, configuration: .init())
    }

    /// Uses the reader's font family and bold settings when reporting face demand.
    public static func scan(input: CSSFrontendInput, writingMode: ReaderWritingMode = .horizontal,
                            configuration: BrowserLayoutConfig) -> BrowserLayoutCapabilityResult {
        guard let document = try? BrowserChapterDocument(input: input) else {
            // Markup SwiftSoup cannot parse: the stylesheets are still judged for
            // media queries, as they always were.
            var reasons: [UnsupportedFeature] = []
            for css in input.productionStylesheetTexts where cssContainsMediaQuery(css) {
                reasons.append(.mediaQueries)
            }
            return BrowserLayoutCapabilityResult(supported: reasons.isEmpty, unsupportedFeatures: dedupe(reasons))
        }
        return document.evaluate(configuration: configuration, writingMode: writingMode).capabilities
    }

    public static func scan(html: String, cssTexts: [String], writingMode: ReaderWritingMode = .horizontal) -> BrowserLayoutCapabilityResult {
        scan(input: .currentCompatibility(html: html, cssTexts: cssTexts), writingMode: writingMode, configuration: .init())
    }

    static func referencedFonts(in root: ComputedStyleNode) -> Set<BrowserFontRequest> {
        var requests: Set<BrowserFontRequest> = []
        func visit(_ node: ComputedStyleNode) {
            guard !node.style.isHidden else { return }
            // Match InlineLayout.resolvedFont, including the reader's bold override.
            let weight = node.style.configBold ? max(700, node.style.fontWeight) : node.style.fontWeight
            requests.formUnion(node.style.fontFamilies.map {
                BrowserFontRequest(family: $0, weight: weight, italic: node.style.isItalic)
            })
            for child in node.children {
                if case .element(let element) = child { visit(element) }
            }
        }
        visit(root)
        return requests
    }

    /// The feature a declaration would need, for the writing mode being judged.
    static func declaration(key: String, value: String, writingMode: ReaderWritingMode) -> UnsupportedFeature? {
        let k = key.lowercased(), v = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if writingMode == .verticalRTL {
            if ["writing-mode", "-webkit-writing-mode", "-epub-writing-mode"].contains(k) {
                return v == "vertical-rl" || v == "inherit" ? nil : .verticalWritingMode
            }
            if k.contains("text-combine"), v != "none" { return .verticalWritingMode }
            if k.contains("text-orientation"), v != "mixed" { return .verticalWritingMode }
            if k == "min-height" || k == "min-width" { return .verticalWritingMode }
        }
        return layoutAffectingDeclaration(key: key, value: value)
    }

    static func validateFloats(
        in node: ComputedStyleNode,
        hasFloatedAncestor: Bool,
        reasons: inout [UnsupportedFeature]
    ) {
        let isFloated = node.style.isFloated
        if isFloated {
            let isReplaced = node.tag == "img"
                || (node.tag == "svg"
                    && node.semanticElement.flatMap(BoxTreeBuilder.svgWrappedImageSource) != nil)
            // Non-replaced floats with width:auto need CSS shrink-to-fit, which
            // Phase 4B deliberately does not guess. max-width alone does not
            // turn width:auto into a definite used width.
            if (!isReplaced && node.tag != "::first-letter" && node.style.width == .auto) || hasFloatedAncestor {
                reasons.append(.float)
            }
        }

        for child in node.children {
            guard case .element(let childNode) = child else { continue }
            validateFloats(
                in: childNode,
                hasFloatedAncestor: hasFloatedAncestor || isFloated,
                reasons: &reasons
            )
        }
    }

    // MARK: - CSS text scanning (media queries only)

    static func cssContainsMediaQuery(_ css: String) -> Bool {
        let cleaned = css.replacingOccurrences(of: #"(?s)/\*.*?(?:\*/|\z)"#, with: "", options: .regularExpression)
        return regexMatch(#"@media\b"#, in: cleaned)
    }

    /// Layout-affecting CSS declarations. Paint-only properties
    /// (background-image, background-size, background-position,
    /// background-attachment, border-radius, text-shadow, …) are NOT layout
    /// features — they are paint degradation at worst and must never reject a
    /// chapter.
    private static func layoutAffectingDeclaration(key: String, value: String) -> UnsupportedFeature? {
        let k = key.lowercased()
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if k == "float" || k == "clear" {
            // Float is validated at the element level (supported for images / explicit widths)
            return nil
        }
        if k == "text-indent" {
            // Property-specific admission happens on the resolved style tree.
            // This must precede the generic calc()/min()/max()/clamp() check so
            // the scanner reports the shared text-indent capability boundary.
            return nil
        }
        if k == "position" && (v.contains("absolute") || v.contains("fixed") || v.contains("sticky")) {
            return .positioned
        }
        if k == "display" && (v.contains("table") || v.contains("flex") || v.contains("grid")) {
            return .unknownBlockDisplay
        }
        if k == "flex" || k == "flex-direction" || k == "flex-wrap" || k == "flex-basis"
            || k == "flex-grow" || k == "flex-shrink" || k == "justify-content"
            || k == "align-items" || k.hasPrefix("grid-") || k == "gap" {
            return .flexGrid
        }
        if v.contains("calc(") || v.contains("min(") || v.contains("max(") || v.contains("clamp(") {
            return .calcOrModernFunctions
        }
        if k == "writing-mode"
            || k == "-webkit-writing-mode"
            || k == "-epub-writing-mode" {
            if v.contains("vertical") { return .verticalWritingMode }
        }
        return nil
    }

    private static func regexMatch(_ pattern: String, in text: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return false }
        return regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    static func dedupe(_ reasons: [UnsupportedFeature]) -> [UnsupportedFeature] {
        var seen = Set<UnsupportedFeature>()
        return reasons.filter { seen.insert($0).inserted }
    }
}
