import Foundation

/// An opaque sRGB colour, 8 bits a channel.
public struct CSSRGB: Equatable, Sendable {
    public let red: UInt8
    public let green: UInt8
    public let blue: UInt8

    public init(_ red: UInt8, _ green: UInt8, _ blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }
}

/// CSS Color 4 §6.1 named colours, and the HTML Standard's legacy colour
/// parsing used by presentational attributes.
public enum CSSNamedColors {
    /// Every CSS named colour, by lowercase name.
    public static let table: [String: CSSRGB] = [
        "aliceblue": CSSRGB(240, 248, 255), "antiquewhite": CSSRGB(250, 235, 215), "aqua": CSSRGB(0, 255, 255),
        "aquamarine": CSSRGB(127, 255, 212), "azure": CSSRGB(240, 255, 255), "beige": CSSRGB(245, 245, 220),
        "bisque": CSSRGB(255, 228, 196), "black": CSSRGB(0, 0, 0), "blanchedalmond": CSSRGB(255, 235, 205),
        "blue": CSSRGB(0, 0, 255), "blueviolet": CSSRGB(138, 43, 226), "brown": CSSRGB(165, 42, 42),
        "burlywood": CSSRGB(222, 184, 135), "cadetblue": CSSRGB(95, 158, 160), "chartreuse": CSSRGB(127, 255, 0),
        "chocolate": CSSRGB(210, 105, 30), "coral": CSSRGB(255, 127, 80), "cornflowerblue": CSSRGB(100, 149, 237),
        "cornsilk": CSSRGB(255, 248, 220), "crimson": CSSRGB(220, 20, 60), "cyan": CSSRGB(0, 255, 255),
        "darkblue": CSSRGB(0, 0, 139), "darkcyan": CSSRGB(0, 139, 139), "darkgoldenrod": CSSRGB(184, 134, 11),
        "darkgray": CSSRGB(169, 169, 169), "darkgreen": CSSRGB(0, 100, 0), "darkgrey": CSSRGB(169, 169, 169),
        "darkkhaki": CSSRGB(189, 183, 107), "darkmagenta": CSSRGB(139, 0, 139), "darkolivegreen": CSSRGB(85, 107, 47),
        "darkorange": CSSRGB(255, 140, 0), "darkorchid": CSSRGB(153, 50, 204), "darkred": CSSRGB(139, 0, 0),
        "darksalmon": CSSRGB(233, 150, 122), "darkseagreen": CSSRGB(143, 188, 143), "darkslateblue": CSSRGB(72, 61, 139),
        "darkslategray": CSSRGB(47, 79, 79), "darkslategrey": CSSRGB(47, 79, 79), "darkturquoise": CSSRGB(0, 206, 209),
        "darkviolet": CSSRGB(148, 0, 211), "deeppink": CSSRGB(255, 20, 147), "deepskyblue": CSSRGB(0, 191, 255),
        "dimgray": CSSRGB(105, 105, 105), "dimgrey": CSSRGB(105, 105, 105), "dodgerblue": CSSRGB(30, 144, 255),
        "firebrick": CSSRGB(178, 34, 34), "floralwhite": CSSRGB(255, 250, 240), "forestgreen": CSSRGB(34, 139, 34),
        "fuchsia": CSSRGB(255, 0, 255), "gainsboro": CSSRGB(220, 220, 220), "ghostwhite": CSSRGB(248, 248, 255),
        "gold": CSSRGB(255, 215, 0), "goldenrod": CSSRGB(218, 165, 32), "gray": CSSRGB(128, 128, 128),
        "green": CSSRGB(0, 128, 0), "greenyellow": CSSRGB(173, 255, 47), "grey": CSSRGB(128, 128, 128),
        "honeydew": CSSRGB(240, 255, 240), "hotpink": CSSRGB(255, 105, 180), "indianred": CSSRGB(205, 92, 92),
        "indigo": CSSRGB(75, 0, 130), "ivory": CSSRGB(255, 255, 240), "khaki": CSSRGB(240, 230, 140),
        "lavender": CSSRGB(230, 230, 250), "lavenderblush": CSSRGB(255, 240, 245), "lawngreen": CSSRGB(124, 252, 0),
        "lemonchiffon": CSSRGB(255, 250, 205), "lightblue": CSSRGB(173, 216, 230), "lightcoral": CSSRGB(240, 128, 128),
        "lightcyan": CSSRGB(224, 255, 255), "lightgoldenrodyellow": CSSRGB(250, 250, 210), "lightgray": CSSRGB(211, 211, 211),
        "lightgreen": CSSRGB(144, 238, 144), "lightgrey": CSSRGB(211, 211, 211), "lightpink": CSSRGB(255, 182, 193),
        "lightsalmon": CSSRGB(255, 160, 122), "lightseagreen": CSSRGB(32, 178, 170), "lightskyblue": CSSRGB(135, 206, 250),
        "lightslategray": CSSRGB(119, 136, 153), "lightslategrey": CSSRGB(119, 136, 153), "lightsteelblue": CSSRGB(176, 196, 222),
        "lightyellow": CSSRGB(255, 255, 224), "lime": CSSRGB(0, 255, 0), "limegreen": CSSRGB(50, 205, 50),
        "linen": CSSRGB(250, 240, 230), "magenta": CSSRGB(255, 0, 255), "maroon": CSSRGB(128, 0, 0),
        "mediumaquamarine": CSSRGB(102, 205, 170), "mediumblue": CSSRGB(0, 0, 205), "mediumorchid": CSSRGB(186, 85, 211),
        "mediumpurple": CSSRGB(147, 112, 219), "mediumseagreen": CSSRGB(60, 179, 113), "mediumslateblue": CSSRGB(123, 104, 238),
        "mediumspringgreen": CSSRGB(0, 250, 154), "mediumturquoise": CSSRGB(72, 209, 204), "mediumvioletred": CSSRGB(199, 21, 133),
        "midnightblue": CSSRGB(25, 25, 112), "mintcream": CSSRGB(245, 255, 250), "mistyrose": CSSRGB(255, 228, 225),
        "moccasin": CSSRGB(255, 228, 181), "navajowhite": CSSRGB(255, 222, 173), "navy": CSSRGB(0, 0, 128),
        "oldlace": CSSRGB(253, 245, 230), "olive": CSSRGB(128, 128, 0), "olivedrab": CSSRGB(107, 142, 35),
        "orange": CSSRGB(255, 165, 0), "orangered": CSSRGB(255, 69, 0), "orchid": CSSRGB(218, 112, 214),
        "palegoldenrod": CSSRGB(238, 232, 170), "palegreen": CSSRGB(152, 251, 152), "paleturquoise": CSSRGB(175, 238, 238),
        "palevioletred": CSSRGB(219, 112, 147), "papayawhip": CSSRGB(255, 239, 213), "peachpuff": CSSRGB(255, 218, 185),
        "peru": CSSRGB(205, 133, 63), "pink": CSSRGB(255, 192, 203), "plum": CSSRGB(221, 160, 221),
        "powderblue": CSSRGB(176, 224, 230), "purple": CSSRGB(128, 0, 128), "rebeccapurple": CSSRGB(102, 51, 153),
        "red": CSSRGB(255, 0, 0), "rosybrown": CSSRGB(188, 143, 143), "royalblue": CSSRGB(65, 105, 225),
        "saddlebrown": CSSRGB(139, 69, 19), "salmon": CSSRGB(250, 128, 114), "sandybrown": CSSRGB(244, 164, 96),
        "seagreen": CSSRGB(46, 139, 87), "seashell": CSSRGB(255, 245, 238), "sienna": CSSRGB(160, 82, 45),
        "silver": CSSRGB(192, 192, 192), "skyblue": CSSRGB(135, 206, 235), "slateblue": CSSRGB(106, 90, 205),
        "slategray": CSSRGB(112, 128, 144), "slategrey": CSSRGB(112, 128, 144), "snow": CSSRGB(255, 250, 250),
        "springgreen": CSSRGB(0, 255, 127), "steelblue": CSSRGB(70, 130, 180), "tan": CSSRGB(210, 180, 140),
        "teal": CSSRGB(0, 128, 128), "thistle": CSSRGB(216, 191, 216), "tomato": CSSRGB(255, 99, 71),
        "turquoise": CSSRGB(64, 224, 208), "violet": CSSRGB(238, 130, 238), "wheat": CSSRGB(245, 222, 179),
        "white": CSSRGB(255, 255, 255), "whitesmoke": CSSRGB(245, 245, 245), "yellow": CSSRGB(255, 255, 0),
        "yellowgreen": CSSRGB(154, 205, 50),
    ]

