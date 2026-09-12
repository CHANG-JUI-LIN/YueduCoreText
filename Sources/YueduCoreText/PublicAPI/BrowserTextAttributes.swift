import Foundation

public enum BrowserTextAttributes {
    public static let preservedForeground = NSAttributedString.Key("YDRegexHighlightOriginalAttributes")
    public static let ipaPronunciation = NSAttributedString.Key("ReaderIPAPronunciation")
}

public enum AuthoredPronunciation {
    public static func hints(in text: NSAttributedString) -> [TTSPronunciationHint] {
        var hints: [TTSPronunciationHint] = []
        text.enumerateAttribute(BrowserTextAttributes.ipaPronunciation,
            in: NSRange(location: 0, length: text.length)) { value, range, _ in
            guard let ipa = value as? String, !ipa.isEmpty else { return }
            hints.append(TTSPronunciationHint(range: range, ipa: ipa))
        }
        return hints
    }
}
