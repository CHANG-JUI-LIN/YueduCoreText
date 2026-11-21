import Foundation
import Testing
import UIKit
@testable import YueduCoreText

/// Layout recurses once per level of nesting, and the app lays chapters out on threads with
/// a 512 KB stack. An unoptimized build copies a whole `ComputedStyle` (over a kilobyte) for
/// every `node.style.x` it reads: with those reads inline, building the box tree took 57 KB
/// a level and seven nested `<div>`s overflowed (about ten fit now, fewer on toolchains with larger frames). The test process dies if this regresses.
struct NestingStackTests {
    @Test(arguments: [
        ("<div>", "</div>", 6),
        // Two boxes a level, and the line that holds each inline-block is laid out in between.
        ("<span style=\"display:inline-block\"><div>", "</div></span>", 3),
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
