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

/// What each level of nesting costs, read off the stack itself: a fresh thread's stack is
/// zero pages, so the lowest byte layout wrote is how deep it went. Measured on Xcode 27, a
/// nested block takes 20 KB a level and a nested flex container, which is laid out by
/// `FlexLayout` between two `BlockLayout` frames, 23 KB. The CI toolchain's frames are about
/// half as large again; the limit leaves room for that and fails before a stack does.
struct NestingStackCostTests {
    private static func stackUsed(open: String, close: String, depth: Int) -> Int {
        let html = "<html><body>" + String(repeating: open, count: depth) + "<p>x</p>"
            + String(repeating: close, count: depth) + "</body></html>"
        let done = DispatchSemaphore(value: 0)
        let used = LockedCount()
        let thread = Thread {
            let me = pthread_self()
            let top = UInt(bitPattern: pthread_get_stackaddr_np(me))
            let config = BrowserLayoutConfig(renderWidth: 350, renderHeight: 800, rootFontSize: 17,
                                             fontFamilies: ["PingFangSC-Regular"], textColor: .black, backgroundColor: .white)
            let document = BrowserLayoutDocument(html: html, cssTexts: [], config: config, imageLoader: { _ in nil })
            _ = try? document.makeLayout(containerSize: CGSize(width: 350, height: 800))
            var address = top - UInt(pthread_get_stacksize_np(me))
            while address < top, UnsafePointer<UInt8>(bitPattern: address)?.pointee == 0 { address += 1 }
            used.set(Int(top - address))
            done.signal()
        }
        thread.stackSize = 8 * 1024 * 1024
        thread.start()
        done.wait()
        return used.value
    }

    @Test(arguments: [
        ("<div>", "</div>"),
        ("<div style=\"display:flex\">", "</div>"),
        ("<div style=\"display:flex;flex-direction:column\"><span>a</span>", "</div>"),
    ])
    func aLevelOfNestingStaysWithinItsShare(open: String, close: String) {
        let perLevel = (Self.stackUsed(open: open, close: close, depth: 8)
            - Self.stackUsed(open: open, close: close, depth: 4)) / 4
        // In the log, so a toolchain's figures can be read off a run.
        print("stack use, \(open): \(Self.stackUsed(open: open, close: close, depth: 1) / 1024) KB at depth 1, \(Self.stackUsed(open: open, close: close, depth: 4) / 1024) KB at depth 4, \(perLevel / 1024) KB a level")
        #expect(perLevel > 0)
        #expect(perLevel < 40 * 1024, "\(open): \(perLevel / 1024) KB a level")
    }
}

private final class LockedCount: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func set(_ value: Int) { lock.lock(); count = value; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
}

private final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false
    func set() { lock.lock(); flag = true; lock.unlock() }
    var value: Bool { lock.lock(); defer { lock.unlock() }; return flag }
}
