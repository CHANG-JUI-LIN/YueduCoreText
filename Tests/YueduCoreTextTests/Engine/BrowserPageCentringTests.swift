import Testing
import UIKit
@testable import YueduCoreText

/// A title page (`BrowserLayoutConfig.centersSinglePage`, Aozora Bunko's ページの左右中央):
/// a chapter that fits on one page sits in the middle of the page's block axis, top to
/// bottom in horizontal writing and right to left in vertical writing. Everything a page
/// paints and hit-tests comes from its fragments, so the fragments carry the move.
@MainActor
struct BrowserPageCentringTests {
    private static let size = CGSize(width: 300, height: 400)
    private static let insets = UIEdgeInsets(top: 20, left: 16, bottom: 30, right: 24)
    /// No margins anywhere, so the chapter's extent is its lines' and the gaps before
    /// and after them are the whole spare extent.
    private static let css = "body { margin: 0; padding: 0 } p { margin: 0 }"

    private static func config(centred: Bool, writingMode: ReaderWritingMode,
                               paragraphSpacing: CGFloat = 0) -> BrowserLayoutConfig {
        BrowserLayoutConfig(
            renderWidth: size.width - insets.left - insets.right,
            renderHeight: size.height - insets.top - insets.bottom,
            rootFontSize: 17,
            fontFamilies: ["PingFangSC-Regular"],
            contentInsets: insets,
            paragraphSpacing: paragraphSpacing,
            writingMode: writingMode,
            centersSinglePage: centred
        )
    }

    private static let titlePage = "<p>　　　　扉の一行目</p><p>　　　　　　献辞の二行目</p>"
    private static let longChapter = String(repeating: "<p>一頁に収まらない章は、置かれる場所を変えずに頁を送る。</p>", count: 40)

    private static func pages(_ body: String, centred: Bool, writingMode: ReaderWritingMode,
                              css: String = css, paragraphSpacing: CGFloat = 0,
                              html: String? = nil) async throws -> [PageFragments] {
        let doc = BrowserLayoutDocument(
            html: html ?? "<html><body>\(body)</body></html>", cssTexts: [css],
            config: config(centred: centred, writingMode: writingMode, paragraphSpacing: paragraphSpacing),
            imageLoader: { _ in nil })
        return try await doc.renderPages(containerSize: size)
    }

    private static func texts(_ page: PageFragments) -> [TextFragment] {
        BrowserLayoutTestSupport.allTextFragments([page])
    }

    /// The space a page leaves before and after its text along the block axis.
    private static func gaps(_ page: PageFragments, writingMode: ReaderWritingMode) -> (start: CGFloat, end: CGFloat) {
        let rects = texts(page).map(\.rect.rawValue)
        switch writingMode {
        case .horizontal:
            return (rects.map(\.minY).min()! - insets.top, size.height - insets.bottom - rects.map(\.maxY).max()!)
        case .verticalRTL:
            return (size.width - insets.right - rects.map(\.maxX).max()!, rects.map(\.minX).min()! - insets.left)
        }
    }

    @Test(arguments: [ReaderWritingMode.horizontal, .verticalRTL])
    func aChapterThatFitsSitsInTheMiddleOfItsPage(writingMode: ReaderWritingMode) async throws {
        let plain = try await Self.pages(Self.titlePage, centred: false, writingMode: writingMode)
        let centred = try await Self.pages(Self.titlePage, centred: true, writingMode: writingMode)
        try #require(plain.count == 1 && centred.count == 1)
        let before = Self.gaps(plain[0], writingMode: writingMode)
        let after = Self.gaps(centred[0], writingMode: writingMode)
        #expect(abs(before.start) < 0.5, "\(writingMode): the plain page starts at its content edge")
        #expect(abs(after.start - after.end) < 0.5, "\(writingMode): gaps \(after.start) and \(after.end)")
        #expect(abs(after.start - (before.start + before.end) / 2) < 0.5)

        // Every fragment moves by the same amount, along the block axis only.
        let moved = zip(Self.texts(plain[0]), Self.texts(centred[0])).map { plain, centred in
            (dx: centred.rect.rawValue.minX - plain.rect.rawValue.minX, dy: centred.rect.rawValue.minY - plain.rect.rawValue.minY)
        }
        try #require(!moved.isEmpty)
        let shift = after.start - before.start
        for step in moved {
            switch writingMode {
            case .horizontal: #expect(abs(step.dx) < 0.01 && abs(step.dy - shift) < 0.01, "\(step)")
            case .verticalRTL: #expect(abs(step.dy) < 0.01 && abs(step.dx + shift) < 0.01, "\(step)")
            }
        }
        #expect(Self.texts(centred[0]).map(\.sourceRange) == Self.texts(plain[0]).map(\.sourceRange))
    }

