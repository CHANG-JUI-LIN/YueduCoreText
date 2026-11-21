import Foundation
import Testing
import UIKit
@testable import YueduCoreText

/// Layout recurses once per level of nesting, and the app lays chapters out on threads with
/// a 512 KB stack. An unoptimized build copies a whole `ComputedStyle` (a kilobyte) for every
/// `node.style.x` it reads and a whole `InlineRun` (2.4 KB) for every run it touches. Measured
/// on Xcode 27, the innermost block's lines take about 190 KB and each level of nesting 20 KB
/// more (the box-tree builder took 57 KB a level until its style reads moved out of it); the
/// CI toolchain's frames are about half as large again. These depths fit both. The test
/// process dies when one stops fitting: the first thing to check is what grew
/// `ComputedStyle`, `InlineRun`, `BlockLayout.layOut` or `InlineLayout.layoutLines`.
struct NestingStackTests {
    @Test(arguments: [
        ("<div>", "</div>", 4),
        // Two boxes a level, and the line that holds each inline-block is laid out in between.
        ("<span style=\"display:inline-block\"><div>", "</div></span>", 2),
    ])
    func nestedBlocksFitASecondaryThreadsStack(open: String, close: String, depth: Int) {
        let html = "<html><body>" + String(repeating: open, count: depth) + "<p>x</p>"
            + String(repeating: close, count: depth) + "</body></html>"
        let done = DispatchSemaphore(value: 0)
        let laidOut = LockedFlag()
        let thread = Thread {
            let config = BrowserLayoutConfig(renderWidth: 350, renderHeight: 800, rootFontSize: 17,
                                             fontFamilies: ["PingFangSC-Regular"], textColor: .black, backgroundColor: .white)
            let document = BrowserLayoutDocument(html: html, cssTexts: [], config: config, imageLoader: { _ in nil })
            if (try? document.makeLayout(containerSize: CGSize(width: 350, height: 800))) != nil { laidOut.set() }
            done.signal()
        }
        thread.stackSize = 512 * 1024
        thread.start()
        done.wait()
        #expect(laidOut.value)
    }
}

private final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false
    func set() { lock.lock(); flag = true; lock.unlock() }
    var value: Bool { lock.lock(); defer { lock.unlock() }; return flag }
}
