import UIKit
import Foundation
import SwiftSoup

public struct CSSRule {
    public let selector: CSSSelector
    public let declarations: [String: String]
    public let importantDeclarations: [String: String]
    /// Property names in source order. Apply declarations by walking this —
    /// never by iterating `declarations`, whose order Swift randomizes per
    /// process (see `DeclarationBlock.order`).
    public let declarationOrder: [String]
    public let specificity: Int
    /// This rule's position among all rules in the stylesheet.
    public let order: Int
    /// True when the rule came from a `@media (prefers-color-scheme: dark)` block. Dark rules are
    /// resolved into a separate per-element style and applied only when the reader appearance is
    /// dark; they never participate in the light cascade (previously the whole block leaked and
    /// its rules applied unconditionally).
    public let isDarkMedia: Bool
    var sourceSelector: String = ""
    var sourceStylesheet: StylesheetIdentity? = nil
}

public struct CSSSelector {
    /// A single `[attr]` / `[attr=val]` / `[attr~=val]` … condition. `name` is already normalized to
    /// the DOM attribute form (namespace pipe `epub|type` and escaped `epub\:type` both → `epub:type`).
    public struct AttributeSelector {
        public enum Op {
            case exists      // [attr]
            case equals      // [attr=val]
            case includes    // [attr~=val]  (whitespace-separated list contains val)
            case dashMatch   // [attr|=val]  (val or val-…)
            case prefix      // [attr^=val]
            case suffix      // [attr$=val]
            case substring   // [attr*=val]
        }
        public let name: String
        public let op: Op
        public let value: String
    }

    /// How a component connects to the component on its left: ancestor, parent, or element sibling.
    public enum Combinator {
        case descendant
        case child
        case adjacentSibling
        case generalSibling
    }

    public struct Component {
        public let tag: String?
        public let id: String?
        public let classes: Set<String>
        public let attributes: [AttributeSelector]
        public let firstChild: Bool
        public var firstOfType: Bool = false
        /// Combinator linking this component to the previous (left) one. Ignored for the first.
        public let combinator: Combinator
    }

    /// Components in source order: `components[0]` is the leftmost (outermost ancestor),
    /// `components.last` is the subject matched against the candidate element itself.
    public let components: [Component]

    /// Matches the full complex selector by walking the component chain right-to-left. Descendant
    /// steps backtrack across every ancestor; child steps require the direct parent. Supports an
    /// arbitrary number of components (e.g. `nav[epub|type~='toc'] a > span.toc-label`).
    public func matches(element: Element, parent: Element?) -> Bool {
        matchChain(index: components.count - 1, element: element, parent: parent)
    }

    private func matchChain(index: Int, element: Element, parent: Element?) -> Bool {
        guard index >= 0 else { return true }
        let component = components[index]
        guard matches(component: component, element: element, parent: parent) else { return false }
        guard index > 0 else { return true }

        // `component.combinator` describes how this component connects to components[index - 1].
        switch component.combinator {
        case .child:
            guard let parent else { return false }
            return matchChain(index: index - 1, element: parent, parent: parent.parent())
        case .adjacentSibling, .generalSibling:
            var sibling = try? element.previousElementSibling()
            while let current = sibling {
                if matchChain(index: index - 1, element: current, parent: parent) { return true }
                if case .adjacentSibling = component.combinator { return false }
                sibling = try? current.previousElementSibling()
            }
            return false
        case .descendant:
            var ancestor = parent
            while let current = ancestor {
                if matchChain(index: index - 1, element: current, parent: current.parent()) {
                    return true
                }
                ancestor = current.parent()
            }
            return false
        }
    }

    private func matches(component: Component, element: Element, parent: Element?) -> Bool {
        if let tag = component.tag, element.tagName().lowercased() != tag {
            return false
        }
        if let id = component.id, element.id() != id {
            return false
        }
        let classNames = Set((try? element.classNames()) ?? [])
        if !component.classes.isSubset(of: classNames) {
            return false
        }
        for attribute in component.attributes where !Self.matches(attribute: attribute, element: element) {
            return false
        }
        if component.firstChild, !isFirstElementChild(element, parent: parent) {
            return false
        }
        if component.firstOfType, let parent {
            let first = parent.getChildNodes().compactMap { $0 as? Element }
                .first { $0.tagName() == element.tagName() }
            if first != element { return false }
        }
        return true
    }

