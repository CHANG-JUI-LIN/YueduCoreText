import Foundation
import SwiftSoup

/// Named facade for the pre-Lexbor SwiftSoup + CSSParser + CSSSelector cascade.
/// It may use SwiftSoup internally, but every returned DOM identity is copied
/// into `HTMLDOMElementSnapshot` before the document leaves this method.
final class CurrentCSSFrontend: CSSFrontend {
    init() {}

    func buildStyleTree(
        input: CSSFrontendInput,
        config: BrowserLayoutConfig,
        metrics: inout LayoutMetrics
    ) throws -> CSSFrontendResult {
        let document = try metrics.time("htmlParse") {
            try SwiftSoup.parse(input.html)
        }
        guard let body = document.body() else {
            throw BrowserLayoutDocument.BrowserLayoutError.emptyBody
        }

        let fullCSS = metrics.time("cssCollect") {
            input.productionStylesheetTexts
                + (input.hasAuthoredStylesheetOrder ? [] : CurrentCSSFrontendSupport.inlineStyles(in: document))
        }
        if let report = config.onDiagnostic {
            for sheet in input.activeAuthorStylesheets {
                report(CSSFrontendDiagnostic(stage:.ingestion,stylesheet:sheet.identity,semanticPath:nil,property:nil,
                    message:"sourceOrder=\(sheet.sourceOrder) active=\(!sheet.isAlternate && !sheet.loadFailed)"))
            }
        }
        let rules = metrics.time("cssParse") {
            CurrentCSSFrontendSupport.parseStylesheets(in: fullCSS,
                identities: input.hasAuthoredStylesheetOrder ? input.activeAuthorStylesheets.map(\.identity) : [],
                onDiagnostic: config.onDiagnostic)
        }
        let builder = ComputedStyleTreeBuilder(rules: rules.regular, config: config, firstLetterRules: rules.firstLetter)
        var linkAnchors: [Int: LinkAnchorInfo] = [:]
        let rootNode = metrics.time("styleTree") {
            let tree = builder.buildTree(body: body)
            linkAnchors = ComputedStyleTreeBuilder.collectLinkAnchors(tree)
            return tree
        }
        let footnotes = BrowserLayoutDocument.collectFootnotes(in: document)

        return CSSFrontendResult(
            rootNode: rootNode,
            linkAnchors: linkAnchors,
            footnotes: footnotes,
            nodeCount: rootNode.nodeID
        )
    }
}

/// Shared collection/parsing policy for every consumer that must agree with
/// the production Current frontend (notably the capability scanner).
enum CurrentCSSFrontendSupport {
    static func stylesheetsForCurrentCompatibility(
        _ stylesheets: [AuthorStylesheet]
    ) -> [String] {
        stylesheets
            .filter { $0.currentCompatibilityOrder != nil }
            .sorted { lhs, rhs in
                let left = lhs.currentCompatibilityOrder ?? lhs.sourceOrder
                let right = rhs.currentCompatibilityOrder ?? rhs.sourceOrder
                if left == right { return lhs.sourceOrder < rhs.sourceOrder }
                return left < right
            }
            .map(\.text)
    }

    static func inlineStyles(in document: Document) -> [String] {
        guard let head = document.head() else { return [] }
        return ((try? head.select("style").array()) ?? [])
            .compactMap { try? $0.html() }
            .filter { !$0.isEmpty }
    }

    static func parseRules(in stylesheets: [String]) -> [CSSRule] { parseStylesheets(in: stylesheets).regular }

    static func parseStylesheets(in stylesheets: [String], identities: [StylesheetIdentity] = [],
                                 onDiagnostic: ((CSSFrontendDiagnostic) -> Void)? = nil) -> (regular: [CSSRule], firstLetter: [CSSRule]) {
        var result: [CSSRule] = []
        var initials: [CSSRule] = []
        var offset = 0
        for (index, css) in stylesheets.enumerated() {
            let identity = identities.indices.contains(index) ? identities[index] : StylesheetIdentity(sourceOrder:index,label:"input[\(index)]")
            let parsed = CSSParser.parseWithFirstLetter(css: css, orderOffset: offset, onUnsupported: onDiagnostic.map { report in
                { selector, order in report(CSSFrontendDiagnostic(stage:.selector,stylesheet:identity,semanticPath:nil,property:nil,
                    message:"unsupported selector=\(selector) order=\(order)")) }
            })
            func attributedRule(_ rule: CSSRule) -> CSSRule { var copy = rule; copy.sourceStylesheet = identity; return copy }
            result += parsed.regular.filter { !$0.isDarkMedia }.map(attributedRule)
            initials += parsed.firstLetter.map(attributedRule)
            offset = (parsed.regular + parsed.firstLetter).map(\.order).max().map { $0 + 1 } ?? offset
        }
        return (result, initials)
    }
}

/// Compatibility spelling retained until the production cutover is complete.
/// It deliberately delegates rather than carrying a second implementation.
final class LegacyCSSFrontend: CSSFrontend {
    private let current = CurrentCSSFrontend()

    init() {}

    func buildStyleTree(
        input: CSSFrontendInput,
        config: BrowserLayoutConfig,
        metrics: inout LayoutMetrics
    ) throws -> CSSFrontendResult {
        try current.buildStyleTree(input: input, config: config, metrics: &metrics)
    }
}

/// Compatibility alias used by scanner/census code during Tasks 4–8. Keeping
/// one implementation guarantees they parse with the same Current policy.
typealias LegacyCSSFrontendSupport = CurrentCSSFrontendSupport
