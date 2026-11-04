import CoreText
import Foundation
import UIKit
import YueduCoreTextTypography

/// One list item's outside marker, built once with the box tree. A marker is
/// generated content: it takes no characters of the chapter's source text, so
/// no reading position, bookmark or highlight moves when one appears.
///
/// Every number here is iOS 27.2 WKWebView's, measured with
/// `scripts/fidelity/list_probe.sh` (App repository) on the S001c test book:
/// docs/superpowers/specs/2026-11-03-browser-list-markers-design.md §5, §9.
final class ListMarker {
    enum Content {
        /// A counter, laid out once in the list item's font. Built here and kept,
        /// so a viewport snapshot draws the same line object every time.
        case text(line: CTLine, string: String, width: CGFloat)
        /// `disc`, `circle`, `square`: a shape WebKit draws itself, sized and
        /// placed from the marker's rounded `ascent`.
        case bullet(ListMarkerBullet)
    }

    let content: Content
    let text: ListMarkerText
    /// The list item's, never the anchoring line's: WebKit's `computeMarkerStyle`
    /// inherits the marker from the list item (measured: a 25.5px li around a
    /// 17px p draws a 25.5px marker).
    let font: UIFont
    /// `font`'s ascent and descent rounded up, as WebKit rounds every inline
    /// box's: the bullet's size and place, and the marker's content area across
    /// a vertical line (design §10).
    let ascent: CGFloat
    let descent: CGFloat
    /// The chapter's: a vertical marker is set as the line's text is and placed
    /// by the vertical rules.
    let writingMode: ReaderWritingMode
    let color: UIColor
    let nodeID: Int
    /// Where the list item's content starts in the chapter's source text: the
    /// marker's zero-length place when it has no line to sit on.
    let sourceLocation: Int
    /// The list item's box. Its border box start is where the marker ends, and
    /// it outlives the marker: the item is an ancestor of the box the marker is
    /// anchored on, or that box itself.
    unowned let listItem: BlockBox
    /// The marker's horizontal inline box about the baseline: the list item's
    /// font with the list item's line-height, split by the half-leading rule
    /// the line's strut and text use. Measured: a marker grows its line
    /// exactly as such a box would (25.5px li around a 17px p: +12.75), and not
    /// at all when its font and line-height are the line's own
    /// (`line-height: 1`, 多看 footnotes).
    ///
    /// WebKit rounds font ascent and descent up for every inline box; this
    /// engine's text does not, so the marker does not either. Rounding only the
    /// marker would grow every same-font line by about 0.38 (PingFang 17px at
    /// line-height 17), where WebKit grows it by 0. The bullet's own size and
    /// place keep the rounded `ascent`: those were measured. A vertical line
    /// takes its room by another rule (`InlineLayout`, design §10).
    let above: CGFloat
    let below: CGFloat

    /// The line an item with no line of its own holds for its marker, about
    /// the marker's baseline. Horizontally the marker's inline box: one item
    /// line (S001c 07-empty: 25.5). Across a vertical line the item's
    /// line-height or the marker's content area, whichever is wider, centred:
    /// the item's own line with the room a marker takes (S001d 14-empty: 25.5,
    /// 14-empty-lh1: 25, not 17).
    var ownLine: (above: CGFloat, below: CGFloat) {
        guard writingMode == .verticalRTL else { return (above, below) }
        let extent = max(above + below, ascent + descent)
        return (extent / 2, extent / 2)
    }

    init(content: Content, text: ListMarkerText, font: UIFont, color: UIColor, nodeID: Int,
         sourceLocation: Int, listItem: BlockBox, writingMode: ReaderWritingMode, above: CGFloat, below: CGFloat) {
        self.content = content; self.text = text; self.font = font; self.color = color
        self.nodeID = nodeID; self.sourceLocation = sourceLocation; self.listItem = listItem
        (self.ascent, self.descent) = InlineLayout.roundedContentExtent(font)
        self.writingMode = writingMode
        self.above = above; self.below = below
    }

