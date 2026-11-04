import CoreGraphics
import Foundation

/// Frontend-neutral HTML element semantics consumed by the presentational-hint
/// normalizer. A SwiftSoup node and a future Lexbor node both adapt into this
/// value; the extractor itself does not depend on either DOM implementation.
public struct HTMLSemanticElement: Equatable {
    public let tagName: String
    public let attributes: [String: String]

    public init(tagName: String, attributes: [String: String]) {
        self.tagName = tagName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var normalized: [String: String] = [:]
        for key in attributes.keys.sorted() {
            normalized[key.lowercased()] = attributes[key]
        }
        self.attributes = normalized
    }

    public func attribute(named name: String) -> String? {
        attributes[name.lowercased()]
    }
}

/// Parsed HTML dimension semantics. Percentages remain symbolic until layout
/// knows the containing inline size; integer-like legacy dimensions are CSS px.
public enum HTMLPresentationalDimension: Equatable {
    case pixels(CGFloat)
    /// Fraction form: 15% is stored as 0.15.
    case percentage(CGFloat)

    public static func parse(_ raw: String) -> HTMLPresentationalDimension? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        if value.hasSuffix("%") {
            let number = String(value.dropLast())
            guard isASCIIUnsignedInteger(number),
                  let parsed = Double(number),
                  parsed.isFinite else { return nil }
            return .percentage(CGFloat(parsed / 100))
        }

        guard isASCIIUnsignedInteger(value),
              let parsed = Double(value),
              parsed.isFinite else { return nil }
        return .pixels(CGFloat(parsed))
    }

    private static func isASCIIUnsignedInteger(_ value: String) -> Bool {
        !value.isEmpty && value.unicodeScalars.allSatisfy { scalar in
            scalar.value >= 0x30 && scalar.value <= 0x39
        }
    }
}

/// The list marker styles an `ol`, `ul` or `li` `type` attribute maps to
/// (HTML Standard §15.3.8 "Lists"). The raw value is the CSS keyword.
public enum HTMLListStyleType: String, Equatable {
    case decimal
    case lowerAlpha = "lower-alpha"
    case upperAlpha = "upper-alpha"
    case lowerRoman = "lower-roman"
    case upperRoman = "upper-roman"
    case disc
    case circle
    case square
    case none

    /// `ol` and `li` take the ordered keywords, matched case-sensitively, since
    /// `a` and `A` differ. `ul` and `li` take the bullet keywords and `none`,
    /// ASCII case-insensitively. The value is never trimmed: an attribute
    /// selector compares it whole.
    static func parse(typeAttribute raw: String, tagName: String) -> HTMLListStyleType? {
        if tagName == "ol" || tagName == "li" {
            switch raw {
            case "1": return .decimal
            case "a": return .lowerAlpha
            case "A": return .upperAlpha
            case "i": return .lowerRoman
            case "I": return .upperRoman
            default: break
            }
        }
        if tagName == "ul" || tagName == "li" {
            switch raw.lowercased() {
            case "disc": return .disc
            case "circle": return .circle
            case "square": return .square
            case "none": return HTMLListStyleType.none
            default: break
            }
        }
        return nil
    }
}

/// The CSS absolute-size keywords a `<font size>` maps to (HTML Standard
/// §15.3.4 "rules for parsing a legacy font size"). The raw value is the CSS
/// keyword.
public enum HTMLFontSizeKeyword: String, Equatable {
    case xSmall = "x-small"
    case small
    case medium
    case large
    case xLarge = "x-large"
    case xxLarge = "xx-large"
    case xxxLarge = "xxx-large"

