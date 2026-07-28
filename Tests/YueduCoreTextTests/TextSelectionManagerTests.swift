import Foundation
import Testing
import YueduCoreText

@Suite("Text selection manager public API")
struct TextSelectionManagerTests {
    @Test("Creates a forward selection")
    func createsForwardSelection() {
        let manager = TextSelectionManager()

        manager.beginSelection(at: 2, maxLength: 10)
        manager.updateSelection(to: 5, maxLength: 10)

        #expect(manager.anchorIndex == 2)
        #expect(manager.focusIndex == 5)
        #expect(manager.selectedRange == NSRange(location: 2, length: 4))
        #expect(manager.hasSelection)
        let bounds = manager.selectionBounds
        #expect(bounds?.start == 2)
        #expect(bounds?.end == 5)
    }

    @Test("Creates a reverse selection")
    func createsReverseSelection() {
        let manager = TextSelectionManager()

        manager.beginSelection(at: 5, maxLength: 10)
        manager.updateSelection(to: 2, maxLength: 10)

        #expect(manager.anchorIndex == 5)
        #expect(manager.focusIndex == 2)
        #expect(manager.selectedRange == NSRange(location: 2, length: 4))
        let bounds = manager.selectionBounds
        #expect(bounds?.start == 2)
        #expect(bounds?.end == 5)
    }

    @Test(
        "Clamps selection start indexes",
        arguments: [
            (index: -4, expected: 0),
            (index: 12, expected: 4),
        ]
    )
    func clampsSelectionStart(index: Int, expected: Int) {
        let manager = TextSelectionManager()

        manager.beginSelection(at: index, maxLength: 5)

        #expect(manager.anchorIndex == expected)
        #expect(manager.focusIndex == expected)
        #expect(manager.selectedRange == NSRange(location: expected, length: 1))
    }

    @Test(
        "Clamps selection updates",
        arguments: [
            (index: -4, expected: 0),
            (index: 12, expected: 4),
        ]
    )
    func clampsSelectionUpdate(index: Int, expected: Int) {
        let manager = TextSelectionManager()
        manager.beginSelection(at: 2, maxLength: 5)

        manager.updateSelection(to: index, maxLength: 5)

        #expect(manager.focusIndex == expected)
    }

    @Test("Clears when setSelection receives an invalid maximum length")
    func clearsForInvalidMaximumLength() {
        let manager = TextSelectionManager()
        manager.beginSelection(at: 1, maxLength: 3)

        manager.setSelection(range: NSRange(location: 0, length: 1), maxLength: 0)

        #expect(!manager.hasSelection)
    }

    @Test("Clears when setSelection receives an empty range")
    func clearsForEmptyRange() {
        let manager = TextSelectionManager()
        manager.beginSelection(at: 1, maxLength: 3)

        manager.setSelection(range: NSRange(location: 1, length: 0), maxLength: 3)

        #expect(!manager.hasSelection)
    }

    @Test("Clears when setSelection range arithmetic would overflow")
    func clearsForOverflowingRange() {
        let manager = TextSelectionManager()
        manager.beginSelection(at: 1, maxLength: 3)

        manager.setSelection(
            range: NSRange(location: Int.max, length: 2),
            maxLength: Int.max
        )

        #expect(!manager.hasSelection)
    }

    @Test("Clears when setSelection receives NSNotFound")
    func clearsWhenSetSelectionReceivesNotFound() {
        let manager = TextSelectionManager()
        manager.beginSelection(at: 1, maxLength: 3)

        manager.setSelection(
            range: NSRange(location: NSNotFound, length: 1),
            maxLength: 3
        )

        #expect(manager.selectedRange == nil)
    }

    @Test("Clears when beginSelection receives NSNotFound")
    func clearsWhenBeginSelectionReceivesNotFound() {
        let manager = TextSelectionManager()
        manager.beginSelection(at: 1, maxLength: 3)

        manager.beginSelection(at: NSNotFound, maxLength: 3)

        #expect(manager.selectedRange == nil)
    }

    @Test("Ignores NSNotFound selection updates")
    func ignoresNotFoundSelectionUpdate() {
        let manager = TextSelectionManager()
        manager.beginSelection(at: 1, maxLength: 4)

        manager.updateSelection(to: NSNotFound, maxLength: 4)

        #expect(manager.anchorIndex == 1)
        #expect(manager.focusIndex == 1)
    }

    @Test("Ignores NSNotFound start handle updates")
    func ignoresNotFoundStartHandleUpdate() {
        let manager = TextSelectionManager()
        manager.setSelection(range: NSRange(location: 1, length: 2), maxLength: 4)

        manager.updateSelectionStart(to: NSNotFound, maxLength: 4)

        #expect(manager.anchorIndex == 1)
        #expect(manager.focusIndex == 2)
    }

