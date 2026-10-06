import Foundation
import Testing
@testable import YueduCoreTextTypography

@Suite("UAX #50 vertical orientation")
struct VerticalOrientationTests {
    @Test("Latin letters, ASCII digits and ASCII punctuation are set sideways", arguments: ["A", "z", "0", "9", "(", "-"])
    func rotated(character: Character) {
        #expect(VerticalOrientation.of(character) == .rotated)
    }

    @Test("Han, kana and full-width letters and digits stand upright", arguments: ["あ", "ア", "漢", "Ａ", "０", "①", "※", "・", "\u{3000}"])
    func upright(character: Character) {
        #expect(VerticalOrientation.of(character) == .upright)
    }

    @Test("Full-width commas, stops, question and exclamation marks are Tu", arguments: ["。", "、", "，", "？", "！"])
    func transformedUpright(character: Character) {
        #expect(VerticalOrientation.of(character) == .transformedUpright)
    }

    @Test("Brackets, the long vowel mark, colon and semicolon are Tr", arguments: ["（", "）", "「", "」", "『", "ー", "：", "；", "〜"])
    func transformedRotated(character: Character) {
        #expect(VerticalOrientation.of(character) == .transformedRotated)
    }

    @Test("The em dash and the ellipsis turn along the column")
    func dashAndEllipsis() {
        // R in VerticalOrientation-18.0.0.txt: in a column, —— reads as a vertical line
        // and …… as vertical dots, which is what Chinese and Japanese vertical text wants.
        #expect(VerticalOrientation.of(Character("\u{2014}")) == .rotated)
        #expect(VerticalOrientation.of(Character("\u{2026}")) == .rotated)
    }

    @Test("Code points the data does not list are R, its @missing default")
    func unlistedDefaultsToRotated() {
        // Unassigned, and absent from VerticalOrientation-18.0.0.txt. (Private-use
        // planes are listed: the data sets them upright.)
        #expect(VerticalOrientation.of(Unicode.Scalar(0x0378)!) == .rotated)
        #expect(VerticalOrientation.of(Unicode.Scalar(0x40000)!) == .rotated)
        #expect(VerticalOrientation.of(Unicode.Scalar(0x10FFFD)!) == .upright)
    }

    @Test("The table's ranges are sorted and do not overlap")
    func tableIsSorted() {
        for (previous, next) in zip(VerticalOrientation.ranges, VerticalOrientation.ranges.dropFirst()) {
            #expect(previous.upper < next.lower)
            #expect(previous.value != .rotated)
        }
        #expect(VerticalOrientation.unicodeVersion == "18.0.0")
    }
}
