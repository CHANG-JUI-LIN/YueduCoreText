import CoreText
import Foundation

/// A conservative envelope for culling/allocating paint surfaces, not layout.
/// Image bounds ask CoreText for every glyph's outline (including variable-font
/// paths). Scroll callbacks only need to know which surfaces MAY contain ink.
/// Use the font's design box at the already-shaped glyph positions instead.
public enum TextLinePaintBounds {
    public static func conservativeBounds(for line: CTLine) -> CGRect {
        var ascent: CGFloat = 0, descent: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, nil))
        var result = CGRect(x: 0, y: -descent, width: max(1, width),
                            height: max(1, ascent + descent))
        for run in CTLineGetGlyphRuns(line) as! [CTRun] {
            let count = CTRunGetGlyphCount(run)
            guard count > 0 else { continue }
            let attributes = CTRunGetAttributes(run) as NSDictionary
            guard let value = attributes[kCTFontAttributeName],
                  CFGetTypeID(value as CFTypeRef) == CTFontGetTypeID() else { continue }
            let font = value as! CTFont
            let box = CTFontGetBoundingBox(font)
            guard !box.isNull, !box.isInfinite else { continue }
            var matrix = CTRunGetTextMatrix(run)
            // CoreText's run text position is supplied by the caller. The glyph
            // positions include shaping/mark offsets and must not be replaced
            // by an advance sum (RTL, combining marks and baseline shifts).
            matrix.tx = 0
            matrix.ty = 0
            func include(_ positions: UnsafeBufferPointer<CGPoint>) {
                var minX = CGFloat.infinity, minY = CGFloat.infinity
                var maxX = -CGFloat.infinity, maxY = -CGFloat.infinity
                for position in positions {
                    minX = min(minX, position.x)
                    minY = min(minY, position.y)
                    maxX = max(maxX, position.x)
                    maxY = max(maxY, position.y)
                }
                let envelope = CGRect(x: minX + box.minX, y: minY + box.minY,
                    width: maxX - minX + box.width, height: maxY - minY + box.height)
                result = result.union(envelope.applying(matrix))
            }
            if let positions = CTRunGetPositionsPtr(run) {
                include(UnsafeBufferPointer(start: positions, count: count))
            } else {
                var positions = [CGPoint](repeating: .zero, count: count)
                CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
                positions.withUnsafeBufferPointer(include)
            }
        }
        return result
    }
}
