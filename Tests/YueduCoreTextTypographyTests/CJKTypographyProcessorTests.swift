import Foundation
import Testing
import UIKit
@testable import YueduCoreTextTypography

@Suite("CJK punctuation post-processor")
struct CJKTypographyProcessorTests {
    @Test("Spacing is the CJK pass's: the processor leaves every kern as it found it")
    func leavesSpacingAlone() {
        for sample in ["」「", "。，", "】【。", "《《", "……】"] {
            let input = NSMutableAttributedString(string: sample, attributes: [.font: UIFont.systemFont(ofSize: 20)])
            input.addAttribute(.kern, value: -3, range: NSRange(location: 0, length: 1))
            #expect(CJKTypographyProcessor.apply(to: input).isEqual(to: input), "\(sample)")
        }
    }
}
