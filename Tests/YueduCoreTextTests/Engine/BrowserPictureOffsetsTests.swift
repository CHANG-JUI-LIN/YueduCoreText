import Foundation
import Testing
@testable import YueduCoreText

/// The map from offsets saved against 0.10's source text, where a picture had a place but
/// no extent, to 0.11's, where it has one U+FFFC.
@Suite("Offsets saved before pictures took up source text")
struct BrowserPictureOffsetsTests {
    /// "前文" ⟨picture⟩ "图注": 0.10 "前文图注", 0.11 "前文\u{FFFC}图注".
    private let one = BrowserPictureOffsets([2])
    /// "甲" ⟨picture⟩⟨picture⟩ "乙丙" ⟨picture⟩: 0.10 "甲乙丙", 0.11 "甲\u{FFFC}\u{FFFC}乙丙\u{FFFC}".
    private let three = BrowserPictureOffsets([1, 2, 5])

    @Test("an offset moves past the pictures at or before it")
    func offsets() {
        #expect((0...4).map(one.migrated) == [0, 1, 3, 4, 5])
        #expect((0...3).map(three.migrated) == [0, 3, 4, 6])
        #expect(BrowserPictureOffsets([]).migrated(7) == 7)
    }

    /// The text a 0.10 offset named is the text its 0.11 offset names.
    @Test("a migrated offset names the same character")
    func sameCharacter() {
        let old = "甲乙丙" as NSString
        let new = "甲\u{FFFC}\u{FFFC}乙丙\u{FFFC}" as NSString
        for offset in 0..<old.length {
            #expect(new.character(at: three.migrated(offset)) == old.character(at: offset))
        }
    }

    @Test("a range keeps its characters and takes in the pictures inside it")
    func ranges() {
        // "前文", "图注", "文图" (straddles the picture), "前文图注" (all of it).
        #expect(one.migrated(NSRange(location: 0, length: 2)) == NSRange(location: 0, length: 2))
        #expect(one.migrated(NSRange(location: 2, length: 2)) == NSRange(location: 3, length: 2))
        #expect(one.migrated(NSRange(location: 1, length: 2)) == NSRange(location: 1, length: 3))
        #expect(one.migrated(NSRange(location: 0, length: 4)) == NSRange(location: 0, length: 5))
        // "乙丙" ends where the last picture stands: the picture stays out.
        #expect(three.migrated(NSRange(location: 1, length: 2)) == NSRange(location: 3, length: 2))
        #expect(one.migrated(NSRange(location: 2, length: 0)) == NSRange(location: 3, length: 0))
    }

    @Test("unmigrated is the inverse, except on a picture")
    func inverse() {
        for offset in 0...3 {
            #expect(three.unmigrated(three.migrated(offset)) == offset)
        }
        // On a picture: its old place, which names the text after it.
        #expect(three.unmigrated(2) == 1)
        #expect(three.migrated(three.unmigrated(2)) == 3)
    }
}