    /// `1`…`7` absolute, `+n` and `-n` relative to 3, clamped to 1…7; leading
    /// white space skipped and anything after the digits ignored. nil without
    /// a digit.
    static func parse(legacyFontSize raw: String) -> HTMLFontSizeKeyword? {
        var scalars = Substring(raw).unicodeScalars.drop { " \t\n\u{0C}\r".unicodeScalars.contains($0) }
        var sign: Int?
        if scalars.first == "+" { sign = 1; scalars = scalars.dropFirst() }
        else if scalars.first == "-" { sign = -1; scalars = scalars.dropFirst() }
        let digits = scalars.prefix { $0.value >= 0x30 && $0.value <= 0x39 }
        guard !digits.isEmpty else { return nil }
        // Saturates long digit runs; the result clamps to 7 either way.
        let parsed = digits.reduce(0) { min($0 * 10 + Int($1.value - 0x30), 1_000) }
        let value: Int
        switch sign {
        case 1: value = 3 + parsed
        case -1: value = 3 - parsed
        default: value = parsed
        }
        return [.xSmall, .small, .medium, .large, .xLarge, .xxLarge, .xxxLarge][min(max(value, 1), 7) - 1]
    }
}

public enum HTMLPresentationalHintProperty: Equatable {
    case width
    case height
    case listStyleType
    case color
    case fontSize
    case fontFamily
    case backgroundColor
    /// All four sides.
    case borderColor
    /// All four sides.
    case borderStyle
    case borderBottomWidth
    case marginLeft
    case marginRight
}

public enum HTMLPresentationalHintValue: Equatable {
    case dimension(HTMLPresentationalDimension)
    case listStyleType(HTMLListStyleType)
    case color(CSSRGB)
    case fontSize(HTMLFontSizeKeyword)
    /// A `font-family` list as written.
    case fontFamily(String)
    case solidBorderStyle
    case auto
}

public struct HTMLPresentationalHint: Equatable {
    public let property: HTMLPresentationalHintProperty
    public let value: HTMLPresentationalHintValue
}

/// Converts HTML markup presentation into typed declarations. These declarations
/// enter the author-presentational-hint origin: after UA defaults and before all
/// author CSS. No synthetic CSS text is constructed or reparsed.
public enum HTMLPresentationalHintExtractor {
    public static func extract(from element: HTMLSemanticElement) -> [HTMLPresentationalHint] {
        // Phase 4F0 is deliberately corpus-driven. The 23-book census found only
        // img width/height; table/body/alignment hints stay absent until real
        // coverage justifies their style and layout contracts. List `type`
        // joined with list markers, whose numbering it selects; `font` and `hr`
        // with the rest of html.css's phrasing and rule defaults.
        switch element.tagName {
        case "ol", "ul", "li":
            guard let raw = element.attribute(named: "type"),
                  let type = HTMLListStyleType.parse(typeAttribute: raw, tagName: element.tagName) else { return [] }
            return [HTMLPresentationalHint(property: .listStyleType, value: .listStyleType(type))]
        case "font": return fontHints(element)
        case "hr": return horizontalRuleHints(element)
        case "img": break
        default: return []
        }

        var result: [HTMLPresentationalHint] = []
        if let raw = element.attribute(named: "width"),
           let dimension = HTMLPresentationalDimension.parse(raw) {
            result.append(HTMLPresentationalHint(
                property: .width,
                value: .dimension(dimension)
            ))
        }
        if let raw = element.attribute(named: "height"),
           let dimension = HTMLPresentationalDimension.parse(raw) {
            result.append(HTMLPresentationalHint(
                property: .height,
                value: .dimension(dimension)
            ))
        }
        return result
    }

