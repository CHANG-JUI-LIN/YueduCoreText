import Foundation
import SwiftSoup

/// A document's principal writing mode (CSS Writing Modes 3 §8): the root element's
/// `writing-mode`, which a user agent takes from `<body>` when there is one, `<body>`
/// inheriting it from `<html>`.
///
/// The cascade never derives a writing mode from CSS: the host passes one, and logical
/// properties are mapped with it. This answers the question a host asks before it can
/// pass one: which mode does this document lay itself out in? It reads only the
/// declarations that reach `<html>` and `<body>`, so it does not depend on any reader
/// configuration.
enum PrincipalWritingMode {
    /// `nil` when no `writing-mode` declaration reaches `<body>` or `<html>`: the
    /// document leaves its mode to whatever the host decides for undeclared documents.
    static func resolve(_ parsed: ParsedChapter) -> ReaderWritingMode? {
        let html = parsed.body?.parent().flatMap { $0.tagName().lowercased() == "html" ? $0 : nil }
            ?? parsed.document.children().first().flatMap { $0.tagName().lowercased() == "html" ? $0 : nil }
        var mode: ReaderWritingMode?
        if let html, let declared = declared(on: html, rules: parsed.rules.regular) {
            mode = declared
        }
        if let body = parsed.body, let declared = declared(on: body, rules: parsed.rules.regular) {
            mode = declared
        }
        return mode
    }

    /// The `writing-mode` the cascade gives `element` from its own declarations, in the
    /// builder's order: normal author rules by specificity then source order, the
    /// `style` attribute, important author rules, important `style`. `nil` when none
    /// applies, so the element inherits.
    private static func declared(on element: Element, rules: [CSSRule]) -> ReaderWritingMode? {
        let matched = rules.filter { $0.selector.matches(element: element, parent: element.parent()) }
            .sorted { $0.specificity == $1.specificity ? $0.order < $1.order : $0.specificity < $1.specificity }
        let inline = CSSParser.parseDeclarationBlock((try? element.attr("style")) ?? "")
        var result: Value?
        func apply(_ declarations: [String: String], order: [String]) {
            for key in order where keys.contains(key) {
                if let value = declarations[key].flatMap(Value.init(css:)) { result = value }
            }
        }
        for rule in matched { apply(rule.declarations, order: rule.declarationOrder) }
        apply(inline.normal, order: inline.order)
        for rule in matched { apply(rule.importantDeclarations, order: rule.declarationOrder) }
        apply(inline.important, order: inline.order)
        switch result {
        case .mode(let mode): return mode
        case .inherit, nil: return nil
        }
    }

    /// WebKit treats the prefixed spellings as aliases of `writing-mode`.
    private static let keys: Set<String> = ["writing-mode", "-webkit-writing-mode", "-epub-writing-mode"]

    private enum Value {
        case mode(ReaderWritingMode)
        case inherit

        /// The values the engine lays out, with the SVG 1.1 spellings older EPUB 2 CSS
        /// still uses. A value it cannot lay out (`vertical-lr`, `sideways-lr`) is
        /// ignored, as a user agent ignores a declaration with an unsupported value:
        /// the declarations before it stand.
        init?(css raw: String) {
            switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "vertical-rl", "sideways-rl", "tb-rl", "tb": self = .mode(.verticalRTL)
            case "horizontal-tb", "lr-tb", "lr", "rl-tb", "rl", "initial", "revert", "revert-layer":
                self = .mode(.horizontal)
            case "inherit", "unset": self = .inherit
            default: return nil
            }
        }
    }
}
