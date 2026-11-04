import UIKit
import CoreText

public enum TextPaintPhase: Sendable, Equatable { case all, decorations, glyphs }

public enum DisplayListDrawer {
    /// Draws the list into the CURRENT context. The caller owns the background.
    ///
    /// - Parameter skipAuthoredBackgroundPaint: drops the injected page-canvas
    ///   fill and image — the document's own `background-color`/`background-image`.
    ///   Pass true when the caller has already painted a reader-chosen background
    ///   image: that preference REPLACES the authored surface rather than sitting
    ///   under it, which is the same precedence `CoreTextPageView` gets from
    ///   `readerBackgroundImage ?? pageBackgroundImage`. Without it the artwork
    ///   was painted and then covered by the book's own wallpaper.
    public static func draw(
        _ list: DisplayList,
        in context: CGContext,
        skipAuthoredBackgroundPaint: Bool = false,
        textPaintPhase: TextPaintPhase = .all,
        textDecoration: ((CTLine, NSAttributedString, CGContext) -> Void)? = nil
    ) {
        var pendingText: [DisplayTextItem] = []
        func flushText() {
            let shaped = pendingText.map { item in
                let resource = item.preparedDrawing ?? TextDrawingResources(item)
                return (item, resource.attributed, resource.line)
            }
            // Decorations may extend past an inline element's own bounds.
            // Paint the complete text group underneath all its glyphs so a
            // later span's padding cannot erase the preceding span's ink.
            for (item, string, line) in shaped where textPaintPhase != .glyphs {
                drawText(item, string: string, line: line, decorationOnly: true, textDecoration: textDecoration, in: context)
            }
            for (item, string, line) in shaped where textPaintPhase != .decorations {
                drawText(item, string: string, line: line, decorationOnly: false, textDecoration: textDecoration, in: context)
            }
            pendingText.removeAll(keepingCapacity: true)
        }
        for item in list.items {
            switch item {
            case .fill(let f):
                flushText()
                if skipAuthoredBackgroundPaint, f.isBackgroundPaint { continue }
                drawFill(f, in: context)
            case .text(let t):
                pendingText.append(t)
            case .image(let i):
                flushText()
                if skipAuthoredBackgroundPaint, i.isBackgroundPaint { continue }
                context.saveGState()
                if let rotation = i.paintTransform { context.concatenate(rotation.matrix) }
                if let image = i.image {
                    image.draw(in: i.rect.rawValue)
                } else {
                    UIColor.lightGray.setFill()
                    context.fill(i.rect.rawValue)
                }
                context.restoreGState()
            }
        }
        flushText()
    }