    private static func matches(attribute: AttributeSelector, element: Element) -> Bool {
        let actual = attributeValue(named: attribute.name, of: element)
        switch attribute.op {
        case .exists:
            return actual != nil
        case .equals:
            return actual == attribute.value
        case .includes:
            guard let actual, !attribute.value.isEmpty else { return false }
            return actual
                .split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" || $0 == "\r" || $0 == "\u{0C}" })
                .contains { $0 == Substring(attribute.value) }
        case .dashMatch:
            guard let actual else { return false }
            return actual == attribute.value || actual.hasPrefix(attribute.value + "-")
        case .prefix:
            guard let actual, !attribute.value.isEmpty else { return false }
            return actual.hasPrefix(attribute.value)
        case .suffix:
            guard let actual, !attribute.value.isEmpty else { return false }
            return actual.hasSuffix(attribute.value)
        case .substring:
            guard let actual, !attribute.value.isEmpty else { return false }
            return actual.contains(attribute.value)
        }
    }

    /// Reads an attribute by name, falling back to a lowercased lookup (HTML attribute names are
    /// ASCII case-insensitive; EPUB content is lowercase, so exact match almost always hits first).
    private static func attributeValue(named name: String, of element: Element) -> String? {
        if element.hasAttr(name) { return try? element.attr(name) }
        let lower = name.lowercased()
        if lower != name, element.hasAttr(lower) { return try? element.attr(lower) }
        return nil
    }

    private func isFirstElementChild(_ element: Element, parent: Element?) -> Bool {
        guard let parent else { return true }
        for child in parent.getChildNodes() {
            if let childElement = child as? Element {
                return childElement == element
            }
        }
        return false
    }
}

