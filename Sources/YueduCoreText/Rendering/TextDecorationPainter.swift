import CoreText
import UIKit

/// Draws a text item's CSS decorations as WebKit does (`TextDecorationPainter`,
/// `GraphicsContext::drawLinesForText`, `FontCascade`). Everything happens in
/// the item's own frame: x along the line from its inline start, y from its
/// baseline toward the under side (down; left in vertical-rl).
///
/// Device pixels decide the geometry, as in WebKit: a thickness is rounded up
/// to whole pixels; an underline or overline starts at the nearest pixel, a
/// line-through at the next one away from the text.
enum TextDecorationPainter {

    /// Underlines and overlines, which go under the glyphs (`include`), or
    /// line-throughs, which go over them.
    static func draw(
        _ paints: [TextDecorationPaint], where include: (TextDecorationPaint.Line) -> Bool,
        length: CGFloat, line: CTLine?, string: NSAttributedString, in context: CGContext
    ) {
        let toDevice = context.userSpaceToDeviceSpaceTransform
        for paint in paints where include(paint.line) {
            let rect = rect(for: paint, length: length, toDevice: toDevice)
            guard rect.width > 0, rect.height > 0 else { continue }
            context.saveGState()
            if paint.style == .wavy {
                strokeWave(rect, paint: paint, in: context)
            } else {
                var segments = [Segment(begin: 0, end: rect.width)]
                if paint.skipsInk, let line {
                    let crossings = glyphCrossings(line: line, string: string, band: rect.minY...rect.maxY)
                        .map { Segment(begin: $0.begin - rect.minX, end: $0.end - rect.minX) }
                    if !crossings.isEmpty {
                        segments = difference(Segment(begin: 0, end: rect.width), crossings,
                                              dilation: min(rect.height, paint.inkDilationLimit))
                    }
                }
                context.setFillColor(paint.color.cgColor)
                for piece in rects(origin: rect.origin, thickness: rect.height, segments: segments, style: paint.style) {
                    context.fill(piece)
                }
            }
            context.restoreGState()
        }
    }

    /// The line's rect in the item frame whose device transform is
    /// `toDevice`: its thicknesses rounded up to device pixels, its origin
    /// snapped (`computeLineBoundsAndAntialiasingModeForText`).
    static func rect(for paint: TextDecorationPaint, length: CGFloat, toDevice: CGAffineTransform) -> CGRect {
        let scale = max(1e-6, hypot(toDevice.a, toDevice.b))
        func ceilToPixel(_ value: CGFloat) -> CGFloat { ceil(value * scale - 1e-6) / scale }
        let thickness = max(ceilToPixel(paint.thickness), 0.5)
        let auto = ceilToPixel(paint.autoThickness)
        let y: CGFloat
        switch paint.line {
        case .underline: y = paint.position
        case .overline: y = paint.position + auto - thickness
        case .lineThrough: y = paint.position + auto / 2 - thickness / 2
        }
        let device = CGPoint(x: 0, y: y).applying(toDevice)
        let snappedY: CGFloat
        if paint.line == .lineThrough {
            // Straight to `drawLineForText`: away from the decorated text.
            snappedY = toDevice.d < 0 ? floor(device.y) : ceil(device.y)
        } else {
            // `roundPointToDevicePixels` first; the line snapping is then a no-op.
            snappedY = device.y.rounded()
        }
        let origin = CGPoint(x: device.x.rounded(), y: snappedY).applying(toDevice.inverted())
        return CGRect(x: origin.x, y: origin.y, width: length, height: thickness)
    }

    /// How far the item's decorations may reach, in its page coordinates,
    /// for culling: before snapping, and generous by a point.
    static func extent(of item: DisplayTextItem) -> CGRect {
        var result = CGRect.null
        for paint in item.textDecorations {
            let shift = abs(paint.autoThickness - paint.thickness) + 1
            let wave = paint.style == .wavy ? paint.waveAmplitude + paint.thickness : 0
            let lower = paint.position - shift - wave
            let upper = paint.position + paint.thickness * (paint.style == .double ? 3 : 1) + shift + wave
            let rect = item.writingMode == .horizontal
                ? CGRect(x: item.rect.minX, y: item.baselineY + lower, width: item.rect.width, height: upper - lower)
                : CGRect(x: item.baselineY - upper, y: item.rect.minY, width: upper - lower, height: item.rect.height)
            result = result.union(rect)
        }
        return result
    }

    struct Segment: Equatable {
        var begin: CGFloat
        var end: CGFloat
        var length: CGFloat { end - begin }
    }