    /// The marker of `listItem`, or nil when it draws none. Only outside
    /// markers are drawn yet: an inside marker takes room on the line, which
    /// nothing here reserves (design §4), and a chapter with one is admitted
    /// to the legacy engine instead (`ListMarkerSupport`).
    static func make(
        for listItem: BlockBox, ordinal: Int?, nodeID: Int, sourceLocation: Int, config: BrowserLayoutConfig
    ) -> ListMarker? {
        let style = listItem.style
        guard style.isListItem, style.listStylePosition == .outside else { return nil }
        guard let ordinal else {
            // `ListItemOrdinals` numbers every list item; a stage that copies a
            // style node without its ordinal drops it (design §7).
            assertionFailure("list item node[\(nodeID)] reached the box tree without an ordinal")
            config.onDiagnostic?(CSSFrontendDiagnostic(stage: .style, stylesheet: nil,
                semanticPath: "node[\(nodeID)]", property: "list-style-type",
                message: "list item has no ordinal; its marker is not drawn"))
            return nil
        }
        guard let text = ListMarkerText(type: style.listStyleType, ordinal: ordinal) else { return nil }
        if case .counterStyle(let name) = style.listStyleType, CounterStyle.predefined[name] == nil {
            // A name WebKit may know (hiragana, lower-greek …) draws as decimal
            // here; the report says which book wants which style.
            config.onDiagnostic?(CSSFrontendDiagnostic(stage: .style, stylesheet: nil,
                semanticPath: "node[\(nodeID)]", property: "list-style-type",
                message: "counter style \(name) has no definition; the marker draws as decimal"))
        }
        let font = InlineLayout.resolvedFont(for: style, resolver: config.fontResolver)
        let box = InlineLayout.halfLeadingBox(font, lineHeight: style.lineHeight)
        let color = style.color ?? .black
        let content: Content
        switch text {
        case .bullet(let bullet):
            content = .bullet(bullet)
        case .counter:
            let string = text.string ?? ""
            // The UA `::marker` rule: tabular figures. `white-space: pre` and
            // `text-transform: none` hold by construction, as the string is ours.
            let attributed = NSMutableAttributedString(string: string, attributes:
                InlineLayout.textAttributes(for: style, resolver: config.fontResolver, font: tabularFigures(font)))
            let vertical = config.writingMode == .verticalRTL
            if let cjk = config.cjkTypographyStyle {
                CJKTypography.apply(to: attributed, style: cjk, vertical: vertical)
            }
            // Latin numerals and ". " lie on their side, ideographs stand, and
            // 「、」 takes its vertical form, as on the line (measured).
            if vertical { InlineLayout.applyVerticalOrientation(to: attributed) }
            let line = CTLineCreateWithAttributedString(attributed)
            content = .text(line: line, string: string,
                            width: CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)))
        }
        return ListMarker(content: content, text: text, font: font, color: color, nodeID: nodeID,
                          sourceLocation: sourceLocation, listItem: listItem, writingMode: config.writingMode,
                          above: box.above, below: box.below)
    }

    private static func tabularFigures(_ font: UIFont) -> UIFont {
        let descriptor = font.fontDescriptor.addingAttributes([.featureSettings: [[
            UIFontDescriptor.FeatureKey.type: kNumberSpacingType,
            UIFontDescriptor.FeatureKey.selector: kMonospacedNumbersSelector,
        ]]])
        return UIFont(descriptor: descriptor, size: font.pointSize)
    }

    /// Hands `marker` to the line it sits on: the first line of the first
    /// inline formatting context in `listItem`'s content, searched in order
    /// (WebKit `RenderListItem::firstFormattedLineRootFor`, design §8). A float
    /// is passed over; a table or a block image ends the search with no line.
    /// With no line the marker stays on the list item itself.
    static func anchor(_ marker: ListMarker, in listItem: BlockBox) {
        if let host = firstLineRoot(in: listItem) {
            // Items anchor once their content is built, innermost first; the
            // markers sharing a line are nested items, so prepending keeps
            // them in document order, which VoiceOver reads them in.
            host.listMarkers.insert(marker, at: 0)
        } else {
            listItem.unanchoredListMarker = marker
        }
    }

    private enum Search { case found(BlockBox), stop, none }

    private static func firstLineRoot(in box: BlockBox) -> BlockBox? {
        if case .found(let host) = search(box) { return host }
        return nil
    }

    private static func search(_ box: BlockBox) -> Search {
        for child in box.children {
            if child.isFloated { continue }
            if child.imageAttachment != nil || child.style.display == .table { return .stop }
            switch search(child) {
            case .found(let host): return .found(host)
            case .stop: return .stop
            case .none: continue
            }
        }
        // A box holds runs of its own only when its other children are floats,
        // which come first in the source: the runs are its first line.
        return box.inlineRuns.isEmpty ? .none : .found(box)
    }
}