public enum CSSParser {
    /// Strips CSS comments and statement at-rules (`@charset`, `@namespace`, stray `@import`) that
    /// carry no `{ }` block. The rule regex below treats everything up to the first `{` as the
    /// selector, so leaving these in front of the first style rule fuses them into that rule's
    /// selector — making it unmatchable and silently dropping its declarations. In practice the
    /// first rule is `body { … }`, so the document-wide `font-family` (and the embedded-font cascade
    /// that depends on it) vanishes. Block at-rules like `@font-face` are removed upstream; `@media`
    /// blocks are left untouched (still unsupported, but no longer able to break a neighbor).
    private static func sanitize(_ css: String) -> String {
        css
            // (?s): dot must match newlines — CJK publisher stylesheets routinely comment out
            // whole multi-line rule blocks (`/*.p_title { … }*/`). Without it the comment
            // survives, fuses with the next rule's selector (dropping that rule), and any
            // `{ }` pairs inside the comment leak back in as live rules. An unterminated
            // trailing comment is stripped to end-of-input.
            .replacingOccurrences(of: #"(?s)/\*.*?(?:\*/|\z)"#, with: "", options: .regularExpression)
            .replacingOccurrences(
                of: #"@(?:charset|namespace|import)\b[^{};]*;"#,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
    }

    public static func parse(css: String, orderOffset: Int = 0) -> [CSSRule] {
        // Flat light-palette rules only. `@media (prefers-color-scheme: dark)` blocks are
        // extracted and dropped here — consumers that support appearance variants (the CoreText
        // builder) use `parseWithFirstLetter` and read the flagged dark rules.
        let stripped = sanitize(css)
        let (baseCSS, _) = extractDarkMediaBlocks(from: stripped)
        return parseRuleList(css: baseCSS, orderOffset: orderOffset, isDarkMedia: false).regular
    }

    /// Parses CSS and returns (regular rules, first-letter rules).
    public static func parseWithFirstLetter(css: String, orderOffset: Int = 0) -> (regular: [CSSRule], firstLetter: [CSSRule]) {
        parseWithFirstLetter(css: css, orderOffset: orderOffset, onUnsupported: nil)
    }

    static func parseWithFirstLetter(css: String, orderOffset: Int, onUnsupported: ((String, Int) -> Void)?) -> (regular: [CSSRule], firstLetter: [CSSRule]) {
        let stripped = sanitize(css)
        let (baseCSS, darkCSS) = extractDarkMediaBlocks(from: stripped)
        let light = parseRuleList(css: baseCSS, orderOffset: orderOffset, isDarkMedia: false, onUnsupported: onUnsupported)
        // Dark :first-letter rules are dropped: the simplified first-letter feature resolves
        // only the light palette (no EPUB in the wild combines the two).
        let dark = parseRuleList(css: darkCSS, orderOffset: orderOffset, isDarkMedia: true)
        return (light.regular + dark.regular, light.firstLetter)
    }

    /// Splits `@media (prefers-color-scheme: dark) { … }` blocks out of a stylesheet. Returns the
    /// remaining CSS plus the concatenated inner rule text of the dark blocks.
    ///
    /// Every other block at-rule (`@supports`, `@media` with other queries, stray `@page`,
    /// `@font-face` leftovers) is removed entirely. They used to stay in place, where the
    /// `([^{}]+)\{([^{}]+)\}` rule regex fused their wrapper with the first inner rule and leaked
    /// the remaining inner rules as unconditional rules — a book with a dark-mode palette rendered
    /// washed-out light text on its light background. Statement at-rules (`@import` etc.) were
    /// already removed by `sanitize`; unrecognized ones without a block are skipped to `;`.
    private static func extractDarkMediaBlocks(from css: String) -> (remaining: String, dark: String) {
        let ns = css as NSString
        let length = ns.length
        guard let atRuleRegex = try? NSRegularExpression(pattern: #"@([a-zA-Z-]+)"#) else {
            return (css, "")
        }
        var remaining = ""
        var dark = ""
        var cursor = 0
        while cursor < length {
            guard let match = atRuleRegex.firstMatch(
                in: css,
                range: NSRange(location: cursor, length: length - cursor)
            ) else {
                remaining += ns.substring(from: cursor)
                break
            }
            remaining += ns.substring(
                with: NSRange(location: cursor, length: match.range.location - cursor)
            )
            let name = ns.substring(with: match.range(at: 1)).lowercased()
            let afterName = match.range.location + match.range.length
            let tail = ns.substring(from: afterName)
            let tailNS = tail as NSString

            var braceIdx: Int?
            var semiIdx: Int?
            for i in 0..<tailNS.length {
                let ch = tailNS.character(at: i)
                if ch == 0x7B { braceIdx = i; break } // '{'
                if ch == 0x3B { semiIdx = i; break }  // ';'
            }

            if let semi = semiIdx, braceIdx == nil || semi < braceIdx! {
                // Statement at-rule without a block — skip to the semicolon.
                cursor = afterName + semi + 1
                continue
            }
            guard let open = braceIdx else {
                // Dangling at-rule with neither brace nor semicolon: drop the rest.
                break
            }
            var depth = 0
            var closeIdx: Int?
            for i in open..<tailNS.length {
                let ch = tailNS.character(at: i)
                if ch == 0x7B { depth += 1 }
                else if ch == 0x7D { depth -= 1; if depth == 0 { closeIdx = i; break } } // '}'
            }
            guard let close = closeIdx else {
                // Unbalanced block: consume the rest of the stylesheet.
                break
            }
            let prelude = tailNS.substring(to: open).lowercased()
            let isDarkMedia = name == "media"
                && prelude.contains("prefers-color-scheme")
                && prelude.contains("dark")
            if isDarkMedia {
                dark += tailNS.substring(
                    with: NSRange(location: open + 1, length: close - open - 1)
                ) + "\n"
            }
            cursor = afterName + close + 1
        }
        return (remaining, dark)
    }

    /// Lower-cased, and without the leading colon a CSS3 selector doubles.
    private static let firstLetterPseudo = ":first-letter"

    private static func parseRuleList(
        css: String,
        orderOffset: Int,
        isDarkMedia: Bool,
        onUnsupported: ((String, Int) -> Void)? = nil
    ) -> (regular: [CSSRule], firstLetter: [CSSRule]) {
        guard let regex = try? NSRegularExpression(
            pattern: #"([^{}]+)\{([^{}]+)\}"#,
            options: [.dotMatchesLineSeparators]
        ) else {
            return ([], [])
        }
        var regular: [CSSRule] = []
        var firstLetter: [CSSRule] = []
        let nsCSS = css as NSString
        for (index, match) in regex.matches(in: css, range: NSRange(location: 0, length: nsCSS.length)).enumerated() {
            let selectorText = nsCSS.substring(with: match.range(at: 1))
            let declarations = parseDeclarationBlock(nsCSS.substring(with: match.range(at: 2)))
            for rawSelector in selectorText.split(separator: ",").map(String.init) {
                let trimmed = rawSelector.trimmingCharacters(in: .whitespacesAndNewlines)
                // Case-insensitive to match the `:first-child` handling in
                // `parseComponent`; CSS pseudo-element names are not case sensitive.
                let isFirstLetter = trimmed.lowercased().hasSuffix(Self.firstLetterPseudo)

                let selectorBody: String
                if isFirstLetter {
                    // Drop the pseudo-element, and the second colon when the stylesheet
                    // uses the CSS3 `p::first-letter` spelling.
                    //
                    // This used to cut at `lastIndex(of: ":")`, which for the CSS3 form
                    // lands *between* the two colons and leaves `p:` behind.
                    // `parseComponent` rejects any leftover colon, so the rule was
                    // dropped entirely and the drop cap silently never rendered — on the
                    // spelling EPUBs actually use.
                    var head = trimmed.dropLast(Self.firstLetterPseudo.count)
                    if head.hasSuffix(":") { head = head.dropLast() }
                    selectorBody = head.trimmingCharacters(in: .whitespacesAndNewlines)
                } else {
                    selectorBody = trimmed
                }

                guard !selectorBody.isEmpty, let selector = parseSelector(selectorBody) else {
                    onUnsupported?(trimmed, orderOffset + index)
                    continue
                }
                var rule = CSSRule(
                    selector: selector,
                    declarations: declarations.normal,
                    importantDeclarations: declarations.important,
                    declarationOrder: declarations.order,
                    specificity: specificity(of: selector) + (isFirstLetter ? 1 : 0),
                    order: orderOffset + index,
                    isDarkMedia: isDarkMedia
                )
                rule.sourceSelector = trimmed
                if isFirstLetter {
                    firstLetter.append(rule)
                } else {
                    regular.append(rule)
                }
            }
        }
        return (regular, firstLetter)
    }

    public struct DeclarationBlock {
        public let normal: [String: String]
        public let important: [String: String]
        /// Property names in SOURCE order — the order they must be applied in.
        ///
        /// A dictionary cannot carry this: Swift randomizes `Dictionary`
        /// iteration per process, so applying declarations by iterating the
        /// dictionary made the cascade depend on the hash seed. Two shorthands
        /// touching one property (`border: 4px` then `border-width: 4px 0px`)
        /// resolved to whichever the seed happened to visit last, so identical
        /// input rendered differently between runs.
        ///
        /// A property that appears more than once is listed at its LAST
        /// position, which is where the surviving value was declared.
        public let order: [String]

        public var merged: [String: String] {
            normal.merging(important) { _, importantValue in importantValue }
        }
    }

    public static func parseDeclarations(_ css: String) -> [String: String] {
        parseDeclarationBlock(css).merged
    }

    /// Splits a declaration block on `;` at PAREN DEPTH ZERO, outside quotes.
    ///
    /// A plain `split(separator: ";")` breaks any declaration whose value
    /// legally contains a semicolon. The common one is a data URI —
    /// `background-image: url(data:image/png;base64,…)` split into
    /// `url(data:image/png` (no closing paren, so the source parsed to nil) plus
    /// a junk `base64,…` fragment, and the image silently never painted.
    /// Quoted strings can carry `;` as well.
    private static func splitDeclarations(_ css: String) -> [Substring] {
        var out: [Substring] = []
        var depth = 0
        var quote: Character?
        var start = css.startIndex
        var i = css.startIndex
        while i < css.endIndex {
            let c = css[i]
            if let q = quote {
                if c == q { quote = nil }
            } else if c == "\"" || c == "'" {
                quote = c
            } else if c == "(" {
                depth += 1
            } else if c == ")" {
                depth = max(0, depth - 1)
            } else if c == ";", depth == 0 {
                if start < i { out.append(css[start..<i]) }
                start = css.index(after: i)
            }
            i = css.index(after: i)
        }
        if start < css.endIndex { out.append(css[start...]) }
        return out
    }

    public static func parseDeclarationBlock(_ css: String) -> DeclarationBlock {
        var normal: [String: String] = [:]
        var important: [String: String] = [:]
        var order: [String] = []
        for segment in splitDeclarations(css) {
            let parts = segment.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: true)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let rawValue = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            let importantRange = rawValue.range(
                of: #"\s*!\s*important\s*$"#,
                options: [.regularExpression, .caseInsensitive]
            )
            let value = importantRange.map {
                String(rawValue[..<$0.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            } ?? rawValue
            if key == "text-indent", !["inherit", "initial", "unset", "revert", "revert-layer"].contains(value.lowercased()), CSSTextIndent.declaration(value) == nil { continue }
            if !key.isEmpty && !value.isEmpty {
                if importantRange != nil {
                    important[key] = value
                    normal.removeValue(forKey: key)
                } else if important[key] == nil {
                    normal[key] = value
                } else {
                    // An `!important` earlier in the block already won this
                    // property; the later normal declaration is dead and must
                    // not move the property's position.
                    continue
                }
                // Re-declaring moves the property to its last position.
                if let existing = order.firstIndex(of: key) { order.remove(at: existing) }
                order.append(key)
            }
        }
        return DeclarationBlock(normal: normal, important: important, order: order)
    }

    /// Splits descendant, child, adjacent and general sibling components. Attribute values keep
    /// their literal combinator characters. Unsupported pseudo-classes or malformed components
    /// reject the whole selector; universal selectors are accepted.
    private static func parseSelector(_ raw: String) -> CSSSelector? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first, let last = trimmed.last,
              !">+~".contains(first), !">+~".contains(last) else { return nil }
        var tokens: [(combinator: CSSSelector.Combinator, text: String)] = []
        var current = ""
        var pendingCombinator: CSSSelector.Combinator = .descendant
        var bracketDepth = 0

        func flush() {
            guard !current.isEmpty else { return }
            tokens.append((pendingCombinator, current))
            current = ""
            pendingCombinator = .descendant
        }

        for char in raw.trimmingCharacters(in: .whitespacesAndNewlines) {
            if char == "[" { bracketDepth += 1; current.append(char); continue }
            if char == "]" { bracketDepth = max(0, bracketDepth - 1); current.append(char); continue }
            if bracketDepth > 0 { current.append(char); continue }

            if char == ">" || char == "+" || char == "~" {
                flush()
                pendingCombinator = char == ">" ? .child : (char == "+" ? .adjacentSibling : .generalSibling)
            } else if char.isWhitespace {
                flush()
            } else {
                current.append(char)
            }
        }
        flush()

        guard !tokens.isEmpty else { return nil }
        var components: [CSSSelector.Component] = []
        for token in tokens {
            guard let component = parseComponent(token.text, combinator: token.combinator) else { return nil }
            components.append(component)
        }
        return CSSSelector(components: components)
    }

    private static func parseComponent(_ raw: String, combinator: CSSSelector.Combinator) -> CSSSelector.Component? {
        var token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return nil }

        var firstOfType = false
        if token.lowercased().hasSuffix(":first-of-type") {
            firstOfType = true
            token = String(token.dropLast(":first-of-type".count))
        }
        var firstChild = false
        if token.lowercased().hasSuffix(":first-child") {
            firstChild = true
            token = String(token.dropLast(":first-child".count))
        }

        // Pull out every `[ … ]` attribute selector, then strip them so the remainder is a plain
        // tag/id/class token. Anything unparseable inside the brackets makes the whole rule unsupported.
        var attributes: [CSSSelector.AttributeSelector] = []
        if token.contains("[") {
            guard let regex = try? NSRegularExpression(pattern: "\\[[^\\]]*\\]") else { return nil }
            let ns = token as NSString
            let fullRange = NSRange(location: 0, length: ns.length)
            for match in regex.matches(in: token, range: fullRange) {
                let body = String(ns.substring(with: match.range).dropFirst().dropLast())
                guard let attribute = parseAttributeSelector(body) else { return nil }
                attributes.append(attribute)
            }
            token = regex.stringByReplacingMatches(in: token, range: fullRange, withTemplate: "")
        }

        let universal = token == "*" || token.isEmpty
        if token == "*" { token = "" }
        // Remaining unsupported pseudo-classes are rejected as a whole selector.
        if token.contains(">") || token.contains("+") || token.contains("~")
            || token.contains("*") || token.contains("[") || token.contains("]")
            || token.contains("(") || token.contains(":") {
            return nil
        }

        var tag: String?
        var id: String?
        var classes = Set<String>()
        var buffer = ""
        var mode: Character = "t"

        func flush() {
            guard !buffer.isEmpty else { return }
            switch mode {
            case "t":
                tag = buffer.lowercased()
            case "#":
                id = buffer
            case ".":
                classes.insert(buffer)
            default:
                break
            }
            buffer = ""
        }

        for char in token {
            if char == "#" || char == "." {
                flush()
                mode = char
            } else {
                buffer.append(char)
            }
        }
        flush()

        guard universal || tag != nil || id != nil || !classes.isEmpty || !attributes.isEmpty else { return nil }

        var component = CSSSelector.Component(tag: tag, id: id, classes: classes, attributes: attributes, firstChild: firstChild, combinator: combinator)
        component.firstOfType = firstOfType
        return component
    }

    /// Parses the inside of one `[ … ]` block, e.g. `epub|type~='pagebreak'`.
    private static func parseAttributeSelector(_ raw: String) -> CSSSelector.AttributeSelector? {
        let body = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return nil }

        guard let eqIndex = body.firstIndex(of: "=") else {
            guard let name = normalizeAttributeName(body) else { return nil }
            return CSSSelector.AttributeSelector(name: name, op: .exists, value: "")
        }

        let op: CSSSelector.AttributeSelector.Op
        let nameEnd: String.Index
        let opChar = eqIndex > body.startIndex ? body[body.index(before: eqIndex)] : nil
        switch opChar {
        case "~": op = .includes;   nameEnd = body.index(before: eqIndex)
        case "|": op = .dashMatch;  nameEnd = body.index(before: eqIndex)
        case "^": op = .prefix;     nameEnd = body.index(before: eqIndex)
        case "$": op = .suffix;     nameEnd = body.index(before: eqIndex)
        case "*": op = .substring;  nameEnd = body.index(before: eqIndex)
        default:  op = .equals;     nameEnd = eqIndex
        }

        guard let name = normalizeAttributeName(String(body[body.startIndex..<nameEnd])) else { return nil }
        let value = unquoteAttributeValue(String(body[body.index(after: eqIndex)...]))
        return CSSSelector.AttributeSelector(name: name, op: op, value: value)
    }

