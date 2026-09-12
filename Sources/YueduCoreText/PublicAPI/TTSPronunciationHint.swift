import Foundation

public struct TTSPronunciationHint: Equatable {
    public let range: NSRange
    public let ipa: String
    /// Orthographic ruby reading (kana, bopomofo, etc.), never mislabeled as IPA.
    public let reading: String?

    public init(range: NSRange, ipa: String) {
        self.range = range
        self.ipa = ipa
        self.reading = nil
    }

    public init(range: NSRange, reading: String) {
        self.range = range
        self.ipa = ""
        self.reading = reading
    }

    public func rebased(to range: NSRange) -> Self {
        if let reading { return Self(range: range, reading: reading) }
        return Self(range: range, ipa: ipa)
    }
}
