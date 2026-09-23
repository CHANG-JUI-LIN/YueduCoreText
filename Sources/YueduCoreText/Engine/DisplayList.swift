import CoreGraphics
import CoreText
import Foundation
import UIKit

/// Display items carry PAGE CANVAS-local rects (Phase 2C contract).
/// The canvas equals the actual page viewport.
public enum DisplayItem {
    case text(DisplayTextItem)
    case fill(DisplayFillItem)
    case image(DisplayImageItem)
}

final class TextDrawingResources {
    let attributed: NSAttributedString
    let line: CTLine
    init(_ item: DisplayTextItem) {
        attributed = item.attributedText
        line = CTLineCreateWithAttributedString(attributed)
    }
    /// The same drawing text with a line of the caller's own. Core Text layout
    /// objects are used by one thread at a time; the attributed text is immutable.
    init(copying other: TextDrawingResources) {
        attributed = other.attributed
        line = CTLineCreateWithAttributedString(attributed)
    }
}

public struct DisplayTextItem {
    // Populated only by viewport preparation. Geometry translations preserve
    // this immutable artifact; theme/config changes produce new display items.
    var preparedDrawing: TextDrawingResources?

    public let sourceRange: NSRange
    public let nodeID: Int
    public let linkTarget: String?
    public let writingMode: ReaderWritingMode
    public let rect: PageLocalRect
    /// Physical baseline y in horizontal mode; physical baseline x in vertical-rl.
    /// Kept under its original name for source compatibility.
    public let baselineY: CGFloat
    public let font: UIFont
    public let color: UIColor
    /// The visible text slice (for rendering and hit-testing).
    public let text: String
    /// The shaped line this run belongs to (untrimmed line range), for
    /// precise string-index → typographic-offset mapping.
    public let ctLine: CTLine?
    public let sourceMapping: TextSourceMapping
    public let renderedTextOverride: String?

    /// Recover the exact attributes used by shaping instead of discarding
    /// kern, synthetic bold, and regex styles when constructing the draw list.
    public var attributedText: NSAttributedString {
        var presentation = text.replacingOccurrences(of: "\u{00AD}", with: "\u{2060}")
        if case .linear(let range) = sourceMapping, let ctLine {
            let hasHyphen = (CTLineGetGlyphRuns(ctLine) as! [CTRun]).contains { run in
                let attributes = CTRunGetAttributes(run) as! [NSAttributedString.Key: Any]
                let r = CTRunGetStringRange(run)
                return attributes[TextBreakingAttributes.visibleHyphen] as? Bool == true
                    && NSIntersectionRange(range, NSRange(location:r.location,length:r.length)).length > 0
            }
            if hasHyphen {
                if range.length > sourceRange.length { presentation += "-" }
                else if presentation.hasSuffix("\u{2060}") { presentation.removeLast(); presentation += "-" }
            }
        }
        let result = NSMutableAttributedString(string: presentation, attributes: [
            .font: font, .foregroundColor: color,
        ])
        guard let ctLine else { return result }
        let shapedRange: NSRange
        switch sourceMapping {
        case .linear(let range), .annotation(let range): shapedRange = range
        case .wholeRange:
            let range = CTLineGetStringRange(ctLine)
            shapedRange = NSRange(location: range.location, length: range.length)
        }
        for run in CTLineGetGlyphRuns(ctLine) as! [CTRun] {
            let runRange = CTRunGetStringRange(run)
            let overlap = NSIntersectionRange(
                shapedRange, NSRange(location: runRange.location, length: runRange.length)
            )
            guard overlap.length > 0 else { continue }
            let local = NSIntersectionRange(
                NSRange(location: overlap.location - shapedRange.location, length: overlap.length),
                NSRange(location: 0, length: result.length)
            )
            guard local.length > 0 else { continue }
            var attributes = CTRunGetAttributes(run) as! [NSAttributedString.Key: Any]
            // Theme-only redraws recolor inherited text, while explicit regex
            // foreground colors remain part of the immutable rule snapshot.
            if attributes[BrowserTextAttributes.preservedForeground] == nil {
                attributes[.foregroundColor] = color
            }
            result.setAttributes(attributes, range: local)
        }
        return result
    }

