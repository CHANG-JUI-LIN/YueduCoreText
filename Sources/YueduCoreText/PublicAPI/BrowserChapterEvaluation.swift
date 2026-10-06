import Foundation
import SwiftSoup
import UIKit

/// One chapter's markup and stylesheets, parsed once.
///
/// Admission (`evaluate`) and layout (a session built from the evaluation) used to
/// parse the chapter independently — the scanner once, the frontend again for the
/// session, and the host a third time for the body's font-scale policy. This holds
/// the one parse they now share. It keeps the DOM for the cascade, so it is not
/// Sendable: build it, evaluate it and hand the evaluation to a session from one
/// executor at a time.
public final class BrowserChapterDocument {
    public let input: CSSFrontendInput
    let parsed: ParsedChapter

    /// The `<body>`'s own `style` attribute, so a host's font-scale policy needs no
    /// parse of its own. Empty when there is no body or no attribute.
    public var bodyInlineStyle: String { parsed.bodyInlineStyle }

    /// Parses the markup and every active stylesheet. Throws when the markup
    /// cannot be parsed at all; a document without a `<body>` still parses (its
    /// evaluation reports admission facts, a session built from it fails).
    public init(input: CSSFrontendInput) throws {
        self.input = input
        var metrics = LayoutMetrics()
        parsed = try CurrentCSSFrontend.parse(input: input, metrics: &metrics)
    }

    /// Styles the chapter for `configuration` and judges it for the browser engine.
    ///
    /// The computed values depend on the configuration's cascade inputs (font size,
    /// families, colors, spacing, bold, alignment); a session built from the result
    /// must be given a configuration with the same ones (`BrowserLayoutConfig.cascadeInputs`).
    /// `writingMode` defaults to the configuration's.
    public func evaluate(configuration: BrowserLayoutConfig,
                         writingMode: ReaderWritingMode? = nil) -> BrowserChapterEvaluation {
        let mode = writingMode ?? configuration.writingMode
        var metrics = LayoutMetrics()
        let cascade = try? CurrentCSSFrontend.cascade(parsed, config: configuration, metrics: &metrics)
        let capabilities = BrowserChapterAdmission.judge(parsed: parsed, cascade: cascade, writingMode: mode)
        let prepared = cascade.map {
            BrowserLayoutDocument.PreparedFrontend(result: $0.result,
                                                   stages: parsed.parseStages.merging(metrics.stages) { $0 + $1 })
        }
        return BrowserChapterEvaluation(document: self, configuration: configuration, writingMode: mode,
                                        capabilities: capabilities, preparedFrontend: prepared)
    }
}

/// A chapter styled for one configuration, with the browser engine's verdict on it.
/// Hand it to `HTMLLayoutDocument(evaluation:)` or `BrowserLayoutSession(evaluation:)`
/// so layout starts from this style tree instead of parsing the chapter again.
public final class BrowserChapterEvaluation {
    public let document: BrowserChapterDocument
    /// The configuration the style tree was computed for.
    public let configuration: BrowserLayoutConfig
    public let writingMode: ReaderWritingMode
    public let capabilities: BrowserLayoutCapabilityResult
    /// `nil` when the markup has no `<body>`.
    let preparedFrontend: BrowserLayoutDocument.PreparedFrontend?

    init(document: BrowserChapterDocument, configuration: BrowserLayoutConfig, writingMode: ReaderWritingMode,
         capabilities: BrowserLayoutCapabilityResult, preparedFrontend: BrowserLayoutDocument.PreparedFrontend?) {
        self.document = document
        self.configuration = configuration
        self.writingMode = writingMode
        self.capabilities = capabilities
        self.preparedFrontend = preparedFrontend
    }

    /// A configuration a session may use this evaluation's style tree with: the same
    /// cascade inputs, whatever its geometry, resolver or diagnostic sink.
    public func accepts(_ configuration: BrowserLayoutConfig) -> Bool {
        configuration.cascadeInputs == self.configuration.cascadeInputs
    }

    /// The same style tree and verdict under `configuration` — one that adds a font
    /// resolver, geometry or a diagnostic sink after admission. `nil` when the
    /// configuration's cascade inputs differ: that needs a new evaluation.
    public func rebound(to configuration: BrowserLayoutConfig) -> BrowserChapterEvaluation? {
        guard accepts(configuration) else { return nil }
        return BrowserChapterEvaluation(document: document, configuration: configuration, writingMode: writingMode,
                                        capabilities: capabilities, preparedFrontend: preparedFrontend)
    }
}

extension BrowserLayoutConfig {
    /// Everything the cascade reads. Two configurations with equal inputs compute
    /// the same style tree for the same chapter.
    struct CascadeInputs: Equatable {
        let rootFontSize: CGFloat
        let fontFamilies: [String]
        let textColor: UIColor
        let backgroundColor: UIColor
        let lineHeight: CGFloat?
        let lineSpacing: CGFloat
        let paragraphSpacing: CGFloat
        let letterSpacing: CGFloat
        let isBold: Bool
        let defaultTextAlignment: NSTextAlignment
    }

    var cascadeInputs: CascadeInputs {
        CascadeInputs(rootFontSize: rootFontSize, fontFamilies: fontFamilies, textColor: textColor,
                      backgroundColor: backgroundColor, lineHeight: lineHeight, lineSpacing: lineSpacing,
                      paragraphSpacing: paragraphSpacing, letterSpacing: letterSpacing, isBold: isBold,
                      defaultTextAlignment: defaultTextAlignment)
    }
}