    /// `epub|type` (CSS namespace) and `epub\:type` (escaped colon) both map to the XHTML DOM
    /// attribute name `epub:type`. A leading `|` / `*|` (no/any namespace) is dropped.
    private static func normalizeAttributeName(_ raw: String) -> String? {
        var name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        name = name.replacingOccurrences(of: "\\:", with: ":")
        name = name.replacingOccurrences(of: "\\", with: "")
        if name.hasPrefix("*|") {
            name = String(name.dropFirst(2))
        } else if name.hasPrefix("|") {
            name = String(name.dropFirst())
        } else {
            name = name.replacingOccurrences(of: "|", with: ":")
        }
        name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    private static func unquoteAttributeValue(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Drop a trailing case-insensitivity flag (`[attr=val i]`).
        if value.hasSuffix(" i") || value.hasSuffix(" I") {
            value = String(value.dropLast(2)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if value.count >= 2,
           (value.hasPrefix("\"") && value.hasSuffix("\"")) || (value.hasPrefix("'") && value.hasSuffix("'")) {
            value = String(value.dropFirst().dropLast())
        }
        return value
    }

    private static func specificity(of selector: CSSSelector) -> Int {
        selector.components.reduce(0) { partial, component in
            partial
            + (component.id == nil ? 0 : 100)
            + component.classes.count * 10
            + component.attributes.count * 10
            + (component.firstChild ? 10 : 0) + (component.firstOfType ? 10 : 0)
            + (component.tag == nil ? 0 : 1)
        }
    }
}