    public init(
        sourceRange: NSRange,
        nodeID: Int,
        linkTarget: String?,
        writingMode: ReaderWritingMode,
        rect: PageLocalRect,
        baselineY: CGFloat,
        font: UIFont,
        color: UIColor,
        text: String,
        ctLine: CTLine?,
        sourceMapping: TextSourceMapping? = nil,
        renderedTextOverride: String? = nil
    ) {
        self.sourceRange = sourceRange
        self.nodeID = nodeID
        self.linkTarget = linkTarget
        self.writingMode = writingMode
        self.rect = rect
        self.baselineY = baselineY
        self.font = font
        self.color = color
        self.text = text
        self.ctLine = ctLine
        self.sourceMapping = sourceMapping ?? .linear(shapedRange: sourceRange)
        self.renderedTextOverride = renderedTextOverride
    }
}

/// A bordered box: background fill + full four-edge border + radius.
/// Phase 2C: one fill item carries the COMPLETE paint representation —
/// dotted/dashed borders render all four sides, never a lone top line.
public struct DisplayFillItem {
    public let rect: PageLocalRect
    public let color: UIColor
    public let cornerRadius: CGFloat
    public let borderTop: BorderEdge
    public let borderBottom: BorderEdge
    public let borderLeft: BorderEdge
    public let borderRight: BorderEdge
    public let nodeID: Int
    public let writingMode: ReaderWritingMode
    public let fragmentPosition: BlockDecorationFragmentPosition
    /// See `FillFragment.isBackgroundPaint` — the authored page surface, which
    /// a reader-chosen background image replaces.
    public let isBackgroundPaint: Bool

    public init(
        rect: PageLocalRect,
        color: UIColor,
        cornerRadius: CGFloat,
        borderTop: BorderEdge,
        borderBottom: BorderEdge,
        borderLeft: BorderEdge,
        borderRight: BorderEdge,
        nodeID: Int,
        writingMode: ReaderWritingMode,
        fragmentPosition: BlockDecorationFragmentPosition = .single,
        isBackgroundPaint: Bool = false
    ) {
        self.rect = rect
        self.color = color
        self.cornerRadius = cornerRadius
        self.borderTop = borderTop
        self.borderBottom = borderBottom
        self.borderLeft = borderLeft
        self.borderRight = borderRight
        self.nodeID = nodeID
        self.writingMode = writingMode
        self.fragmentPosition = fragmentPosition
        self.isBackgroundPaint = isBackgroundPaint
    }

    public var hasVisibleBorder: Bool {
        borderTop.isVisible || borderBottom.isVisible || borderLeft.isVisible || borderRight.isVisible
    }
}

public struct DisplayImageItem {
    public let source: String
    public let image: UIImage?
    public let sourceRange: NSRange
    public let nodeID: Int
    public let linkTarget: String?
    public let writingMode: ReaderWritingMode
    public let rect: PageLocalRect
    public let alt: String?
    /// Painted CSS background — draws, never hit-tests. See `ImageFragment`.
    public let isBackgroundPaint: Bool

    public init(
        source: String,
        image: UIImage?,
        sourceRange: NSRange,
        nodeID: Int,
        linkTarget: String?,
        writingMode: ReaderWritingMode,
        rect: PageLocalRect,
        alt: String?,
        isBackgroundPaint: Bool = false
    ) {
        self.source = source
        self.image = image
        self.sourceRange = sourceRange
        self.nodeID = nodeID
        self.linkTarget = linkTarget
        self.writingMode = writingMode
        self.rect = rect
        self.alt = alt
        self.isBackgroundPaint = isBackgroundPaint
    }
}

public struct DisplayList {
    public init(items: [DisplayItem]) { self.items = items }
    public let items: [DisplayItem]
    public static var empty: DisplayList { DisplayList(items: []) }

