import Testing
import UIKit
@testable import YueduCoreText

/// Border sides that are not one uniform frame meet as WebKit's
/// `BorderPainter` joins them: cut on the line from the outer corner to the
/// inner one, antialiased between two colours, painted top, bottom, left,
/// right; a rounded box keeps its curve whatever its sides' colours (list-
/// marker design step 8f). Expected pixels are a WKWebView's at device pixel
/// ratio 3 (S001 ua-all, crop m119), on boxes set on whole device pixels as
/// WebKit snaps them.
@Suite @MainActor
struct BorderCornerTests {

    /// A display list drawn at 3× on white, read back as RGB.
    private struct Canvas {
        static let scale: CGFloat = 3
        private let pixels: [UInt8]
        private let width: Int

        init(_ items: [DisplayItem], size: CGSize) {
            let format = UIGraphicsImageRendererFormat()
            format.scale = Self.scale
            format.opaque = true
            let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
                UIColor.white.setFill()
                context.fill(CGRect(origin: .zero, size: size))
                DisplayListDrawer.draw(DisplayList(items: items), in: context.cgContext)
            }
            let cgImage = image.cgImage!
            width = cgImage.width
            var data = [UInt8](repeating: 0, count: cgImage.width * cgImage.height * 4)
            data.withUnsafeMutableBytes { buffer in
                let context = CGContext(data: buffer.baseAddress, width: cgImage.width, height: cgImage.height,
                                        bitsPerComponent: 8, bytesPerRow: cgImage.width * 4,
                                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
            }
            pixels = data
        }

        /// The device pixel at column `x`, row `y`.
        func rgb(_ x: Int, _ y: Int) -> [Int] {
            let i = (y * width + x) * 4
            return [Int(pixels[i]), Int(pixels[i + 1]), Int(pixels[i + 2])]
        }
    }

    private static func box(_ rect: CGRect, radius: CGFloat = 0, edges: [BorderEdge],
                            writingMode: ReaderWritingMode = .horizontal) -> DisplayItem {
        .fill(DisplayFillItem(rect: PageLocalRect(rawValue: rect), color: .clear, cornerRadius: radius,
                              borderTop: edges[0], borderBottom: edges[1], borderLeft: edges[2], borderRight: edges[3],
                              nodeID: 0, writingMode: writingMode))
    }

    private static func near(_ got: [Int], _ expected: [Int], _ tolerance: Int) -> Bool {
        zip(got, expected).allSatisfy { abs($0 - $1) <= tolerance }
    }

    /// `cc2`: `border: 2px solid; border-left-color: red` on black text.
    @Test func twoColoursMeetOnTheDiagonal() {
        let black = BorderEdge(width: 2, color: .black, style: .solid)
        let red = BorderEdge(width: 2, color: UIColor(red: 1, green: 0, blue: 0, alpha: 1), style: .solid)
        // The bottom on device row 120, as in the probe.
        let canvas = Canvas([Self.box(CGRect(x: 8, y: 10.5, width: 350, height: 29.5),
                                      edges: [black, black, red, black])],
                            size: CGSize(width: 366, height: 50))
        // The bottom-left corner: half of each pixel on the diagonal, the
        // bottom painted first and the left over it.
        for (x, y) in [(24, 119), (25, 118), (29, 114)] {
            #expect(Self.near(Array(canvas.rgb(x, y).prefix(2)), [191, 64], 3), "\(x),\(y) \(canvas.rgb(x, y))")
        }
        #expect(canvas.rgb(25, 119) == [0, 0, 0])
        #expect(canvas.rgb(30, 114) == [0, 0, 0])
        #expect(canvas.rgb(24, 114) == [255, 0, 0])
        #expect(canvas.rgb(24, 118) == [255, 0, 0])
        #expect(canvas.rgb(28, 114) == [255, 0, 0])
    }

    /// `ri`: `border: 4px inset rgb(128,128,128); border-radius: 10px`, its
    /// top on device row 30 and 101 device pixels tall.
    @Test func roundedInsetBorderKeepsItsCurve() {
        for mode in [ReaderWritingMode.horizontal, .verticalRTL] {
            let gray = BorderEdge(width: 4, color: UIColor(red: 128 / 255, green: 128 / 255, blue: 128 / 255, alpha: 1),
                                  style: .inset)
            let canvas = Canvas([Self.box(CGRect(x: 8, y: 10, width: 350, height: 101.0 / 3), radius: 10,
                                          edges: [gray, gray, gray, gray], writingMode: mode)],
                                size: CGSize(width: 366, height: 50))
            // Probe pixel (x, row − 6) → value, tolerance.
            let expected: [(Int, Int, Int, Int)] = [
                (1073, 30, 255, 0),                                   // outside the top-right curve
                (1046, 30, 74, 20), (1048, 30, 121, 20),              // the curve's antialiased edge
                (1050, 33, 44, 0), (500, 32, 44, 0), (26, 66, 44, 0), // dark top and left
                (40, 46, 44, 0), (39, 46, 44, 0),                     // the top-left join: one colour, no seam
                (1065, 44, 212, 0), (1072, 66, 212, 0), (500, 128, 212, 0), (500, 130, 212, 0),
                (1064, 39, 180, 8), (1061, 42, 180, 8), (1058, 45, 180, 8), // top, then right over it
                (34, 120, 139, 8), (35, 119, 139, 8), (36, 118, 138, 8),     // bottom, then left over it
                (48, 130, 234, 20), (52, 130, 214, 20),                       // the bottom-left curve
            ]
            for (x, y, value, tolerance) in expected {
                let got = canvas.rgb(x, y)[0]
                #expect(abs(got - value) <= tolerance, "\(mode) \(x),\(y) got \(got) expected \(value)")
            }
        }
    }

    /// Unequal widths of one colour: each side reaches the outer corner and
    /// no further.
    @Test func unequalWidthsStayInsideTheBox() {
        let thin = BorderEdge(width: 1, color: .black, style: .solid)
        let thick = BorderEdge(width: 3, color: .black, style: .solid)
        let canvas = Canvas([Self.box(CGRect(x: 10, y: 10, width: 40, height: 20), edges: [thin, thin, thick, thin])],
                            size: CGSize(width: 60, height: 40))
        #expect(canvas.rgb(32, 29) == [255, 255, 255])  // above the box, over the left side
        #expect(canvas.rgb(29, 30) == [255, 255, 255])  // left of it
        #expect(canvas.rgb(60, 30) == [0, 0, 0])        // the top
        #expect(canvas.rgb(60, 32) == [0, 0, 0])
        #expect(canvas.rgb(60, 33) == [255, 255, 255])  // inside
        #expect(canvas.rgb(30, 30) == [0, 0, 0])        // the corner
        #expect(canvas.rgb(38, 45) == [0, 0, 0])        // the 3px left
        #expect(canvas.rgb(39, 45) == [255, 255, 255])
    }
}