    @Test("Ignores NSNotFound end handle updates")
    func ignoresNotFoundEndHandleUpdate() {
        let manager = TextSelectionManager()
        manager.setSelection(range: NSRange(location: 1, length: 2), maxLength: 4)

        manager.updateSelectionEnd(to: NSNotFound, maxLength: 4)

        #expect(manager.anchorIndex == 1)
        #expect(manager.focusIndex == 2)
    }

    @Test(
        "Clears when beginSelection receives a nonpositive content length",
        arguments: [0, -1]
    )
    func clearsWhenBeginSelectionReceivesEmptyContent(maxLength: Int) {
        let manager = TextSelectionManager()
        manager.beginSelection(at: 1, maxLength: 3)

        manager.beginSelection(at: 0, maxLength: maxLength)

        #expect(manager.selectedRange == nil)
    }

    @Test(
        "Clears when updateSelection receives a nonpositive content length",
        arguments: [0, -1]
    )
    func clearsWhenUpdateSelectionReceivesEmptyContent(maxLength: Int) {
        let manager = TextSelectionManager()
        manager.beginSelection(at: 1, maxLength: 3)

        manager.updateSelection(to: 0, maxLength: maxLength)

        #expect(manager.selectedRange == nil)
    }

    @Test(
        "Clears when start handle update receives a nonpositive content length",
        arguments: [0, -1]
    )
    func clearsWhenStartHandleUpdateReceivesEmptyContent(maxLength: Int) {
        let manager = TextSelectionManager()
        manager.setSelection(range: NSRange(location: 1, length: 2), maxLength: 4)

        manager.updateSelectionStart(to: 0, maxLength: maxLength)

        #expect(manager.selectedRange == nil)
    }

    @Test(
        "Clears when end handle update receives a nonpositive content length",
        arguments: [0, -1]
    )
    func clearsWhenEndHandleUpdateReceivesEmptyContent(maxLength: Int) {
        let manager = TextSelectionManager()
        manager.setSelection(range: NSRange(location: 1, length: 2), maxLength: 4)

        manager.updateSelectionEnd(to: 0, maxLength: maxLength)

        #expect(manager.selectedRange == nil)
    }

    @Test("Start handle keeps its identity across consecutive crossings")
    func startHandleKeepsIdentityAcrossCrossings() {
        let manager = TextSelectionManager()
        manager.setSelection(range: NSRange(location: 2, length: 3), maxLength: 10)

        manager.updateSelectionStart(to: 7, maxLength: 10)

        #expect(manager.anchorIndex == 7)
        #expect(manager.focusIndex == 4)
        #expect(manager.selectedRange == NSRange(location: 4, length: 4))

        manager.updateSelectionStart(to: 8, maxLength: 10)

        #expect(manager.anchorIndex == 8)
        #expect(manager.focusIndex == 4)
        #expect(manager.selectedRange == NSRange(location: 4, length: 5))
    }

    @Test("End handle keeps its identity across consecutive crossings")
    func endHandleKeepsIdentityAcrossCrossings() {
        let manager = TextSelectionManager()
        manager.setSelection(range: NSRange(location: 4, length: 3), maxLength: 10)

        manager.updateSelectionEnd(to: 2, maxLength: 10)

        #expect(manager.anchorIndex == 4)
        #expect(manager.focusIndex == 2)
        #expect(manager.selectedRange == NSRange(location: 2, length: 3))

        manager.updateSelectionEnd(to: 1, maxLength: 10)

        #expect(manager.anchorIndex == 4)
        #expect(manager.focusIndex == 1)
        #expect(manager.selectedRange == NSRange(location: 1, length: 4))
    }

    @Test("Clears all selection state")
    func clearsSelection() {
        let manager = TextSelectionManager()
        manager.beginSelection(at: 2, maxLength: 5)

        manager.clear()

        #expect(manager.anchorIndex == nil)
        #expect(manager.focusIndex == nil)
        #expect(manager.selectedRange == nil)
        #expect(manager.selectionBounds == nil)
        #expect(!manager.hasSelection)
    }

    @Test("Extracts selected text using UTF-16 indexes")
    func extractsEmojiUsingUTF16Indexes() {
        let manager = TextSelectionManager()
        manager.setSelection(range: NSRange(location: 1, length: 2), maxLength: 4)
        let attributedString = NSAttributedString(string: "A😀中")

        #expect(manager.selectedText(in: attributedString) == "😀")
    }

    @Test("Returns nil when selection exceeds the attributed string")
    func rejectsSelectionOutsideAttributedString() {
        let manager = TextSelectionManager()
        manager.setSelection(range: NSRange(location: 1, length: 3), maxLength: 4)

        #expect(manager.selectedText(in: NSAttributedString(string: "ab")) == nil)
    }
}
