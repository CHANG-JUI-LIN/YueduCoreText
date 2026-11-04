import Foundation

/// What a list item's marker says, before any font or geometry: CSS Counter
/// Styles 3 applied to the item's ordinal.
enum ListMarkerText: Equatable {
    /// `disc`, `circle`, `square`. WebKit draws its own shape for these
    /// (`listMarkerSynthesizesGlyph`), not the symbol character, so there is no
    /// text to lay out.
    case bullet(ListMarkerBullet)
    /// Every other style. The representation carries the negative sign and any
    /// padding; the suffix is kept apart so a reader can speak `"1."` without
    /// the trailing space.
    case counter(representation: String, suffix: String)

    /// The marker for an item numbered `ordinal`; nil for `list-style-type: none`.
    /// A name with no style in `CounterStyle.predefined` draws as `decimal`, for
    /// one of two reasons:
    /// - No counter style has that name. CSS Counter Styles 3 §3 draws it as
    ///   decimal, and so does WebKit.
    /// - Fallback: WebKit predefines the style (`hiragana`, `lower-greek` …) but
    ///   this table does not, so WebKit draws something else. The corpus uses
    ///   none of them; a name stops falling back once it has an entry.
    init?(type: CSSListStyleType, ordinal: Int) {
        guard case .counterStyle(let name) = type else { return nil }
        let style = CounterStyle.predefined[name] ?? CounterStyle.decimal
        if case .bullet(let bullet) = style.system {
            self = .bullet(bullet)
        } else {
            self = .counter(representation: style.representation(of: ordinal), suffix: style.suffix)
        }
    }

    /// The text a counter marker lays out; nil for a bullet.
    var string: String? {
        guard case .counter(let representation, let suffix) = self else { return nil }
        return representation + suffix
    }
}

enum ListMarkerBullet: Equatable {
    case disc
    case circle
    case square
}

/// One `@counter-style`, as WebKit's UA sheet (`counterStyles.css`, read out of
/// the iOS 27.2 runtime) defines it. Only the styles the list-marker design
/// supports are in `predefined`; adding one is one more entry.
struct CounterStyle {
    enum System {
        /// The cyclic `disc`/`circle`/`square`, drawn as a shape.
        case bullet(ListMarkerBullet)
        /// Place value; `symbols[0]` is zero.
        case numeric([String])
        /// Bijective base n: a … z, aa, ab …
        case alphabetic([String])
        /// Each weight, largest first, repeated as often as it fits.
        case additive([(weight: Int, symbol: String)])
        /// The informal Chinese longhand (CSS Counter Styles 3 §7.1.3).
        case chineseInformal(digits: [String], markers: [String])
    }

    let system: System
    var suffix = ". "
    var negative = "-"
    /// The `pad` descriptor: the minimum length in grapheme clusters, negative
    /// sign included, and the symbol that makes it up.
    var pad: (length: Int, symbol: String)?
    /// nil is `range: auto`, whose extent depends on the system.
    var range: ClosedRange<Int>?
    /// The style that writes a value outside `range`. Only the representation
    /// falls back: the marker keeps this style's suffix, as WebKit builds it
    /// (`listMarkerTextContent` appends the resolved style's suffix to
    /// `text()`, and `text()` is what falls back).
    var fallback = "decimal"

    static let decimal = CounterStyle(system: .numeric((0...9).map(String.init)))

    static let predefined: [String: CounterStyle] = {
        let lowerAlpha = CounterStyle(system: .alphabetic("abcdefghijklmnopqrstuvwxyz".map(String.init)))
        let upperAlpha = CounterStyle(system: .alphabetic("ABCDEFGHIJKLMNOPQRSTUVWXYZ".map(String.init)))
        let chineseDigits = "零一二三四五六七八九".map(String.init)
        // The range is iOS 27.2's. WebKit main widened it to ±9999999999999999
        // on 2026-09-10 (bug 257369, the specification's optional §7.1.2), but
        // the 27.2 runtimes (24B8117, 24B91016s) still ship -9999 9999.
        let tradChineseInformal = CounterStyle(
            system: .chineseInformal(digits: chineseDigits, markers: ["十", "百", "千"]),
            suffix: "、", negative: "負", range: -9999...9999, fallback: "cjk-decimal")
        return [
            "decimal": decimal,
            "decimal-leading-zero": CounterStyle(system: decimal.system, pad: (2, "0")),
            "lower-alpha": lowerAlpha,
            "lower-latin": lowerAlpha,
            "upper-alpha": upperAlpha,
            "upper-latin": upperAlpha,
            "lower-roman": CounterStyle(system: .additive(romanNumerals(uppercase: false)), range: 1...3999),
            "upper-roman": CounterStyle(system: .additive(romanNumerals(uppercase: true)), range: 1...3999),
            "disc": CounterStyle(system: .bullet(.disc)),
            "circle": CounterStyle(system: .bullet(.circle)),
            "square": CounterStyle(system: .bullet(.square)),
            "cjk-decimal": CounterStyle(
                system: .numeric("〇一二三四五六七八九".map(String.init)), suffix: "、", range: 0...Int.max),
            "trad-chinese-informal": tradChineseInformal,
            // Identical to trad-chinese-informal by definition.
            "cjk-ideographic": tradChineseInformal,
            "simp-chinese-informal": CounterStyle(
                system: .chineseInformal(digits: chineseDigits, markers: ["十", "百", "千"]),
                suffix: "、", negative: "负", range: -9999...9999, fallback: "cjk-decimal"),
        ]
    }()

