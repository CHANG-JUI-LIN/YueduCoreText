import CoreText
import UIKit

/// A content-owned rendering surface. Its identity never includes a scroll
/// offset, cell index, viewport height, or CTLine allocation address.
public struct BrowserPaintFragment {
    public struct ID: Hashable {
        public let node: Int
        public let sourceOffset: Int
        public let kind: Int
        public let occurrence: Int
        public let part: Int
    }
    public let id: ID
    /// Order in the source display list, independent of the query rectangle.
    public let paintOrder: Int
    /// The visible surface; image/background subdivisions have a sampling bleed.
    public let documentRect: CGRect
    public let renderingRect: CGRect
    public let displayList: DisplayList
    public let textPaintPhase: TextPaintPhase
}

extension BrowserScrollDocument {
    /// Produces immutable, local-coordinate paint fragments from existing layout.
    /// Text is grouped by shaped baseline. A very long paragraph can therefore
    /// enter the viewport incrementally without allocating a paragraph-size bitmap.
    /// CSS fills/images retain display-list order. Text decorations precede ALL
    /// glyphs in their original text batch, including overlapping decorations.
    public func paintFragments(
        in demand: CGRect, scale: CGFloat, maximumSurfaceHeight: CGFloat = 1024,
        textDecorationBounds: ((CTLine, NSAttributedString) -> CGRect)? = nil
    ) -> [BrowserPaintFragment] {
        let scale = max(1, scale)
        let limit = max(1, maximumSurfaceHeight)
        struct Key: Hashable { let node: Int; let offset: Int; let kind: Int }
        var occurrences: [Key: Int] = [:]
        var result: [BrowserPaintFragment] = []
        var pending: [[DisplayTextItem]] = []
        var nextPaintOrder = 0

        func emit(_ items: [DisplayItem], bounds: CGRect, node: Int, offset: Int,
                  kind: Int, phase: TextPaintPhase) {
            let paintOrder = nextPaintOrder
            nextPaintOrder += 1
            let key = Key(node: node, offset: offset, kind: kind)
            let occurrence = occurrences[key, default: 0]
            occurrences[key] = occurrence + 1
            guard !bounds.isNull, !bounds.isEmpty, bounds.minY.isFinite, bounds.maxY.isFinite else { return }
            let minX = floor(bounds.minX * scale) / scale
            let minY = floor(bounds.minY * scale) / scale
            let rect = CGRect(x: minX, y: minY,
                width: ceil(bounds.maxX * scale) / scale - minX,
                height: ceil(bounds.maxY * scale) / scale - minY)
            guard rect.intersects(demand) else { return }
            let count = max(1, Int(ceil(rect.height / limit)))
            let first = max(0, Int(floor((demand.minY - rect.minY) / limit)))
            let last = min(count - 1, Int(floor((demand.maxY - rect.minY) / limit)))
            guard first <= last else { return }
            let list = DisplayList(items: items)
            for part in first...last {
                let y = rect.minY + CGFloat(part) * limit
                let piece = CGRect(x: rect.minX, y: y, width: rect.width, height: min(limit, rect.maxY - y))
                let rendering = count > 1 ? piece.insetBy(dx: 0, dy: -1) : piece
                result.append(BrowserPaintFragment(
                    id: .init(node: node, sourceOffset: offset, kind: kind, occurrence: occurrence, part: part),
                    paintOrder: paintOrder,
                    documentRect: piece, renderingRect: rendering,
                    displayList: list.items(in: rendering, filteringItems: false), textPaintPhase: phase))
            }
        }

        func flushText() {
            guard !pending.isEmpty else { return }
            // Resolve a run's immutable drawing resource once, before exposing
            // either surface. This preserves justification, ruby and rule styles.
            let lines = pending.map { line in line.map { value in
                var value = value
                if value.preparedDrawing == nil { value.preparedDrawing = TextDrawingResources(value) }
                return value
            } }
            for phase in [TextPaintPhase.decorations, .glyphs] {
                for line in lines {
                    guard let first = line.first else { continue }
                    var bounds = CGRect.null
                    for item in line {
                        guard let resource = item.preparedDrawing else { continue }
                        let ink: CGRect
                        if phase == .decorations {
                            ink = textDecorationBounds?(resource.line, resource.attributed) ?? .null
                        } else {
                            ink = TextLinePaintBounds.conservativeBounds(for: resource.line)
                        }
                        if !ink.isNull, !ink.isEmpty {
                            bounds = bounds.union(CGRect(x: item.rect.minX + ink.minX,
                                y: item.baselineY - ink.maxY, width: ink.width, height: ink.height))
                        }
                        if phase == .glyphs { bounds = bounds.union(item.rect.rawValue) }
                    }
                    // One pixel includes the antialiased ink at a fractional edge.
                    if !bounds.isNull { bounds = bounds.insetBy(dx: -1 / scale, dy: -1 / scale) }
                    emit(line.map(DisplayItem.text), bounds: bounds, node: first.nodeID,
                        offset: first.sourceRange.location, kind: phase == .decorations ? 0 : 1, phase: phase)
                }
            }
            pending.removeAll(keepingCapacity: true)
        }

        for item in displayList.items {
            switch item {
            case .text(let text):
                if let last = pending.last?.last, last.baselineY == text.baselineY {
                    pending[pending.count - 1].append(text)
                } else { pending.append([text]) }
            case .fill(let fill):
                flushText()
                emit([item], bounds: fill.rect.rawValue, node: fill.nodeID, offset: 0, kind: 2, phase: .all)
            case .image(let image):
                flushText()
                emit([item], bounds: image.rect.rawValue, node: image.nodeID,
                    offset: image.sourceRange.location, kind: 3, phase: .all)
            }
        }
        flushText()
        return result
    }
}