    /// Exact paint and interaction equality for a retained rendering surface.
    /// A viewport revision elsewhere in the document does not dirty this surface.
    /// CTLine identity includes its immutable shaping attributes; a new line is
    /// conservatively treated as changed even when the plain text matches.
    public func hasSameContents(as other: DisplayList, geometryTolerance: CGFloat = 0) -> Bool {
        guard items.count == other.items.count else { return false }
        func same(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) <= geometryTolerance }
        func sameRect(_ a: PageLocalRect, _ b: PageLocalRect) -> Bool {
            same(a.minX, b.minX) && same(a.minY, b.minY)
                && same(a.rawValue.width, b.rawValue.width) && same(a.rawValue.height, b.rawValue.height)
        }
        return zip(items, other.items).allSatisfy { lhs, rhs in
            switch (lhs, rhs) {
            case (.text(let a), .text(let b)):
                return a.ctLine === b.ctLine && sameRect(a.rect, b.rect) && same(a.baselineY, b.baselineY)
                    && a.sourceRange == b.sourceRange && a.nodeID == b.nodeID && a.linkTarget == b.linkTarget
                    && a.writingMode == b.writingMode && a.font == b.font && a.color == b.color
                    && a.text == b.text && a.sourceMapping == b.sourceMapping
                    && a.renderedTextOverride == b.renderedTextOverride
            case (.fill(let a), .fill(let b)):
                return sameRect(a.rect, b.rect) && a.color == b.color && a.cornerRadius == b.cornerRadius
                    && a.borderTop == b.borderTop && a.borderBottom == b.borderBottom
                    && a.borderLeft == b.borderLeft && a.borderRight == b.borderRight
                    && a.nodeID == b.nodeID && a.writingMode == b.writingMode
                    && a.fragmentPosition == b.fragmentPosition && a.isBackgroundPaint == b.isBackgroundPaint
            case (.image(let a), .image(let b)):
                return a.image === b.image && a.source == b.source && sameRect(a.rect, b.rect)
                    && a.sourceRange == b.sourceRange && a.nodeID == b.nodeID && a.linkTarget == b.linkTarget
                    && a.writingMode == b.writingMode && a.alt == b.alt && a.isBackgroundPaint == b.isBackgroundPaint
            default: return false
            }
        }
    }
}

/// Flattens a page's fragment tree (groups are recursive) into a flat draw list.
/// Coordinates are page canvas-local already.
public enum DisplayListBuilder {

    /// Builds a display list for one page. `sourceText` supplies the visible
    /// slices for text items (needed by the renderer / hit-testing).
    public static func build(for page: PageFragments, sourceText: String = "", themeTextColor: UIColor? = nil, oldThemeColor: UIColor? = nil) -> DisplayList {
        var items: [DisplayItem] = []
        collect(page.fragments, into: &items, sourceText: sourceText)
        if let themeTextColor, let oldThemeColor {
            items = items.map { item in
                guard case .text(let text) = item, text.color == oldThemeColor else { return item }
                return .text(DisplayTextItem(sourceRange: text.sourceRange, nodeID: text.nodeID,
                    linkTarget: text.linkTarget, writingMode: text.writingMode, rect: text.rect,
                    baselineY: text.baselineY, font: text.font, color: themeTextColor, text: text.text,
                    ctLine: text.ctLine, sourceMapping: text.sourceMapping,
                    renderedTextOverride: text.renderedTextOverride))
            }
        }
        return DisplayList(items: items)
    }

    private static func collect(_ fragments: [Fragment], into items: inout [DisplayItem], sourceText: String) {
        for fragment in fragments {
            switch fragment {
            case .text(let t):
                let visible = t.renderedTextOverride ?? slice(sourceText, range: t.sourceRange)
                items.append(.text(DisplayTextItem(
                    sourceRange: t.sourceRange,
                    nodeID: t.nodeID,
                    linkTarget: t.linkTarget,
                    writingMode: t.writingMode,
                    rect: t.rect,
                    baselineY: t.baselineY,
                    font: t.font,
                    color: t.color,
                    text: visible,
                    ctLine: t.ctLine,
                    sourceMapping: t.sourceMapping,
                    renderedTextOverride: t.renderedTextOverride
                )))
            case .fill(let f):
                items.append(.fill(DisplayFillItem(
                    rect: f.rect, color: f.color, cornerRadius: f.cornerRadius,
                    borderTop: f.borderTop, borderBottom: f.borderBottom,
                    borderLeft: f.borderLeft, borderRight: f.borderRight,
                    nodeID: f.nodeID, writingMode: f.writingMode,
                    fragmentPosition: f.fragmentPosition,
                    isBackgroundPaint: f.isBackgroundPaint
                )))
            case .image(let i):
                items.append(.image(DisplayImageItem(
                    source: i.source, image: i.image, sourceRange: i.sourceRange,
                    nodeID: i.nodeID, linkTarget: i.linkTarget,
                    writingMode: i.writingMode, rect: i.rect, alt: i.alt,
                    isBackgroundPaint: i.isBackgroundPaint
                )))
            case .group(let children):
                collect(children, into: &items, sourceText: sourceText)
            }
        }
    }

    private static func slice(_ sourceText: String, range: NSRange) -> String {
        guard !sourceText.isEmpty, range.length > 0 else { return "" }
        let ns = sourceText as NSString
        guard range.location >= 0,
              range.location + range.length <= ns.length else { return "" }
        return ns.substring(with: range)
    }
}
