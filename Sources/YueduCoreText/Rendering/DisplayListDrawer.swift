import UIKit
import CoreText

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
        textDecoration: ((CTLine, NSAttributedString, CGContext) -> Void)? = nil
    ) {
        var pendingText: [DisplayTextItem] = []
        func flushText() {
            let shaped = pendingText.map { item in
                let string = item.attributedText
                return (item, string, CTLineCreateWithAttributedString(string))
            }
            // Decorations may extend past an inline element's own bounds.
            // Paint the complete text group underneath all its glyphs so a
            // later span's padding cannot erase the preceding span's ink.
            for (item, string, line) in shaped {
                drawText(item, string: string, line: line, decorationOnly: true, textDecoration: textDecoration, in: context)
            }
            for (item, string, line) in shaped {
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
                if let image = i.image {
                    image.draw(in: i.rect.rawValue)
                } else {
                    UIColor.lightGray.setFill()
                    context.fill(i.rect.rawValue)
                }
            }
        }
        flushText()
    }

    /// One bordered box: background (clipped to radius) + four border edges.
    private static func drawFill(_ item: DisplayFillItem, in context: CGContext) {
        let rect = item.rect.rawValue
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
                fragmentPosition: item.fragmentPosition, isBackgroundPaint: item.isBackgroundPaint), in: context)
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
            case .solid, .none:
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
            case .solid, .none:
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

        // Top edge spans the full box width; side edges start below the top
        // border width and end above the bottom border width so corners don't
        // double-stroke.
        let topInset = item.borderTop.width / 2
        let bottomInset = item.borderBottom.width / 2
        let leftInset = item.borderLeft.width / 2
        let rightInset = item.borderRight.width / 2

        strokeEdge(
            from: CGPoint(x: rect.minX + leftInset, y: rect.minY + topInset),
            to: CGPoint(x: rect.maxX - rightInset, y: rect.minY + topInset),
            width: item.borderTop.width,
            style: item.borderTop.style,
            color: item.borderTop.color
        )
        strokeEdge(
            from: CGPoint(x: rect.minX + leftInset, y: rect.maxY - bottomInset),
            to: CGPoint(x: rect.maxX - rightInset, y: rect.maxY - bottomInset),
            width: item.borderBottom.width,
            style: item.borderBottom.style,
            color: item.borderBottom.color
        )
        strokeEdge(
            from: CGPoint(x: rect.minX + leftInset, y: rect.minY + topInset),
            to: CGPoint(x: rect.minX + leftInset, y: rect.maxY - bottomInset),
            width: item.borderLeft.width,
            style: item.borderLeft.style,
            color: item.borderLeft.color
        )
        strokeEdge(
            from: CGPoint(x: rect.maxX - rightInset, y: rect.minY + topInset),
            to: CGPoint(x: rect.maxX - rightInset, y: rect.maxY - bottomInset),
            width: item.borderRight.width,
            style: item.borderRight.style,
            color: item.borderRight.color
        )
        context.restoreGState()
    }

    private static func drawText(
        _ item: DisplayTextItem, string: NSAttributedString, line: CTLine,
        decorationOnly: Bool, textDecoration: ((CTLine, NSAttributedString, CGContext) -> Void)?, in context: CGContext
    ) {
        guard !item.text.isEmpty else { return }
        context.saveGState()
        if item.writingMode == .verticalRTL {
            // Core Text's vertical run matrices keep CJK upright after the
            // inline axis turns downward. Do not rotate individual characters.
            context.translateBy(x: item.baselineY, y: item.rect.minY)
            context.rotate(by: .pi / 2)
        } else {
            context.translateBy(x: item.rect.minX, y: item.baselineY)
        }
        context.scaleBy(x: 1, y: -1)
        context.textMatrix = .identity
        context.textPosition = .zero
        if decorationOnly {
            textDecoration?(line, string, context)
        } else {
            CTLineDraw(line, context)
        }
        context.restoreGState()
    }
}
