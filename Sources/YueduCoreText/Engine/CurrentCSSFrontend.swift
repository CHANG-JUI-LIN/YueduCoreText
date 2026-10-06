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
        let parsed = try Self.parse(input: input, metrics: &metrics)
        return try Self.cascade(parsed, config: config, metrics: &metrics).result
    }

    /// Parses the markup and the stylesheets once; nothing here depends on the
    /// reader configuration, so one parse serves admission and every cascade.
    static func parse(input: CSSFrontendInput, metrics: inout LayoutMetrics) throws -> ParsedChapter {
        var parseMetrics = LayoutMetrics()
        defer { metrics.add(parseMetrics) }
        let document = try parseMetrics.time("htmlParse") {
            try SwiftSoup.parse(input.html)
        }
        let fullCSS = parseMetrics.time("cssCollect") {
            input.productionStylesheetTexts
                + (input.hasAuthoredStylesheetOrder ? [] : CurrentCSSFrontendSupport.inlineStyles(in: document))
        }
        var diagnostics: [CSSFrontendDiagnostic] = []
        for sheet in input.activeAuthorStylesheets {
            diagnostics.append(CSSFrontendDiagnostic(stage:.ingestion,stylesheet:sheet.identity,semanticPath:nil,property:nil,
                message:"sourceOrder=\(sheet.sourceOrder) active=\(!sheet.isAlternate && !sheet.loadFailed)"))
        }
        let rules = parseMetrics.time("cssParse") {
            CurrentCSSFrontendSupport.parseStylesheets(in: fullCSS,
                identities: input.hasAuthoredStylesheetOrder ? input.activeAuthorStylesheets.map(\.identity) : [],
                onDiagnostic: { diagnostics.append($0) })
        }
        return ParsedChapter(input: input, document: document, fullCSS: fullCSS, rules: rules,
                             diagnostics: diagnostics, parseStages: parseMetrics.stages)
    }

    /// Styles a parsed chapter for one configuration. The builder comes back with
    /// the result so admission can read which rules the cascade matched.
    static func cascade(
        _ parsed: ParsedChapter,
        config: BrowserLayoutConfig,
        metrics: inout LayoutMetrics
    ) throws -> (result: CSSFrontendResult, builder: ComputedStyleTreeBuilder) {
        guard let body = parsed.body else {
            throw BrowserLayoutDocument.BrowserLayoutError.emptyBody
        }
        if let report = config.onDiagnostic {
            for diagnostic in parsed.diagnostics { report(diagnostic) }
        }
        let builder = ComputedStyleTreeBuilder(rules: parsed.rules.regular, config: config, firstLetterRules: parsed.rules.firstLetter)
        var linkAnchors: [Int: LinkAnchorInfo] = [:]
        let rootNode = metrics.time("styleTree") {
            let tree = builder.buildTree(body: body)
            linkAnchors = ComputedStyleTreeBuilder.collectLinkAnchors(tree)
            return tree
        }
        let footnotes = BrowserLayoutDocument.collectFootnotes(in: parsed.document)

        let result = CSSFrontendResult(
            rootNode: rootNode,
            linkAnchors: linkAnchors,
            footnotes: footnotes,
            nodeCount: rootNode.nodeID
        )
        return (result, builder)
    }
}

/// One chapter's markup and stylesheets, parsed once by `CurrentCSSFrontend.parse`.
/// Holds the DOM for the cascade; never crosses a thread while in use.
final class ParsedChapter {
    let input: CSSFrontendInput
    let document: Document
    /// `nil` when the markup has no `<body>`: admission still reads the DOM, the cascade throws.
    let body: Element?
    /// The production sheets plus inline `<style>` blocks when ingestion did not order them.
    let fullCSS: [String]
    let rules: (regular: [CSSRule], firstLetter: [CSSRule])
    /// Ingestion and selector diagnostics, in the order the frontend reported them.
    let diagnostics: [CSSFrontendDiagnostic]
    /// `htmlParse` / `cssCollect` / `cssParse`, carried to whichever layout reuses the parse.
    let parseStages: [String: TimeInterval]

    init(input: CSSFrontendInput, document: Document, fullCSS: [String],
         rules: (regular: [CSSRule], firstLetter: [CSSRule]),
         diagnostics: [CSSFrontendDiagnostic], parseStages: [String: TimeInterval]) {
        self.input = input
        self.document = document
        self.body = document.body()
        self.fullCSS = fullCSS
        self.rules = rules
        self.diagnostics = diagnostics
        self.parseStages = parseStages
    }

    /// The `<body>`'s own `style` attribute, for the host's font-scale policy.
    var bodyInlineStyle: String {
        (try? body?.attr("style")) ?? ""
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