/// The browser engine's admission facts for one parsed chapter: the same judgments
/// `BrowserLayoutCapabilityScanner` always made, read from the shared parse and the
/// cascade's own rule matching instead of a second parse of the chapter.
enum BrowserChapterAdmission {
    static func judge(parsed: ParsedChapter,
                      cascade: (result: CSSFrontendResult, builder: ComputedStyleTreeBuilder)?,
                      writingMode: ReaderWritingMode) -> BrowserLayoutCapabilityResult {
        func declaration(key: String, value: String) -> UnsupportedFeature? {
            BrowserLayoutCapabilityScanner.declaration(key: key, value: value, writingMode: writingMode)
        }
        var reasons: [UnsupportedFeature] = []
        var textIndentUsage: HorizontalTextIndentUsage = .none
        var fontRequests: Set<BrowserFontRequest> = []

        // @media anywhere in the stylesheet affects layout for every chapter
        // that links it (the media query is not re-evaluated per element).
        for css in parsed.input.productionStylesheetTexts {
            if BrowserLayoutCapabilityScanner.cssContainsMediaQuery(css) { reasons.append(.mediaQueries) }
        }

        // DOM-level checks (script, MathML, SVG semantics, table in markup).
        let doc = parsed.document
        func hasAny(_ selector: String) -> Bool {
            ((try? doc.select(selector).isEmpty()) ?? true) == false
        }
        if hasAny("script, iframe, object, embed, canvas, audio") {
            reasons.append(.scriptedInteractive)
        }
        if hasAny("math") {
            reasons.append(.mathML)
        }
        if hasAny("table, thead, tbody, tr, td, th, colgroup") {
            reasons.append(.table)
        }
        let svgs = (try? doc.select("svg").array()) ?? []
        if svgs.contains(where: {
            BoxTreeBuilder.svgWrappedImageSource(SwiftSoupHTMLSemanticAdapter.snapshot($0)) == nil
        }) {
            reasons.append(.unsupportedSVG)
        }
        for css in CurrentCSSFrontendSupport.inlineStyles(in: doc) {
            if BrowserLayoutCapabilityScanner.cssContainsMediaQuery(css) { reasons.append(.mediaQueries) }
        }

        // CSS rules: only declarations from selectors that match at least one
        // element are judged. The cascade matched every rule against every element
        // it styled; the elements it never styles (the <head> subtree, descendants of
        // a hidden element) are matched here, so the verdict covers the whole DOM
        // exactly as a scan of every element did.
        let rules = parsed.rules.regular
        var matched = cascade?.builder.matchedRuleIndices ?? []
        let styled = cascade?.builder.styledElements ?? []
        if let elements = try? doc.getAllElements().array() {
            for element in elements where !styled.contains(ObjectIdentifier(element)) {
                for index in rules.indices where !matched.contains(index) {
                    if rules[index].selector.matches(element: element, parent: element.parent()) {
                        matched.insert(index)
                    }
                }
            }
        }
        for index in rules.indices where matched.contains(index) {
            let rule = rules[index]
            for property in rule.declarationOrder {
                guard let value = rule.declarations[property] else { continue }
                if let feature = declaration(key: property, value: value) {
                    reasons.append(feature)
                }
            }
            for property in rule.declarationOrder {
                guard let value = rule.importantDeclarations[property] else { continue }
                if let feature = declaration(key: property, value: value) {
                    reasons.append(feature)
                }
            }
        }

        // Element inline style attributes — always apply to this chapter.
        for element in (try? doc.select("[style]").array()) ?? [] {
            let inline = (try? element.attr("style")) ?? ""
            let decl = CSSParser.parseDeclarationBlock(inline)
            for key in decl.order {
                if let value = decl.normal[key], let reason = declaration(key: key, value: value) {
                    reasons.append(reason)
                }
            }
            for key in decl.order {
                if let value = decl.important[key], let reason = declaration(key: key, value: value) {
                    reasons.append(reason)
                }
            }
        }

        // Ruby, Float and text-indent classification use the SAME resolved cascade
        // as layout. Replaying raw declarations here gets overrides, specificity
        // and !important wrong.
        if let styleTree = cascade?.result.rootNode {
            fontRequests = BrowserLayoutCapabilityScanner.referencedFonts(in: styleTree)
            let hasRubyMarkup = hasAny("ruby, rp, rt, rb, rtc")
            if hasRubyMarkup,
               !HorizontalRubySupport.validate(styleTree, writingMode: writingMode).isSupported {
                reasons.append(.ruby)
            }
            if writingMode == .verticalRTL, !VerticalTextSupport.accepts(styleTree) {
                reasons.append(.verticalWritingMode)
            }
            BrowserLayoutCapabilityScanner.validateFloats(in: styleTree, hasFloatedAncestor: false, reasons: &reasons)
            textIndentUsage = HorizontalTextIndentSupport.usage(in: styleTree)
            if textIndentUsage == .unsupported {
                reasons.append(.textIndent)
            }
        }

        return BrowserLayoutCapabilityResult(
            supported: reasons.isEmpty,
            unsupportedFeatures: BrowserLayoutCapabilityScanner.dedupe(reasons),
            textIndentUsage: textIndentUsage,
            fontRequests: fontRequests
        )
    }
}