/// Which list markers this engine draws, judged on the computed style tree
/// layout uses, so an `inside` declared and then overridden, or one on a list
/// of `list-style-type: none`, never counts.
///
/// Fallback: a chapter in which some list item would draw an inside marker is
/// laid out by the legacy engine, whole (`UnsupportedFeature.listMarker`). An
/// inside marker takes room on its line and breaks with it; nothing here lays
/// that out, so the marker would silently go missing (`ListMarker.make`).
/// None of the 19 books in the corpus uses one (design §3, §4). Delete this
/// check, and the reason with it, once inside markers are drawn.
enum ListMarkerSupport {
    static func drawsInsideMarker(in node: ComputedStyleNode) -> Bool {
        let style = node.style
        // A hidden element draws nothing, and the tree holds none of its
        // descendants.
        if style.isHidden { return false }
        if style.isListItem, style.listStylePosition == .inside,
           ListMarkerText(type: style.listStyleType, ordinal: 1) != nil {
            return true
        }
        return node.children.contains {
            if case .element(let child) = $0 { return drawsInsideMarker(in: child) }
            return false
        }
    }
}

/// A marker on the line it sits on.
struct PlacedListMarker {
    let marker: ListMarker
    /// How far a float placed before the list item pushes the marker in from
    /// the item's border box start. Measured: a float left by earlier content
    /// moves the marker with the line it pushes; a float that is the item's own
    /// first child does not move it.
    let floatShift: CGFloat
    /// How far the marker's own central line sits from the vertical line's,
    /// towards the block end: its content area starts where the room it takes
    /// on the line starts (design §10). Zero horizontally, where the marker
    /// sits on the line's baseline.
    let blockShift: CGFloat
}

extension ListMarker {
    /// Where the marker is drawn, from the list item's border box start
    /// (`borderStart`, already moved by any float before the item) and the
    /// marker's baseline: the line's horizontally, the marker's own central
    /// line vertically. Neither text-indent, alignment, nor the item's padding,
    /// border or the margins inside it move a marker (measured). In vertical
    /// writing these are the canonical axes `LogicalFlow` turns at emission.
    enum Paint {
        /// The marker's line starts at `x`, on `baseline`.
        case text(x: CGFloat, width: CGFloat)
        case shape(rect: CGRect, isFilled: Bool, cornerRadius: CGFloat)
    }

    func paint(borderStart: CGFloat, baseline: CGFloat) -> Paint {
        switch content {
        case .text(_, _, let width):
            // The marker box, its suffix's space included, ends at the border box.
            return .text(x: borderStart - width, width: width)
        case .bullet(let bullet):
            // A square of side (A × 2/3 + 1) / 2, unrounded, its start
            // floor(A × 2/3) + 7 out from the border box and its top A / 2 into
            // the marker's content area: seven sizes of PingFang and Times New
            // Roman matched. That area starts A above the baseline, or
            // (A + D) / 2 before a vertical marker's central line (14-disc,
            // 14-disc-large).
            let side = (ascent * 2 / 3 + 1) / 2
            let contentStart = writingMode == .verticalRTL ? baseline - (ascent + descent) / 2 : baseline - ascent
            let shape = CGRect(x: borderStart - (floor(ascent * 2 / 3) + 7), y: contentStart + ascent / 2,
                               width: side, height: side)
            switch bullet {
            case .disc: return .shape(rect: shape, isFilled: true, cornerRadius: side / 2)
            case .square: return .shape(rect: shape, isFilled: true, cornerRadius: 0)
            case .circle:
                // A 1pt stroke centred on the disc's edge: the fill painter
                // strokes inside its rect, so the rect grows by half the stroke.
                let ring = shape.insetBy(dx: -0.5, dy: -0.5)
                return .shape(rect: ring, isFilled: false, cornerRadius: ring.width / 2)
            }
        }
    }
}
