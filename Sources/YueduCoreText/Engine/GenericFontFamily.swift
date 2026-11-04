import UIKit

/// The CSS generic font families as WebKit on iOS 27.2 draws them. A generic
/// family follows the content language: with one, Core Text's choice for that
/// language; with none, WebKit's own settings (`SettingsBaseCocoa.mm`, and its
/// preferences for `cursive` and `fantasy`).
///
/// Measured in a WKWebView (S001 ua-q-h): the 17px advance of
/// "Hamburgefonstiv" and the inline box's ascent and height name the face.
///
/// | language        | serif               | sans-serif         | cursive        | fantasy        | monospace |
/// |-----------------|---------------------|--------------------|----------------|----------------|-----------|
/// | none            | Times New Roman     | Helvetica          | Snell Roundhand | Papyrus       | Courier   |
/// | zh (any)        | PingFang            | PingFang           | PingFang       | PingFang       | Menlo     |
/// | ja              | Hiragino Mincho W3  | Hiragino Sans W4   | Hiragino Mincho W3 | Hiragino Mincho W3 | Menlo |
/// | ko              | Apple SD Gothic Neo | Apple SD Gothic Neo | Apple SD Gothic Neo | Apple SD Gothic Neo | Menlo |
/// | en, fr, und     | Times New Roman     | Helvetica          | Snell Roundhand | Zapfino       | Menlo     |
/// | ru              | Times New Roman     | Helvetica          | Snell Roundhand | Snell Roundhand | Menlo   |
///
/// `system-ui` is the system font in every language. The PingFang widths are
/// the same in all four regional cuts, so which one WebKit takes is not
/// observable; each region gets its own.
enum GenericFontFamily {

    static func font(named family: String, language: String?, size: CGFloat) -> UIFont? {
        let generic = family.lowercased()
        switch generic {
        case "system-ui", "-apple-system", "ui-sans-serif":
            return UIFont.systemFont(ofSize: size)
        case "ui-serif", "ui-rounded":
            let design: UIFontDescriptor.SystemDesign = generic == "ui-serif" ? .serif : .rounded
            let base = UIFont.systemFont(ofSize: size)
            return base.fontDescriptor.withDesign(design).map { UIFont(descriptor: $0, size: size) } ?? base
        case "ui-monospace":
            return UIFont.monospacedSystemFont(ofSize: size, weight: .regular)
        case "serif", "sans-serif", "cursive", "fantasy", "monospace":
            return postScriptName(generic, language: language).flatMap { UIFont(name: $0, size: size) }
        default:
            return nil
        }
    }

    /// Whether `family` names a generic family rather than a face.
    static func isGeneric(_ family: String) -> Bool {
        ["serif", "sans-serif", "cursive", "fantasy", "monospace", "system-ui", "-apple-system",
         "ui-serif", "ui-sans-serif", "ui-monospace", "ui-rounded"].contains(family.lowercased())
    }

    private static func postScriptName(_ generic: String, language: String?) -> String? {
        let subtags = (language ?? "").lowercased().split(separator: "-").map(String.init)
        guard let primary = subtags.first, !primary.isEmpty else {
            return ["serif": "TimesNewRomanPSMT", "sans-serif": "Helvetica", "cursive": "SnellRoundhand",
                    "fantasy": "Papyrus", "monospace": "Courier"][generic]
        }
        if generic == "monospace" { return "Menlo-Regular" }
        switch primary {
        case "zh":
            if subtags.contains("hk") { return "PingFangHK-Regular" }
            if subtags.contains("mo") { return "PingFangMO-Regular" }
            if subtags.contains("hant") || subtags.contains("tw") { return "PingFangTC-Regular" }
            return "PingFangSC-Regular"
        case "ja":
            return generic == "sans-serif" ? "HiraginoSans-W4" : "HiraMinProN-W3"
        case "ko":
            return "AppleSDGothicNeo-Regular"
        default:
            return ["serif": "TimesNewRomanPSMT", "sans-serif": "Helvetica", "cursive": "SnellRoundhand",
                    "fantasy": primary == "ru" ? "SnellRoundhand" : "Zapfino"][generic]
        }
    }
}