    /// One bordered box: background (clipped to radius) + four border edges.
    /// `sideOrder` is the canonical sides in the order WebKit paints the
    /// physical top, bottom, left and right.
    private static func drawFill(_ item: DisplayFillItem, sideOrder: [BoxSide] = [.top, .bottom, .left, .right],
                                 in context: CGContext) {
        // Bevelled edges take their colours by physical side, so they resolve
        // before the vertical branch below maps the sides to canonical ones.
        let item = item.resolvingBevelEdges()
        let rect = item.rect.rawValue
        context.saveGState()
        defer { context.restoreGState() }
        if let rotation = item.paintTransform { context.concatenate(rotation.matrix) }
        guard !rect.isEmpty else { return }
        if item.writingMode == .verticalRTL {
            // Fragment-start/end corners and border edges are logical. Reuse
            // the same decoration painter in its canonical axes.
            context.saveGState()
            context.translateBy(x: rect.maxX, y: rect.minY)
            context.rotate(by: .pi / 2)
            drawFill(DisplayFillItem(
                rect: PageLocalRect(rawValue: CGRect(x: 0, y: 0, width: rect.height, height: rect.width)),
                color: item.color, cornerRadius: item.cornerRadius,
                borderTop: item.borderRight, borderBottom: item.borderLeft,
                borderLeft: item.borderTop, borderRight: item.borderBottom,
                nodeID: item.nodeID, writingMode: .horizontal,
                fragmentPosition: item.fragmentPosition, isBackgroundPaint: item.isBackgroundPaint,
                followsTextColor: item.followsTextColor), sideOrder: [.left, .right, .bottom, .top], in: context)
            context.restoreGState()
            return
        }
        let radius = min(item.cornerRadius, rect.width / 2, rect.height / 2)

        let roundedCorners: UIRectCorner
        switch item.fragmentPosition {
        case .single:
            roundedCorners = .allCorners
        case .first:
            roundedCorners = [.topLeft, .topRight]
        case .middle:
            roundedCorners = []
        case .last:
            roundedCorners = [.bottomLeft, .bottomRight]
        }
        let borderPath: UIBezierPath
        if radius > 0, !roundedCorners.isEmpty {
            borderPath = UIBezierPath(
                roundedRect: rect,
                byRoundingCorners: roundedCorners,
                cornerRadii: CGSize(width: radius, height: radius)
            )
        } else {
            borderPath = UIBezierPath(rect: rect)
        }
        // Background fill (respects alpha — rgba(255,255,255,0.7) shows the
        // authored background through).
        if item.color != .clear {
            context.saveGState()
            borderPath.addClip()
            item.color.setFill()
            context.fill(rect)
            context.restoreGState()
        }
        guard item.hasVisibleBorder else { return }

        // Border: stroke the same rounded path at half the max width so the
        // corner join is correct; then re-stroke thinner per-edge segments is
        // overkill — a single stroked rounded path with per-side widths is
        // approximated by stroking the full path at the max width for each
        // visible style band.
        let maxWidth = max(item.borderTop.width, item.borderBottom.width,
                           item.borderLeft.width, item.borderRight.width)
        guard maxWidth > 0 else { return }

        // Draw each visible edge as a separate line so dotted/dashed styles
        // apply per edge. Edges are drawn on the border box boundary.
        context.saveGState()
        context.setLineCap(.square)

        func strokeEdge(from start: CGPoint, to end: CGPoint, width: CGFloat, style: BorderStyle, color: UIColor) {
            guard width > 0, style != .none else { return }
            color.setStroke()
            context.setLineWidth(width)
            // Dotted: round dots. Dashed: short dashes.
            switch style {
            case .solid, .none, .inset, .outset:
                context.setLineDash(phase: 0, lengths: [])
            case .dotted:
                // Visible dots: a 1×-width solid dot with a 2.5× gap. A
                // 0.1pt dash anti-aliased into near-invisible gray on device.
                context.setLineDash(phase: 0, lengths: [width, width * 2.5])
                context.setLineCap(.round)
            case .dashed:
                context.setLineDash(phase: 0, lengths: [width * 3, width * 2])
            }
            context.beginPath()
            context.move(to: start)
            context.addLine(to: end)
            context.strokePath()
            context.setLineDash(phase: 0, lengths: [])
            context.setLineCap(.square)
        }

        /// One `border-radius` corner. Same per-path dash treatment as an edge.
        func strokeArc(
            center: CGPoint, radius: CGFloat, start: CGFloat, end: CGFloat,
            width: CGFloat, style: BorderStyle, color: UIColor
        ) {
            guard width > 0, radius > 0, style != .none else { return }
            color.setStroke()
            context.setLineWidth(width)
            switch style {
            case .solid, .none, .inset, .outset:
                context.setLineDash(phase: 0, lengths: [])
            case .dotted:
                context.setLineDash(phase: 0, lengths: [width, width * 2.5])
                context.setLineCap(.round)
            case .dashed:
                context.setLineDash(phase: 0, lengths: [width * 3, width * 2])
            }
            context.beginPath()
            context.addArc(center: center, radius: radius, startAngle: start, endAngle: end, clockwise: false)
            context.strokePath()
            context.setLineDash(phase: 0, lengths: [])
            context.setLineCap(.square)
        }

        // A UNIFORM border on a rounded box is stroked as ONE rounded path.
        // The per-edge straight lines below cannot bend, so `border-radius: 12px`
        // on a dotted bordered box drew square
        // corners while its own background fill was already clipped round —
        // the fill and the frame disagreed on the same box.
        let visibleEdges = [item.borderTop, item.borderBottom, item.borderLeft, item.borderRight]
            .filter(\.isVisible)
        let uniformVisibleBorder = visibleEdges.first.map { first in
            visibleEdges.dropFirst().allSatisfy {
                $0.width == first.width && $0.style == first.style && $0.color == first.color
            }
        } ?? false
        let hasFragmentPerimeter: Bool
        switch item.fragmentPosition {
        case .single:
            hasFragmentPerimeter = item.borderTop.isVisible && item.borderBottom.isVisible
                && item.borderLeft.isVisible && item.borderRight.isVisible
        case .first:
            hasFragmentPerimeter = item.borderTop.isVisible
                && item.borderLeft.isVisible && item.borderRight.isVisible
        case .middle:
            hasFragmentPerimeter = item.borderLeft.isVisible && item.borderRight.isVisible
        case .last:
            hasFragmentPerimeter = item.borderBottom.isVisible
                && item.borderLeft.isVisible && item.borderRight.isVisible
        }
        if radius > 0, uniformVisibleBorder, hasFragmentPerimeter,
           let commonEdge = visibleEdges.first {
            let width = commonEdge.width
            let inset = width / 2
            let box = rect.insetBy(dx: inset, dy: inset)
            let r = max(0, min(radius - inset, box.width / 2, box.height / 2))
            let style = commonEdge.style
            let color = commonEdge.color

            // The four FLAT segments are stroked one path at a time, exactly as
            // the square-corner code below does — a single closed path would run
            // one continuous dash phase around the whole perimeter, which
            // changes where dots land on every edge after the first. Only the
            // corners are new geometry.
            let roundsTop = item.fragmentPosition == .single || item.fragmentPosition == .first
            let roundsBottom = item.fragmentPosition == .single || item.fragmentPosition == .last
            let topRadius = roundsTop ? r : 0
            let bottomRadius = roundsBottom ? r : 0
            if item.borderTop.isVisible {
                strokeEdge(from: CGPoint(x: box.minX + topRadius, y: box.minY),
                           to: CGPoint(x: box.maxX - topRadius, y: box.minY),
                           width: width, style: style, color: color)
            }
            if item.borderBottom.isVisible {
                strokeEdge(from: CGPoint(x: box.minX + bottomRadius, y: box.maxY),
                           to: CGPoint(x: box.maxX - bottomRadius, y: box.maxY),
                           width: width, style: style, color: color)
            }
            if item.borderLeft.isVisible {
                strokeEdge(from: CGPoint(x: box.minX, y: box.minY + topRadius),
                           to: CGPoint(x: box.minX, y: box.maxY - bottomRadius),
                           width: width, style: style, color: color)
            }
            if item.borderRight.isVisible {
                strokeEdge(from: CGPoint(x: box.maxX, y: box.minY + topRadius),
                           to: CGPoint(x: box.maxX, y: box.maxY - bottomRadius),
                           width: width, style: style, color: color)
            }
            if r > 0 {
                if roundsTop {
                    strokeArc(center: CGPoint(x: box.minX + r, y: box.minY + r), radius: r,
                              start: .pi, end: 1.5 * .pi, width: width, style: style, color: color)
                    strokeArc(center: CGPoint(x: box.maxX - r, y: box.minY + r), radius: r,
                              start: 1.5 * .pi, end: 2 * .pi, width: width, style: style, color: color)
                }
                if roundsBottom {
                    strokeArc(center: CGPoint(x: box.maxX - r, y: box.maxY - r), radius: r,
                              start: 0, end: 0.5 * .pi, width: width, style: style, color: color)
                    strokeArc(center: CGPoint(x: box.minX + r, y: box.maxY - r), radius: r,
                              start: 0.5 * .pi, end: .pi, width: width, style: style, color: color)
                }
            }
            context.restoreGState()
            return
        }

        // Dotted and dashed sides: the top edge spans the full box width;
        // side edges start below the top border width and end above the
        // bottom border width so corners don't double-stroke.
        let topInset = item.borderTop.width / 2
        let bottomInset = item.borderBottom.width / 2
        let leftInset = item.borderLeft.width / 2
        let rightInset = item.borderRight.width / 2
        let edges: [BoxSide: BorderEdge] = [.top: item.borderTop, .bottom: item.borderBottom,
                                            .left: item.borderLeft, .right: item.borderRight]
        let outerRadius = roundedCorners.isEmpty ? 0 : radius
        for side in sideOrder {
            guard let edge = edges[side], edge.isVisible else { continue }
            if edge.style == .solid {
                fillSolidSide(side, of: item, rect: rect, outerRadius: outerRadius,
                              roundedCorners: roundedCorners, in: context)
                continue
            }
            switch side {
            case .top:
                strokeEdge(from: CGPoint(x: rect.minX + leftInset, y: rect.minY + topInset),
                           to: CGPoint(x: rect.maxX - rightInset, y: rect.minY + topInset),
                           width: edge.width, style: edge.style, color: edge.color)
            case .bottom:
                strokeEdge(from: CGPoint(x: rect.minX + leftInset, y: rect.maxY - bottomInset),
                           to: CGPoint(x: rect.maxX - rightInset, y: rect.maxY - bottomInset),
                           width: edge.width, style: edge.style, color: edge.color)
            case .left:
                strokeEdge(from: CGPoint(x: rect.minX + leftInset, y: rect.minY + topInset),
                           to: CGPoint(x: rect.minX + leftInset, y: rect.maxY - bottomInset),
                           width: edge.width, style: edge.style, color: edge.color)
            case .right:
                strokeEdge(from: CGPoint(x: rect.maxX - rightInset, y: rect.minY + topInset),
                           to: CGPoint(x: rect.maxX - rightInset, y: rect.maxY - bottomInset),
                           width: edge.width, style: edge.style, color: edge.color)
            }
        }
        context.restoreGState()
    }