    private static func romanNumerals(uppercase: Bool) -> [(weight: Int, symbol: String)] {
        let numerals: [(Int, String)] = [
            (1000, "m"), (900, "cm"), (500, "d"), (400, "cd"), (100, "c"), (90, "xc"),
            (50, "l"), (40, "xl"), (10, "x"), (9, "ix"), (5, "v"), (4, "iv"), (1, "i"),
        ]
        return numerals.map { (weight: $0.0, symbol: uppercase ? $0.1.uppercased() : $0.1) }
    }

    /// CSS Counter Styles 3 "generate a counter representation", without the
    /// suffix. Every system here uses a negative sign, so a negative value is
    /// written from its magnitude and then signed.
    func representation(of value: Int) -> String {
        guard contains(value), var text = initialRepresentation(of: value.magnitude) else {
            return (Self.predefined[fallback] ?? Self.decimal).representation(of: value)
        }
        let isNegative = value < 0
        if let pad {
            let missing = pad.length - text.count - (isNegative ? negative.count : 0)
            if missing > 0 { text = String(repeating: pad.symbol, count: missing) + text }
        }
        return isNegative ? negative + text : text
    }

    private func contains(_ value: Int) -> Bool {
        if let range { return range.contains(value) }
        switch system {
        case .bullet, .numeric, .chineseInformal: return true
        case .alphabetic: return value >= 1
        case .additive: return value >= 0
        }
    }

    /// nil when the system cannot write the value, which falls back.
    private func initialRepresentation(of magnitude: UInt) -> String? {
        switch system {
        case .bullet:
            return nil
        case .numeric(let symbols):
            let base = UInt(symbols.count)
            var value = magnitude
            var text = symbols[Int(value % base)]
            value /= base
            while value > 0 {
                text = symbols[Int(value % base)] + text
                value /= base
            }
            return text
        case .alphabetic(let symbols):
            let base = UInt(symbols.count)
            var value = magnitude
            var text = ""
            while value > 0 {
                value -= 1
                text = symbols[Int(value % base)] + text
                value /= base
            }
            return text
        case .additive(let symbols):
            var value = Int(magnitude)
            var text = ""
            for (weight, symbol) in symbols where weight > 0 && value >= weight {
                text += String(repeating: symbol, count: value / weight)
                value %= weight
            }
            return value == 0 && !text.isEmpty ? text : nil
        case .chineseInformal(let digits, let markers):
            return Self.chineseInformal(magnitude, digits: digits, markers: markers)
        }
    }

    /// §7.1.3 for one group of up to four digits (the range keeps it there):
    /// every non-zero digit takes its place's marker, 10–19 drop the tens
    /// digit, trailing zeros go, and runs of zeros collapse into one.
    private static func chineseInformal(_ magnitude: UInt, digits: [String], markers: [String]) -> String {
        if magnitude == 0 { return digits[0] }
        let places = String(magnitude).map { $0.wholeNumberValue! }
        var text: [(digit: Int?, symbol: String)] = []
        for (index, digit) in places.enumerated() {
            let place = places.count - 1 - index
            if magnitude >= 10, magnitude <= 19, place == 1 {
                text.append((nil, markers[0]))
                continue
            }
            text.append((digit, digits[digit]))
            if digit != 0, place > 0 { text.append((nil, markers[place - 1])) }
        }
        while text.last?.digit == 0 { text.removeLast() }
        var result = ""
        var previousWasZero = false
        for (digit, symbol) in text {
            let isZero = digit == 0
            if !(isZero && previousWasZero) { result += symbol }
            previousWasZero = isZero
        }
        return result
    }
}
