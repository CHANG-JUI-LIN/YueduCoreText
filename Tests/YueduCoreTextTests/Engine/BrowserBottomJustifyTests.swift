import CoreText
import Testing
import UIKit
@testable import YueduCoreText

/// 底部對齊 (`BrowserLayoutConfig.bottomJustify`): a page that ends because its
/// next text line no longer fits spreads the space left below its last line
/// evenly over its line gaps. Everything a page paints and hit-tests is derived
/// from its fragments, so the fragments themselves carry the moved geometry.
@MainActor
struct BrowserBottomJustifyTests {
    private static let size = CGSize(width: 300, height: 400)
    private static let insets = UIEdgeInsets(top: 20, left: 16, bottom: 30, right: 16)
    private static var contentBottom: CGFloat { size.height - insets.bottom }

    private static func config(bottomJustify: Bool, writingMode: ReaderWritingMode = .horizontal) -> BrowserLayoutConfig {
        BrowserLayoutConfig(
            renderWidth: size.width - insets.left - insets.right,
            renderHeight: size.height - insets.top - insets.bottom,
            rootFontSize: 17,
            fontFamilies: ["PingFangSC-Regular"],
            textColor: .black,
            backgroundColor: .white,
            contentInsets: insets,
            lineSpacing: 6,
            paragraphSpacing: 8,
            writingMode: writingMode,
            bottomJustify: bottomJustify
        )
    }

    private static let paragraphs = String(
        repeating: "<p>每一頁的最後一行都要貼齊內容區的底邊，中間的行距平均分攤剩下的空間。</p>",
        count: 30
    )

    private static func pages(
        _ body: String = paragraphs,
        bottomJustify: Bool,
        writingMode: ReaderWritingMode = .horizontal
    ) async throws -> [PageFragments] {
        let doc = BrowserLayoutDocument(
            html: "<html><body>\(body)</body></html>",
            cssTexts: [],
            config: config(bottomJustify: bottomJustify, writingMode: writingMode),
            imageLoader: { _ in UIGraphicsImageRenderer(size: CGSize(width: 200, height: 150)).image { _ in } }
        )
        return try await doc.renderPages(containerSize: size)
    }

    private static func texts(_ page: PageFragments) -> [TextFragment] {
        BrowserLayoutTestSupport.allTextFragments([page])
    }

    /// Distinct baselines on the page, top to bottom: one per line.
    private static func baselines(_ page: PageFragments) -> [CGFloat] {
        var result: [CGFloat] = []
        for baseline in texts(page).map(\.baselineY).sorted() where result.last.map({ baseline - $0 > 0.01 }) ?? true {
            result.append(baseline)
        }
        return result
    }

    private static func inkBottom(_ page: PageFragments) -> CGFloat {
        texts(page).map { text in
            var descent: CGFloat = 0
            if let line = text.ctLine { CTLineGetTypographicBounds(line, nil, &descent, nil) }
            return text.baselineY + descent
        }.max() ?? 0
    }

    @Test func fullPagesEndOnTheContentBottomWithEvenGaps() async throws {
        let natural = try await Self.pages(bottomJustify: false)
        let justified = try await Self.pages(bottomJustify: true)
        try #require(natural.count >= 3)
        #expect(justified.count == natural.count)

        for (plain, page) in zip(natural, justified).dropLast() {
            #expect(abs(Self.inkBottom(page) - Self.contentBottom) < 0.5)
            let before = Self.baselines(plain)
            let after = Self.baselines(page)
            try #require(before.count == after.count && before.count > 2)
            #expect(after[0] == before[0])
            let step = after[1] - before[1]
            #expect(step > 0)
            for index in after.indices {
                #expect(abs((after[index] - before[index]) - step * CGFloat(index)) < 0.01)
            }
            // Same text on the same page: justification moves lines, never content.
            #expect(Self.texts(page).map(\.sourceRange) == Self.texts(plain).map(\.sourceRange))
        }
    }

    @Test func theLastPageKeepsItsLines() async throws {
        let natural = try #require(try await Self.pages(bottomJustify: false).last)
        let justified = try #require(try await Self.pages(bottomJustify: true).last)
        #expect(Self.texts(justified).map(\.rect) == Self.texts(natural).map(\.rect))
    }

    @Test func aPageLeftForABlockImageKeepsItsLines() async throws {
        // Text, then an image too tall for what is left: the page ends early.
        let body = String(repeating: "<p>圖片前面的段落。</p>", count: 6)
            + "<img src=\"a.png\" style=\"display:block;width:200px;height:300px\">"
            + Self.paragraphs
        let natural = try await Self.pages(body, bottomJustify: false)
        let justified = try await Self.pages(body, bottomJustify: true)
        let first = try #require(justified.first)
        #expect(Self.texts(first).map(\.rect) == Self.texts(try #require(natural.first)).map(\.rect))
    }

