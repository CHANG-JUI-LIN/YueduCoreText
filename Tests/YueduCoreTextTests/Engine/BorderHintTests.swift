import Testing
import UIKit
@testable import YueduCoreText

/// `hr`'s presentational attributes, a border's `currentColor`, and the
/// logical border properties, against a WKWebView (iOS 27.2, S001 ua-all;
/// list-marker design step 8f). Every expected box is the web view's border
/// box.
@Suite @MainActor
struct BorderHintTests {

    private static func fills(_ body: String, css: String = "", vertical: Bool = false) async throws -> [DisplayFillItem] {
        let layout = try await BrowserLayoutTestSupport.webKitReference(body, css: css, vertical: vertical)
        return layout.pages.flatMap { page in
            DisplayListBuilder.build(for: page).items.compactMap {
                if case .fill(let fill) = $0, fill.hasVisibleBorder { return fill } else { return nil }
            }
        }
    }

    private static func rgb(_ color: UIColor) -> [Int] {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return [r, g, b].map { Int(($0 * 255).rounded()) }
    }

    private static let gray = [128, 128, 128]

    /// The rule's border box and its edges, top, bottom, left, right.
    @Test func horizontalRuleAttributes() async throws {
        let cases: [(String, CGRect, [BorderStyle], [[Int]])] = [
            ("<hr/>", CGRect(x: 8, y: 0, width: 350, height: 2), [.inset], [Self.gray]),
            ("<hr noshade=\"noshade\"/>", CGRect(x: 8, y: 0, width: 350, height: 2), [.solid], [Self.gray]),
            ("<hr size=\"5\"/>", CGRect(x: 8, y: 0, width: 350, height: 5), [.inset], [Self.gray]),
            ("<hr color=\"red\"/>", CGRect(x: 8, y: 0, width: 350, height: 2), [.solid], [[255, 0, 0]]),
            ("<hr width=\"50%\"/>", CGRect(x: 94.5, y: 0, width: 177, height: 2), [.inset], [Self.gray]),
            ("<hr width=\"100\" align=\"left\"/>", CGRect(x: 8, y: 0, width: 102, height: 2), [.inset], [Self.gray]),
            ("<hr width=\"100\" align=\"right\"/>", CGRect(x: 256, y: 0, width: 102, height: 2), [.inset], [Self.gray]),
            // A single side's colour and style leave the other three alone.
            ("<hr class=\"dot\"/>", CGRect(x: 8, y: 0, width: 350, height: 2),
             [.dotted, .inset, .inset, .inset], [[153, 153, 153], Self.gray, Self.gray, Self.gray]),
        ]
        for (hr, box, styles, colors) in cases {
            let fill = try #require(try await Self.fills("<p>前</p>" + hr, css: "hr.dot { border-top: 1px dotted #999 }").first,
                                    "\(hr) drew no border")
            let rect = fill.rect.rawValue
            #expect(abs(rect.minX - box.minX) < 0.01 && abs(rect.width - box.width) < 0.01
                    && abs(rect.height - box.height) < 0.01, "\(hr) \(rect)")
            let edges = [fill.borderTop, fill.borderBottom, fill.borderLeft, fill.borderRight]
            #expect(edges.allSatisfy { $0.width == 1 }, "\(hr)")
            #expect(edges.map(\.style) == (styles.count == 1 ? Array(repeating: styles[0], count: 4) : styles), "\(hr)")
            #expect(edges.map { Self.rgb($0.color) } == (colors.count == 1 ? Array(repeating: colors[0], count: 4) : colors),
                    "\(hr)")
        }
    }

    /// A border with no colour is the box's `color`, set on it or inherited.
    @Test(arguments: [false, true])
    func borderColorIsCurrentColor(vertical: Bool) async throws {
        let blue = try #require(try await Self.fills("<div style=\"border: 2px solid; color: blue\">辛二邊框</div>",
                                                     vertical: vertical).first)
        #expect([blue.borderTop, blue.borderBottom, blue.borderLeft, blue.borderRight].allSatisfy {
            Self.rgb($0.color) == [0, 0, 255] && $0.width == 2
        })
        let mixed = try #require(try await Self.fills(
            "<div style=\"color: green\"><div style=\"border: 2px solid; border-left-color: red\">辛三邊框</div></div>",
            vertical: vertical).first)
        #expect(Self.rgb(mixed.borderLeft.color) == [255, 0, 0])
        #expect([mixed.borderTop, mixed.borderBottom, mixed.borderRight].allSatisfy { Self.rgb($0.color) == [0, 128, 0] })
    }

    /// `border-block-end` is the bottom horizontally and the left in
    /// vertical-rl.
    @Test(arguments: [false, true])
    func logicalBorderSides(vertical: Bool) async throws {
        let fill = try #require(try await Self.fills("<div style=\"border-block-end: 1px solid black\"><p>甲四段落。</p></div>",
                                                     vertical: vertical).first)
        let physical = [fill.borderTop.width, fill.borderBottom.width, fill.borderLeft.width, fill.borderRight.width]
        #expect(physical == (vertical ? [0, 0, 1, 0] : [0, 1, 0, 0]), "\(physical)")
    }
}