    private enum BoxSide { case top, bottom, left, right }

    /// A solid side of a border that is not one uniform frame, as WebKit's
    /// `BorderPainter` paints it (`paintOneBorderSide`,
    /// `clipBorderSidePolygon`): its part of the border ring between the
    /// outer and inner borders, rounded where the box is, cut from each
    /// neighbour along the line from their outer corner to their inner one.
    /// The cut is antialiased where the neighbour is another colour and
    /// aliased where it is the same, so a join of one colour leaves no seam.
    ///
    /// Measured, S001 ua-all (dpr 3): `cc2`'s red left meets its black
    /// bottom on the diagonal, the pixel there (191, 64, 0), the bottom
    /// painted first; `ri`'s 4px inset border with a 10px radius keeps its
    /// curve, 180 where its 44 top meets its 212 right, the top first.
    private static func fillSolidSide(
        _ side: BoxSide, of item: DisplayFillItem, rect: CGRect, outerRadius: CGFloat,
        roundedCorners: UIRectCorner, in context: CGContext
    ) {
        func occupied(_ edge: BorderEdge) -> CGFloat { edge.style == .none ? 0 : edge.width }
        let top = occupied(item.borderTop), bottom = occupied(item.borderBottom)
        let left = occupied(item.borderLeft), right = occupied(item.borderRight)
        let inner = CGRect(x: rect.minX + left, y: rect.minY + top,
                           width: max(0, rect.width - left - right), height: max(0, rect.height - top - bottom))
        func outer(_ corner: UIRectCorner) -> CGFloat { roundedCorners.contains(corner) ? outerRadius : 0 }
        let outerRadii = CornerRadii(
            topLeft: CGSize(width: outer(.topLeft), height: outer(.topLeft)),
            topRight: CGSize(width: outer(.topRight), height: outer(.topRight)),
            bottomRight: CGSize(width: outer(.bottomRight), height: outer(.bottomRight)),
            bottomLeft: CGSize(width: outer(.bottomLeft), height: outer(.bottomLeft)))
        let innerRadii = CornerRadii(
            topLeft: CGSize(width: max(0, outer(.topLeft) - left), height: max(0, outer(.topLeft) - top)),
            topRight: CGSize(width: max(0, outer(.topRight) - right), height: max(0, outer(.topRight) - top)),
            bottomRight: CGSize(width: max(0, outer(.bottomRight) - right), height: max(0, outer(.bottomRight) - bottom)),
            bottomLeft: CGSize(width: max(0, outer(.bottomLeft) - left), height: max(0, outer(.bottomLeft) - bottom)))

        // `findIntersection`: where the line through p1 and p2 crosses the
        // one through d1 and d2.
        func intersection(_ p1: CGPoint, _ p2: CGPoint, _ d1: CGPoint, _ d2: CGPoint) -> CGPoint? {
            let px = p2.x - p1.x, py = p2.y - p1.y, dx = d2.x - d1.x, dy = d2.y - d1.y
            let denominator = px * dy - py * dx
            guard denominator != 0 else { return nil }
            let t = ((d1.x - p1.x) * dy - (d1.y - p1.y) * dx) / denominator
            return CGPoint(x: p1.x + t * px, y: p1.y + t * py)
        }
        // The side's quad from the outer corner at its start, through the
        // inner corners, to the outer corner at its end; at a rounded inner
        // corner the cut runs on to the chord of the inner curve, so the
        // whole ring there is divided.
        var quad: [CGPoint]
        let first: BorderEdge, second: BorderEdge, edge: BorderEdge
        switch side {
        case .top:
            edge = item.borderTop; first = item.borderLeft; second = item.borderRight
            quad = [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: inner.minX, y: inner.minY),
                    CGPoint(x: inner.maxX, y: inner.minY), CGPoint(x: rect.maxX, y: rect.minY)]
            let a = innerRadii.topLeft, b = innerRadii.topRight
            if a != .zero, let p = intersection(quad[0], quad[1], CGPoint(x: quad[1].x + a.width, y: quad[1].y),
                                                CGPoint(x: quad[1].x, y: quad[1].y + a.height)) { quad[1] = p }
            if b != .zero, let p = intersection(quad[3], quad[2], CGPoint(x: quad[2].x - b.width, y: quad[2].y),
                                                CGPoint(x: quad[2].x, y: quad[2].y + b.height)) { quad[2] = p }
        case .left:
            edge = item.borderLeft; first = item.borderTop; second = item.borderBottom
            quad = [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: inner.minX, y: inner.minY),
                    CGPoint(x: inner.minX, y: inner.maxY), CGPoint(x: rect.minX, y: rect.maxY)]
            let a = innerRadii.topLeft, b = innerRadii.bottomLeft
            if a != .zero, let p = intersection(quad[0], quad[1], CGPoint(x: quad[1].x + a.width, y: quad[1].y),
                                                CGPoint(x: quad[1].x, y: quad[1].y + a.height)) { quad[1] = p }
            if b != .zero, let p = intersection(quad[3], quad[2], CGPoint(x: quad[2].x + b.width, y: quad[2].y),
                                                CGPoint(x: quad[2].x, y: quad[2].y - b.height)) { quad[2] = p }
        case .bottom:
            edge = item.borderBottom; first = item.borderLeft; second = item.borderRight
            quad = [CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: inner.minX, y: inner.maxY),
                    CGPoint(x: inner.maxX, y: inner.maxY), CGPoint(x: rect.maxX, y: rect.maxY)]
            let a = innerRadii.bottomLeft, b = innerRadii.bottomRight
            if a != .zero, let p = intersection(quad[0], quad[1], CGPoint(x: quad[1].x + a.width, y: quad[1].y),
                                                CGPoint(x: quad[1].x, y: quad[1].y - a.height)) { quad[1] = p }
            if b != .zero, let p = intersection(quad[3], quad[2], CGPoint(x: quad[2].x - b.width, y: quad[2].y),
                                                CGPoint(x: quad[2].x, y: quad[2].y - b.height)) { quad[2] = p }
        case .right:
            edge = item.borderRight; first = item.borderTop; second = item.borderBottom
            quad = [CGPoint(x: rect.maxX, y: rect.minY), CGPoint(x: inner.maxX, y: inner.minY),
                    CGPoint(x: inner.maxX, y: inner.maxY), CGPoint(x: rect.maxX, y: rect.maxY)]
            let a = innerRadii.topRight, b = innerRadii.bottomRight
            if a != .zero, let p = intersection(quad[0], quad[1], CGPoint(x: quad[1].x - a.width, y: quad[1].y),
                                                CGPoint(x: quad[1].x, y: quad[1].y + a.height)) { quad[1] = p }
            if b != .zero, let p = intersection(quad[3], quad[2], CGPoint(x: quad[2].x - b.width, y: quad[2].y),
                                                CGPoint(x: quad[2].x, y: quad[2].y - b.height)) { quad[2] = p }
        }
        func matches(_ other: BorderEdge) -> Bool {
            other.isVisible && other.style == edge.style && other.color == edge.color
        }
        let firstMatches = matches(first), secondMatches = matches(second)

        context.saveGState()
        defer { context.restoreGState() }
        let ring = CGMutablePath()
        ring.addPath(roundedPath(rect, outerRadii))
        if !inner.isEmpty { ring.addPath(roundedPath(inner, innerRadii)) }
        context.addPath(ring)
        context.clip(using: .evenOdd)
        func clip(_ points: [CGPoint], antialias: Bool) {
            context.setShouldAntialias(antialias)
            context.beginPath()
            context.addLines(between: points)
            context.closePath()
            context.clip()
        }
        let horizontal = side == .top || side == .bottom
        if firstMatches == secondMatches {
            clip(quad, antialias: !firstMatches)
        } else {
            // One end aliased, the other not: each clip squares off the end
            // the other one cuts.
            let squaredEnd = horizontal ? CGPoint(x: quad[3].x, y: quad[2].y) : CGPoint(x: quad[2].x, y: quad[3].y)
            clip([quad[0], quad[1], quad[2], squaredEnd, quad[3]], antialias: !firstMatches)
            let squaredStart = horizontal ? CGPoint(x: quad[0].x, y: quad[1].y) : CGPoint(x: quad[1].x, y: quad[0].y)
            clip([quad[0], squaredStart, quad[1], quad[2], quad[3]], antialias: !secondMatches)
        }
        context.setShouldAntialias(true)
        context.setFillColor(edge.color.cgColor)
        context.fill(rect)
    }

    private struct CornerRadii {
        var topLeft: CGSize, topRight: CGSize, bottomRight: CGSize, bottomLeft: CGSize
    }

    /// A rect with elliptical corners (cubic arcs).
    private static func roundedPath(_ rect: CGRect, _ radii: CornerRadii) -> CGPath {
        let k: CGFloat = 0.5522847498
        let path = CGMutablePath()
        let tl = radii.topLeft, tr = radii.topRight, br = radii.bottomRight, bl = radii.bottomLeft
        path.move(to: CGPoint(x: rect.minX + tl.width, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - tr.width, y: rect.minY))
        if tr != .zero {
            path.addCurve(to: CGPoint(x: rect.maxX, y: rect.minY + tr.height),
                          control1: CGPoint(x: rect.maxX - tr.width * (1 - k), y: rect.minY),
                          control2: CGPoint(x: rect.maxX, y: rect.minY + tr.height * (1 - k)))
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br.height))
        if br != .zero {
            path.addCurve(to: CGPoint(x: rect.maxX - br.width, y: rect.maxY),
                          control1: CGPoint(x: rect.maxX, y: rect.maxY - br.height * (1 - k)),
                          control2: CGPoint(x: rect.maxX - br.width * (1 - k), y: rect.maxY))
        }
        path.addLine(to: CGPoint(x: rect.minX + bl.width, y: rect.maxY))
        if bl != .zero {
            path.addCurve(to: CGPoint(x: rect.minX, y: rect.maxY - bl.height),
                          control1: CGPoint(x: rect.minX + bl.width * (1 - k), y: rect.maxY),
                          control2: CGPoint(x: rect.minX, y: rect.maxY - bl.height * (1 - k)))
        }
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tl.height))
        if tl != .zero {
            path.addCurve(to: CGPoint(x: rect.minX + tl.width, y: rect.minY),
                          control1: CGPoint(x: rect.minX, y: rect.minY + tl.height * (1 - k)),
                          control2: CGPoint(x: rect.minX + tl.width * (1 - k), y: rect.minY))
        }
        path.closeSubpath()
        return path
    }

    private static func drawText(
        _ item: DisplayTextItem, string: NSAttributedString, line: CTLine,
        decorationOnly: Bool, textDecoration: ((CTLine, NSAttributedString, CGContext) -> Void)?, in context: CGContext
    ) {
        guard !item.text.isEmpty else { return }
        context.saveGState()
        if let rotation = item.paintTransform { context.concatenate(rotation.matrix) }
        if item.writingMode == .verticalRTL {
            // Core Text's vertical run matrices keep CJK upright after the
            // inline axis turns downward. Do not rotate individual characters.
            context.translateBy(x: item.baselineY, y: item.rect.minY)
            context.rotate(by: .pi / 2)
        } else {
            context.translateBy(x: item.rect.minX, y: item.baselineY)
        }
        // CSS decorations go with the glyphs, as WebKit paints a text box:
        // underlines and overlines under them, line-throughs over them.
        let length = item.writingMode == .horizontal ? item.rect.width : item.rect.height
        if !decorationOnly, !item.textDecorations.isEmpty {
            TextDecorationPainter.draw(item.textDecorations, where: { $0 != .lineThrough },
                                       length: length, line: line, string: string, in: context)
        }
        context.saveGState()
        context.scaleBy(x: 1, y: -1)
        context.textMatrix = .identity
        context.textPosition = .zero
        if decorationOnly {
            textDecoration?(line, string, context)
        } else {
            CTLineDraw(line, context)
            var syntheticBoldOffset: CGFloat = 0
            string.enumerateAttribute(
                BrowserTextAttributes.syntheticBoldOffset,
                in: NSRange(location: 0, length: string.length)
            ) { value, _, stop in
                if let offset = (value as? NSNumber)?.doubleValue, offset > 0 {
                    syntheticBoldOffset = offset
                    stop.pointee = true
                }
            }
            // The synthetic-bold marker calls for a second pass offset along
            // the inline axis.
            if syntheticBoldOffset > 0 {
                context.textPosition = CGPoint(x: syntheticBoldOffset, y: 0)
                CTLineDraw(line, context)
            }
        }
        context.restoreGState()
        if !decorationOnly, !item.textDecorations.isEmpty {
            TextDecorationPainter.draw(item.textDecorations, where: { $0 == .lineThrough },
                                       length: length, line: line, string: string, in: context)
        }
        context.restoreGState()
    }
}
