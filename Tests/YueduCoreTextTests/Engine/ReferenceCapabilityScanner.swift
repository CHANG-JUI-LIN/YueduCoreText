import Foundation
import SwiftSoup
import Testing
import UIKit
@testable import YueduCoreText

/// The capability scanner exactly as it was before admission and layout shared one
/// parse (release 0.6.1): a second DOM parse, a second CSS parse, every rule
/// matched against every element, its own style tree. The equivalence tests run
/// it against `BrowserChapterDocument.evaluate` on real chapters and on markup
/// built to probe the seams (hidden subtrees, `<head>` rules, no body, dark media).
enum ReferenceCapabilityScanner {
    static func scan(input: CSSFrontendInput, writingMode: ReaderWritingMode, configuration: BrowserLayoutConfig) -> BrowserLayoutCapabilityResult {
        scan(html: input.html, cssTexts: input.productionStylesheetTexts, writingMode: writingMode,
             includeInline: !input.hasAuthoredStylesheetOrder, configuration: configuration)
    }

    private static func referencedFonts(in root: ComputedStyleNode) -> Set<BrowserFontRequest> {
        var requests: Set<BrowserFontRequest> = []
        func visit(_ node: ComputedStyleNode) {
            guard !node.style.isHidden else { return }
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

    private static func scan(html: String, cssTexts: [String], writingMode: ReaderWritingMode, includeInline: Bool, configuration: BrowserLayoutConfig) -> BrowserLayoutCapabilityResult {
        func declaration(key: String, value: String) -> UnsupportedFeature? {
            let k = key.lowercased(), v = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if writingMode == .verticalRTL {
                if ["writing-mode", "-webkit-writing-mode", "-epub-writing-mode"].contains(k) {
                    return v == "vertical-rl" || v == "inherit" ? nil : .verticalWritingMode
                }
                if k.contains("text-combine"), v != "none" { return .verticalWritingMode }
                if k.contains("text-orientation"), v != "mixed" { return .verticalWritingMode }
                if k == "min-height" || k == "min-width" { return .verticalWritingMode }
            }
            return BrowserLayoutCapabilityScanner.declaration(key: key, value: value, writingMode: .horizontal)
        }
        var reasons: [UnsupportedFeature] = []
        var textIndentUsage: HorizontalTextIndentUsage = .none
        var fontRequests: Set<BrowserFontRequest> = []

        // @media anywhere in the stylesheet affects layout for every chapter
        // that links it (the media query is not re-evaluated per element).
        for css in cssTexts {
            if BrowserLayoutCapabilityScanner.cssContainsMediaQuery(css) { reasons.append(.mediaQueries) }
        }

        // DOM-level checks (script, MathML, SVG semantics, table/float/flex in markup).
        if let doc = try? SwiftSoup.parse(html) {
            let fullCSS = cssTexts + (includeInline ? LegacyCSSFrontendSupport.inlineStyles(in: doc) : [])
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
                BoxTreeBuilder.svgWrappedImageSource(
                    SwiftSoupHTMLSemanticAdapter.snapshot($0)
                ) == nil
            }) {
                reasons.append(.unsupportedSVG)
            }

            // CSS rules: match selectors against the real DOM. Only declarations
            // from selectors that match at least one element are judged.
            let elements = (try? doc.getAllElements().array()) ?? []
            for css in LegacyCSSFrontendSupport.inlineStyles(in: doc) {
                if BrowserLayoutCapabilityScanner.cssContainsMediaQuery(css) { reasons.append(.mediaQueries) }
            }
            for css in fullCSS {
                for rule in CSSParser.parse(css: css, orderOffset: 0) {
                    let matchedElements = elements.filter { element in
                        guard rule.selector.matches(element: element, parent: element.parent()) else { return false }
                        return true
                    }
                    guard !matchedElements.isEmpty else { continue }  // unmatched rule → ignore

                    for property in rule.declarationOrder {
                        guard let value = rule.declarations[property] else { continue }
                        if let feature = declaration(key: property, value: value) {
                            reasons.append(feature)
                        }
                    }
                    for (property, value) in rule.importantDeclarations {
                        if let feature = declaration(key: property, value: value) {
                            reasons.append(feature)
                        }
                    }
                }
            }

            // Element inline style attributes — always apply to this chapter.
            for element in (try? doc.select("[style]").array()) ?? [] {
                let inline = (try? element.attr("style")) ?? ""
                let decl = CSSParser.parseDeclarationBlock(inline)
                for (key, value) in decl.normal {
                    if let reason = declaration(key: key, value: value) {
                        reasons.append(reason)
                    }
                }
                for (key, value) in decl.important {
                    if let reason = declaration(key: key, value: value) {
                        reasons.append(reason)
                    }
                }
            }

            // Ruby, Float and text-indent classification must use the SAME resolved cascade
            // as layout. Replaying raw declarations here gets overrides,
            // specificity and !important wrong.
            if let body = doc.body() {
                let parsed = LegacyCSSFrontendSupport.parseStylesheets(in: fullCSS)
                let styleTree = ComputedStyleTreeBuilder(
                    rules: parsed.regular,
                    config: configuration, firstLetterRules: parsed.firstLetter
                ).buildTree(body: body)
                fontRequests = referencedFonts(in: styleTree)
                let hasRubyMarkup = hasAny("ruby, rp, rt, rb, rtc")
                if hasRubyMarkup,
                   !HorizontalRubySupport.validate(
                       styleTree,
                       writingMode: writingMode
                   ).isSupported {
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
        }

        return BrowserLayoutCapabilityResult(
            supported: reasons.isEmpty,
            unsupportedFeatures: BrowserLayoutCapabilityScanner.dedupe(reasons),
            textIndentUsage: textIndentUsage,
            fontRequests: fontRequests
        )
    }
}