    /// HTML Standard §2.3.6.4 "rules for parsing a legacy colour value", as
    /// `<font color>` and `<hr color>` read it: a named colour or `#rgb`, else
    /// any string turned into hex digits and split in three
    /// (`chucknorris` is rgb(192, 0, 0), `00ff00` green; measured, WebKit iOS
    /// 27.2). nil for an empty value or `transparent`.
    public static func parseLegacy(_ raw: String) -> CSSRGB? {
        let trimmed = raw.trimmingCharacters(in: CharacterSet(charactersIn: " \t\n\u{0C}\r"))
        guard !trimmed.isEmpty, trimmed.lowercased() != "transparent" else { return nil }
        if let named = table[trimmed.lowercased()] { return named }
        let scalars = Array(trimmed.unicodeScalars)
        func hexValue(_ scalar: Unicode.Scalar) -> UInt8? {
            switch scalar.value {
            case 0x30...0x39: return UInt8(scalar.value - 0x30)
            case 0x41...0x46: return UInt8(scalar.value - 0x41 + 10)
            case 0x61...0x66: return UInt8(scalar.value - 0x61 + 10)
            default: return nil
            }
        }
        if scalars.count == 4, scalars[0] == "#",
           let r = hexValue(scalars[1]), let g = hexValue(scalars[2]), let b = hexValue(scalars[3]) {
            return CSSRGB(r * 17, g * 17, b * 17)
        }
        // Characters beyond the BMP become "00"; then at most 128 code units.
        var units: [Character] = []
        for scalar in scalars {
            if scalar.value > 0xFFFF { units.append("0"); units.append("0") } else { units.append(Character(scalar)) }
        }
        if units.count > 128 { units = Array(units.prefix(128)) }
        if units.first == "#" { units.removeFirst() }
        var digits = units.map { character -> Character in
            character.unicodeScalars.first.flatMap(hexValue) != nil ? character : "0"
        }
        while digits.isEmpty || digits.count % 3 != 0 { digits.append("0") }
        var length = digits.count / 3
        var parts = [Array(digits[0..<length]), Array(digits[length..<2 * length]), Array(digits[(2 * length)...])]
        if length > 8 {
            parts = parts.map { Array($0.suffix(8)) }
            length = 8
        }
        while length > 2, parts.allSatisfy({ $0.first == "0" }) {
            parts = parts.map { Array($0.dropFirst()) }
            length -= 1
        }
        if length > 2 { parts = parts.map { Array($0.prefix(2)) } }
        let channels = parts.map { part -> UInt8 in
            // At most two digits are left, so the value fits a byte.
            part.reduce(0) { $0 * 16 + ($1.unicodeScalars.first.flatMap(hexValue) ?? 0) }
        }
        return CSSRGB(channels[0], channels[1], channels[2])
    }
}