    /// `differenceWithDilation`: what is left of `whole` once every crossing,
    /// widened by `dilation` either side, is taken out; pieces no longer than
    /// the dilation go too.
    static func difference(_ whole: Segment, _ crossings: [Segment], dilation: CGFloat) -> [Segment] {
        var remaining = whole
        var result: [Segment] = []
        for crossing in crossings.sorted(by: { $0.begin < $1.begin }) {
            guard remaining.begin < remaining.end else { break }
            let widened = Segment(begin: crossing.begin - dilation, end: crossing.end + dilation)
            guard widened.begin < remaining.end else { break }
            let candidate = Segment(begin: remaining.begin, end: widened.begin)
            if candidate.length > dilation { result.append(candidate) }
            remaining.begin = max(remaining.begin, widened.end)
        }
        if remaining.length > dilation { result.append(remaining) }
        return result
    }

    /// The x extents, in the item frame, where glyphs cross the band between
    /// `band`'s two edges (`FontCascade::lineSegmentsForIntersectionsWithRect`).
    /// Each contour is taken as the straight lines between its points.
    /// Ideographs, kana, hangul and Arabic are drawn through
    /// (`computeUnderlineType`).
    static func glyphCrossings(line: CTLine, string: NSAttributedString, band: ClosedRange<CGFloat>) -> [Segment] {
        // Glyph space runs y up from the baseline.
        let y1 = -band.upperBound, y2 = -band.lowerBound
        let text = string.string as NSString
        var result: [Segment] = []
        for run in CTLineGetGlyphRuns(line) as! [CTRun] {
            let count = CTRunGetGlyphCount(run)
            guard count > 0,
                  let value = (CTRunGetAttributes(run) as NSDictionary)[kCTFontAttributeName],
                  CFGetTypeID(value as CFTypeRef) == CTFontGetTypeID() else { continue }
            let font = value as! CTFont
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            var indices = [CFIndex](repeating: 0, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
            CTRunGetStringIndices(run, CFRange(location: 0, length: count), &indices)
            var matrix = CTRunGetTextMatrix(run)
            matrix.tx = 0
            matrix.ty = 0
            for index in 0..<count {
                guard indices[index] < text.length,
                      !drawsThrough(character(in: text, at: indices[index])) else { continue }
                var transform = matrix.concatenating(CGAffineTransform(translationX: positions[index].x,
                                                                       y: positions[index].y))
                guard let path = CTFontCreatePathForGlyph(font, glyphs[index], &transform) else { continue }
                var minX = CGFloat.infinity, maxX = -CGFloat.infinity
                var start = CGPoint.zero, current = CGPoint.zero
                func crossing(_ y: CGFloat, _ p1: CGPoint, _ p2: CGPoint) -> CGFloat? {
                    guard (p1.y < y && p2.y > y) || (p1.y > y && p2.y < y) else { return nil }
                    return p1.x + (y - p1.y) * (p2.x - p1.x) / (p2.y - p1.y)
                }
                func reach(_ x: CGFloat) { minX = min(minX, x); maxX = max(maxX, x) }
                path.applyWithBlock { pointer in
                    let element = pointer.pointee
                    let next: CGPoint
                    switch element.type {
                    case .moveToPoint:
                        start = element.points[0]; current = start
                        return
                    case .addLineToPoint: next = element.points[0]
                    case .addQuadCurveToPoint: next = element.points[1]
                    case .addCurveToPoint: next = element.points[2]
                    case .closeSubpath: next = start
                    @unknown default: return
                    }
                    if let x = crossing(y1, current, next) { reach(x) }
                    if let x = crossing(y2, current, next) { reach(x) }
                    if (current.y >= y1 && current.y <= y2) || (current.y <= y1 && current.y >= y2) { reach(current.x) }
                    current = next
                }
                if minX < maxX { result.append(Segment(begin: minX, end: maxX)) }
            }
        }
        return result
    }

    private static func character(in text: NSString, at index: Int) -> UInt32 {
        let unit = text.character(at: index)
        if UTF16.isLeadSurrogate(unit), index + 1 < text.length {
            let trail = text.character(at: index + 1)
            if UTF16.isTrailSurrogate(trail) {
                return 0x10000 + ((UInt32(unit) - 0xD800) << 10) + (UInt32(trail) - 0xDC00)
            }
        }
        return UInt32(unit)
    }

    /// WebKit's Unicode blocks whose glyphs an underline crosses.
    private static let drawnThroughBlocks: [ClosedRange<UInt32>] = [
        0x0600...0x06FF, 0x0750...0x077F, 0x0870...0x089F, 0x08A0...0x08FF,    // Arabic
        0x1100...0x11FF,                                                        // Hangul Jamo
        0x2E80...0x2EFF, 0x2FF0...0x2FFF,                                       // radicals, description
        0x3000...0x303F, 0x3040...0x309F, 0x30A0...0x30FF, 0x3100...0x312F,    // symbols, kana, bopomofo
        0x3130...0x318F, 0x31A0...0x31BF, 0x31C0...0x31EF,                      // jamo, bopomofo, strokes
        0x3200...0x32FF, 0x3300...0x33FF, 0x3400...0x4DBF, 0x4E00...0x9FFF,    // enclosed, ideographs
        0xA960...0xA97F, 0xAC00...0xD7AF, 0xD7B0...0xD7FF,                      // hangul
        0xF900...0xFAFF, 0xFB50...0xFDFF, 0xFE30...0xFE4F, 0xFE70...0xFEFF,    // compatibility, Arabic forms
        0x10080...0x100FF, 0x10EC0...0x10EFF, 0x1F200...0x1F2FF,
        0x20000...0x2A6DF, 0x2A700...0x2B73F, 0x2B740...0x2B81F, 0x2F800...0x2FA1F,
    ]

    private static func drawsThrough(_ scalar: UInt32) -> Bool {
        drawnThroughBlocks.contains { $0.contains(scalar) }
    }

    /// The rects a solid, double, dotted or dashed line fills along
    /// `segments` (`computeRectsAndStrokeColorForLinesForText`): a dot is as
    /// long as the line is thick, a dash twice that, with gaps as long; a
    /// double line repeats one thickness below the first.
    static func rects(origin: CGPoint, thickness: CGFloat, segments: [Segment], style: TextDecorationStyle) -> [CGRect] {
        guard !segments.isEmpty else { return [] }
        var result: [CGRect] = []
        let dash: CGFloat = style == .dotted ? thickness : style == .dashed ? 2 * thickness : 0
        if dash > 0 {
            for segment in segments {
                let left = segment.begin, width = segment.length
                let period = 2 * dash
                let startOffset = left - CGFloat(Int(left / period)) * period
                let startParticle = Int(floor((left + startOffset) / period))
                let endParticle = Int(ceil((left + width) / period))
                guard startParticle < endParticle else { continue }
                for particle in startParticle..<endParticle {
                    var dashWidth = dash
                    var dashStart = origin.x + CGFloat(particle) * period
                    if particle == startParticle, startOffset > 0, startOffset < dash {
                        dashWidth -= startOffset
                        dashStart += startOffset
                    }
                    if particle == endParticle - 1 {
                        let remaining = left + width - CGFloat(particle) * period
                        if remaining < dash { dashWidth = remaining }
                    }
                    result.append(CGRect(x: dashStart, y: origin.y, width: dashWidth, height: thickness))
                }
            }
        } else {
            for segment in segments {
                result.append(CGRect(x: origin.x + segment.begin, y: origin.y, width: segment.length, height: thickness))
            }
        }
        if style == .double {
            for segment in segments {
                result.append(CGRect(x: origin.x + segment.begin, y: origin.y + 2 * thickness,
                                     width: segment.length, height: thickness))
            }
        }
        return result
    }

    /// `strokeWavyTextDecoration`: cubic waves along the rect's top edge,
    /// started two steps early and clipped to the rect's length.
    private static func strokeWave(_ rect: CGRect, paint: TextDecorationPaint, in context: CGContext) {
        let step = paint.waveStep
        let amplitude = paint.waveAmplitude
        var y = rect.minY
        // `adjustLineToPixelBoundaries`: an odd whole thickness sits half a
        // point lower.
        if Int(rect.height) % 2 == 1 { y += 0.5 }
        let x1 = rect.minX - 2 * step, x2 = rect.maxX + 2 * step
        guard step >= 1, (x2 - x1) / (2 * step) <= 1024 else {
            context.setFillColor(paint.color.cgColor)
            context.fill(rect)
            return
        }
        let path = CGMutablePath()
        path.move(to: CGPoint(x: x1, y: y))
        var x = x1
        while x + 2 * step <= x2 {
            let control = x + step
            x += 2 * step
            path.addCurve(to: CGPoint(x: x, y: y), control1: CGPoint(x: control, y: y + amplitude),
                          control2: CGPoint(x: control, y: y - amplitude))
        }
        context.clip(to: rect.insetBy(dx: 0, dy: -amplitude))
        context.setShouldAntialias(true)
        context.setStrokeColor(paint.color.cgColor)
        context.setLineWidth(rect.height)
        context.addPath(path)
        context.strokePath()
    }
}