    @Test func aBackgroundBoxStillHoldsItsLines() async throws {
        let body = String(
            repeating: "<p style=\"background-color:#eee\">每一段都有底色，底色要跟著自己的行一起移動。</p>",
            count: 30
        )
        let pages = try await Self.pages(body, bottomJustify: true)
        let page = try #require(pages.first)
        let fills = page.fragments.compactMap { fragment -> FillFragment? in
            if case .fill(let fill) = fragment, fill.decorationID >= 0 { return fill }
            return nil
        }
        try #require(!fills.isEmpty)
        for text in Self.texts(page) {
            let holder = fills.contains { $0.rect.minY <= text.rect.minY + 0.5 && text.baselineY <= $0.rect.maxY + 0.5 }
            #expect(holder, "line at \(text.rect.minY) left its background box")
        }
    }

    @Test func aPageLeftForATallLineKeepsItsLines() async throws {
        // A display-size line that does not fit what is left can leave most of the
        // page empty; spreading that would tear the page apart. How many paragraphs
        // push the heading off its page depends on font metrics, so try a range.
        var checked = 0
        for leading in 4...14 {
            let body = String(repeating: "<p>標題前面的段落，長度剛好讓標題落在頁中間。</p>", count: leading)
                + "<p style=\"font-size:90px;line-height:1.2;margin:0\">大</p>"
                + Self.paragraphs
            let natural = try await Self.pages(body, bottomJustify: false)
            guard let headingPage = natural.firstIndex(where: { page in
                Self.texts(page).contains { $0.font.pointSize >= 89 }
            }), headingPage > 0,
                  (Self.texts(natural[headingPage]).first?.font.pointSize ?? 0) >= 89 else { continue }
            let justified = try await Self.pages(body, bottomJustify: true)
            try #require(justified.count == natural.count)
            #expect(
                Self.texts(justified[headingPage - 1]).map(\.rect) == Self.texts(natural[headingPage - 1]).map(\.rect),
                "\(leading) paragraphs: the page before the heading was stretched"
            )
            checked += 1
        }
        try #require(checked > 0, "the heading never moved to a new page")
    }

    @Test func linesNeverMoveIntoABoxOpeningBelowThem() async throws {
        // Plain paragraphs alternate with padded boxes. When a box's top fits a
        // page but its first line does not, the box already owns the space below
        // the last line, and justified lines may not slide into it.
        var body = ""
        for index in 0..<24 {
            body += "<p>" + String(repeating: "框外的段落。", count: 3 + index % 5) + "</p>"
            body += "<div style=\"background-color:#eee;padding-top:40px;color:#00f\"><p>框內的段落。</p></div>"
        }
        let natural = try await Self.pages(body, bottomJustify: false)
        let justified = try await Self.pages(body, bottomJustify: true)
        try #require(justified.count == natural.count)

        func fills(_ page: PageFragments) -> [CGRect] {
            page.fragments.compactMap { fragment in
                if case .fill(let fill) = fragment, fill.decorationID >= 0 { return fill.rect.rawValue }
                return nil
            }
        }
        func plainLines(_ page: PageFragments) -> [CGRect] {
            Self.texts(page).filter { text in
                var red: CGFloat = 0, blue: CGFloat = 0
                text.color.getRed(&red, green: nil, blue: &blue, alpha: nil)
                return !(blue > 0.5 && red < 0.5)
            }.map(\.rect.rawValue)
        }
        // The layout really contains the case under test.
        let opensBelow = natural.dropLast().contains { page in
            guard let lastLine = Self.texts(page).map(\.rect.maxY).max() else { return false }
            return fills(page).contains { $0.minY >= lastLine - 0.5 }
        }
        try #require(opensBelow, "no box opened below a page's last line")
        for page in justified {
            for line in plainLines(page) {
                #expect(!fills(page).contains { $0.insetBy(dx: 0, dy: 0.5).intersects(line) },
                        "plain line at \(line.minY) slid into a box")
            }
        }
    }

    @Test func sessionAndBatchJustifyTheSamePages() async throws {
        let html = "<html><body>\(Self.paragraphs)</body></html>"
        let batch = try await Self.pages(bottomJustify: true)
        let session = BrowserLayoutSession(
            html: html, cssTexts: [], config: Self.config(bottomJustify: true),
            imageLoader: { _ in nil }, generation: 0
        )
        var incremental: [PageFragments] = []
        while let page = try await session.layoutNextPage() { incremental.append(page) }
        #expect(incremental.count == batch.count)
        for (a, b) in zip(incremental, batch) {
            #expect(Self.texts(a).map(\.rect) == Self.texts(b).map(\.rect))
            #expect(Self.texts(a).map(\.baselineY) == Self.texts(b).map(\.baselineY))
        }
    }

    @Test func verticalWritingIsNotJustified() async throws {
        let natural = try await Self.pages(bottomJustify: false, writingMode: .verticalRTL)
        let justified = try await Self.pages(bottomJustify: true, writingMode: .verticalRTL)
        #expect(justified.count == natural.count)
        for (a, b) in zip(justified, natural) {
            #expect(Self.texts(a).map(\.rect) == Self.texts(b).map(\.rect))
        }
    }
}
