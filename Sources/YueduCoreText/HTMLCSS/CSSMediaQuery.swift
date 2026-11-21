import CoreGraphics
import Foundation

/// What a `@media` query is asked about: the reader's page and its appearance.
public struct CSSMediaEnvironment: Sendable, Equatable {
    /// The viewport in CSS px. nil = not known: every width, height,
    /// orientation and aspect-ratio feature is false.
    public var viewportWidth: CGFloat?
    public var viewportHeight: CGFloat?
    /// `prefers-color-scheme`.
    public var prefersDark: Bool

    public init(viewportWidth: CGFloat? = nil, viewportHeight: CGFloat? = nil, prefersDark: Bool = false) {
        self.viewportWidth = viewportWidth
        self.viewportHeight = viewportHeight
        self.prefersDark = prefersDark
    }
}

/// Evaluates a media query list (Media Queries 3, with the level 4 features
/// EPUBs use): comma-separated queries of `[not | only]? <type> [and
/// (<feature>)]*` or `(<feature>) [and (<feature>)]*`. The medium is a
/// touch screen: `all` and `screen` match, every other type — `print`,
/// vendor types such as `amzn-kf8` — does not. A query that cannot be parsed
/// is false, as CSS makes it `not all`.
public enum CSSMediaQuery {
    public static func matches(_ list: String, in environment: CSSMediaEnvironment) -> Bool {
        let queries = split(list.lowercased(), at: ",")
        // An empty media query list is true.
        if queries.count == 1, queries[0].isEmpty { return true }
        return queries.contains { query($0, in: environment) == true }
    }

    /// nil = malformed.
    private static func query(_ text: String, in environment: CSSMediaEnvironment) -> Bool? {
        var parts = split(text, at: " and ")
        guard var first = parts.first, !first.isEmpty else { return nil }
        var negated = false
        if first.hasPrefix("not ") { negated = true; first = String(first.dropFirst(4)).trimmingCharacters(in: .whitespaces) }
        else if first.hasPrefix("only ") { first = String(first.dropFirst(5)).trimmingCharacters(in: .whitespaces) }
        parts[0] = first
        var result = true
        for (index, part) in parts.enumerated() {
            if part.hasPrefix("(") {
                guard part.hasSuffix(")"), let value = feature(String(part.dropFirst().dropLast()), in: environment) else { return nil }
                result = result && value
            } else {
                // A media type, which only the first position takes.
                guard index == 0, part.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }) else { return nil }
                result = result && (part == "all" || part == "screen")
            }
        }
        return negated ? !result : result
    }

    /// nil = not a feature this evaluator knows, which makes the query false.
    private static func feature(_ text: String, in environment: CSSMediaEnvironment) -> Bool? {
        let pair = text.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        guard let name = pair.first, !name.isEmpty else { return nil }
        let value = pair.count == 2 ? pair[1] : nil
        let width = environment.viewportWidth, height = environment.viewportHeight
        func compare(_ actual: CGFloat?, _ name: String) -> Bool? {
            // The boolean form (`(width)`) is true for a non-zero value.
            guard let value else { return actual.map { $0 > 0 } ?? false }
            guard let expected = length(value) else { return nil }
            guard let actual else { return false }
            if name.hasPrefix("min-") { return actual >= expected }
            if name.hasPrefix("max-") { return actual <= expected }
            return abs(actual - expected) < 0.5
        }
        switch name {
        case "width", "min-width", "max-width", "device-width", "min-device-width", "max-device-width":
            return compare(width, name)
        case "height", "min-height", "max-height", "device-height", "min-device-height", "max-device-height":
            return compare(height, name)
        case "orientation":
            guard let width, let height else { return false }
            if value == "portrait" { return height >= width }
            if value == "landscape" { return width > height }
            return nil
        case "prefers-color-scheme":
            if value == "dark" { return environment.prefersDark }
            if value == "light" { return !environment.prefersDark }
            return nil
        case "hover", "any-hover":
            return value == nil ? false : value == "none"
        case "pointer", "any-pointer":
            return value == nil ? true : value == "coarse"
        case "color":
            return value == nil
        case "monochrome":
            return false
        case "prefers-reduced-motion", "prefers-contrast", "prefers-reduced-transparency":
            return value == "no-preference"
        default:
            return nil
        }
    }

    /// A media query length in CSS px. `em` and `rem` are the initial font
    /// size, 16px, whatever the document sets.
    private static func length(_ text: String) -> CGFloat? {
        guard let parsed = CSSLengthResolver.parse(text) else { return nil }
        switch parsed {
        case .px(let value): return value
        case .pt(let value): return value * 96 / 72
        case .em(let value), .rem(let value): return value * 16
        case .percent, .vh, .vw, .auto, .calc: return nil
        }
    }

    /// Splits at `separator` outside parentheses and trims each piece.
    private static func split(_ text: String, at separator: String) -> [String] {
        var pieces: [String] = []
        var current = ""
        var depth = 0
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            if character == "(" { depth += 1 } else if character == ")" { depth = max(0, depth - 1) }
            if depth == 0, text[index...].hasPrefix(separator) {
                pieces.append(current)
                current = ""
                index = text.index(index, offsetBy: separator.count)
                continue
            }
            current.append(character)
            index = text.index(after: index)
        }
        pieces.append(current)
        return pieces.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression) }
    }
}