    /// `HTMLFontElement`: `color` by the legacy colour rules, `size` by the
    /// legacy font size rules, `face` as a `font-family` list. Measured in
    /// WebKit on iOS 27.2: sizes 1…7 are 10, 13, 16, 18, 24, 32 and 48px,
    /// `+1` 18, `-1` 13, `+5` 48, `0` 10; `chucknorris` paints rgb(192, 0, 0).
    private static func fontHints(_ element: HTMLSemanticElement) -> [HTMLPresentationalHint] {
        var result: [HTMLPresentationalHint] = []
        if let raw = element.attribute(named: "color"), let color = CSSNamedColors.parseLegacy(raw) {
            result.append(HTMLPresentationalHint(property: .color, value: .color(color)))
        }
        if let raw = element.attribute(named: "size"), let keyword = HTMLFontSizeKeyword.parse(legacyFontSize: raw) {
            result.append(HTMLPresentationalHint(property: .fontSize, value: .fontSize(keyword)))
        }
        if let raw = element.attribute(named: "face"),
           !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            result.append(HTMLPresentationalHint(property: .fontFamily, value: .fontFamily(raw)))
        }
        return result
    }

    /// `HTMLHRElement::collectPresentationalHintsForAttribute`: `align` sets
    /// the inline margins, `width` the width (`0` is 1px), `color` a solid
    /// border and background in that colour, `noshade` without `color` the
    /// same in dark gray (WebKit's `Color::darkGray`, 128), and `size` the
    /// height less the two 1px borders, or no bottom border at 1 or less.
    /// Measured on iOS 27.2: `size=5` is a 5px box, `width=100 align=left`
    /// leaves the remaining width on the right.
    private static func horizontalRuleHints(_ element: HTMLSemanticElement) -> [HTMLPresentationalHint] {
        var result: [HTMLPresentationalHint] = []
        if let align = element.attribute(named: "align") {
            let zero = HTMLPresentationalHintValue.dimension(.pixels(0))
            switch align.lowercased() {
            case "left":
                result.append(HTMLPresentationalHint(property: .marginLeft, value: zero))
                result.append(HTMLPresentationalHint(property: .marginRight, value: .auto))
            case "right":
                result.append(HTMLPresentationalHint(property: .marginLeft, value: .auto))
                result.append(HTMLPresentationalHint(property: .marginRight, value: zero))
            default:
                result.append(HTMLPresentationalHint(property: .marginLeft, value: .auto))
                result.append(HTMLPresentationalHint(property: .marginRight, value: .auto))
            }
        }
        if let raw = element.attribute(named: "width") {
            if legacyInteger(raw) == 0 {
                result.append(HTMLPresentationalHint(property: .width, value: .dimension(.pixels(1))))
            } else if let dimension = HTMLPresentationalDimension.parse(raw) {
                result.append(HTMLPresentationalHint(property: .width, value: .dimension(dimension)))
            }
        }
        let color = element.attribute(named: "color").flatMap(CSSNamedColors.parseLegacy)
        let shade: CSSRGB? = element.attribute(named: "color") != nil ? color
            : element.attribute(named: "noshade") != nil ? CSSRGB(128, 128, 128) : nil
        if element.attribute(named: "color") != nil || shade != nil {
            result.append(HTMLPresentationalHint(property: .borderStyle, value: .solidBorderStyle))
        }
        if let shade {
            result.append(HTMLPresentationalHint(property: .borderColor, value: .color(shade)))
            result.append(HTMLPresentationalHint(property: .backgroundColor, value: .color(shade)))
        }
        if let raw = element.attribute(named: "size") {
            let size = legacyInteger(raw) ?? 0
            if size <= 1 {
                result.append(HTMLPresentationalHint(property: .borderBottomWidth, value: .dimension(.pixels(0))))
            } else {
                result.append(HTMLPresentationalHint(property: .height, value: .dimension(.pixels(CGFloat(size - 2)))))
            }
        }
        return result
    }

    /// HTML Standard "rules for parsing integers": leading white space, an
    /// optional sign, then digits; anything after them is ignored.
    private static func legacyInteger(_ raw: String) -> Int? {
        var scalars = Substring(raw).unicodeScalars.drop { " \t\n\u{0C}\r".unicodeScalars.contains($0) }
        var negative = false
        if scalars.first == "-" { negative = true; scalars = scalars.dropFirst() }
        else if scalars.first == "+" { scalars = scalars.dropFirst() }
        let digits = scalars.prefix { $0.value >= 0x30 && $0.value <= 0x39 }
        guard !digits.isEmpty else { return nil }
        let value = digits.reduce(0) { min($0 * 10 + Int($1.value - 0x30), 1_000_000) }
        return negative ? -value : value
    }
}