    /// The reader's spacing after each paragraph, and a block's own margins, paint
    /// nothing: the lines sit in the middle, not the boxes around them.
    @Test(arguments: [ReaderWritingMode.horizontal, .verticalRTL])
    func theLinesSitInTheMiddleNotTheirBoxes(writingMode: ReaderWritingMode) async throws {
        // The third is a chapter as the app's Aozora converter writes one: white space
        // around the body, and each block ended by a `br` that is a block.
        let aozora = """
            <?xml version="1.0" encoding="UTF-8"?>
            <html xmlns="http://www.w3.org/1999/xhtml">
            <head>
            <title>献辞</title>
            </head>
            <body style="zy-page-align: center"><p>　　　　献辞<br class="eol"/></p><p>　　　　　　友に<br class="eol"/></p></body>
            </html>

            """
        let cases: [(css: String, paragraphSpacing: CGFloat, html: String?)] = [
            (Self.css, 8, nil),
            ("body { margin: 0; padding: 0 } p { margin: 1em 0 }", 0, nil),
            (Self.css + " br.eol { display: block }", 8, aozora),
        ]
        for (css, spacing, html) in cases {
            let centred = try await Self.pages(Self.titlePage, centred: true, writingMode: writingMode,
                                               css: css, paragraphSpacing: spacing, html: html)
            try #require(centred.count == 1)
            let gaps = Self.gaps(centred[0], writingMode: writingMode)
            #expect(abs(gaps.start - gaps.end) < 0.5, "\(writingMode) \(css) spacing \(spacing): gaps \(gaps)")
        }
    }

    @Test(arguments: [ReaderWritingMode.horizontal, .verticalRTL])
    func aChapterLongerThanAPageIsUnchanged(writingMode: ReaderWritingMode) async throws {
        let plain = try await Self.pages(Self.longChapter, centred: false, writingMode: writingMode)
        let centred = try await Self.pages(Self.longChapter, centred: true, writingMode: writingMode)
        try #require(plain.count >= 2)
        #expect(centred.count == plain.count)
        for (a, b) in zip(centred, plain) {
            #expect(Self.texts(a).map(\.rect) == Self.texts(b).map(\.rect))
        }
    }

    @Test(arguments: [ReaderWritingMode.horizontal, .verticalRTL])
    func sessionAndBatchCentreTheSamePage(writingMode: ReaderWritingMode) async throws {
        let batch = try await Self.pages(Self.titlePage, centred: true, writingMode: writingMode)
        let session = BrowserLayoutSession(
            html: "<html><body>\(Self.titlePage)</body></html>", cssTexts: [Self.css],
            config: Self.config(centred: true, writingMode: writingMode), imageLoader: { _ in nil }, generation: 0)
        var incremental: [PageFragments] = []
        while let page = try await session.layoutNextPage() { incremental.append(page) }
        #expect(incremental.count == batch.count)
        for (a, b) in zip(incremental, batch) {
            #expect(Self.texts(a).map(\.rect) == Self.texts(b).map(\.rect))
        }
    }

    /// A host turns it on for a chapter it has already evaluated (`BrowserChapterEvaluation.accepts`).
    @Test func theFlagIsNotACascadeInput() {
        #expect(Self.config(centred: true, writingMode: .horizontal).cascadeInputs
                == Self.config(centred: false, writingMode: .horizontal).cascadeInputs)
    }
}
