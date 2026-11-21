import CoreGraphics
import UIKit

/// The collapsing border model (CSS 2.1 §17.6.2), for a table whose
/// `border-collapse` is `collapse`.
///
/// Every edge of the cell grid has one border: the winner among the borders of
/// the boxes that meet there — the two cells, their rows, their row groups and,
/// on the table's outside, the table. The border is centred on the grid line,
/// so each cell holds half of it for layout. `resolve` picks the winners and
/// writes them onto the boxes:
/// - a cell's style gets half of each of its four edges as its border widths;
/// - a cell's `collapsedBorders` names the edges it paints, whole: its top and
///   left, its bottom in the table's last row, its right at the end of its row.
///   Every edge is painted once, by one cell;
/// - the table, rows and row groups paint no border; the table's own border
///   widths become half of the widest edge along each of its sides, as §17.6.2
///   sizes the table, and it has no padding.
///
/// Row spans are outside the table subset (`TableSupport`), so every row is a
/// plain sequence of cells and their column spans.
enum CollapsedTableBorders {

    /// The four borders a box declares.
    struct Sides: Equatable {
        var top = BorderEdge.zero, right = BorderEdge.zero, bottom = BorderEdge.zero, left = BorderEdge.zero

        init() {}

        init(_ style: ComputedStyle) {
            func edge(_ width: CGFloat, _ borderStyle: BorderStyle, _ color: UIColor?) -> BorderEdge {
                BorderEdge(width: width, color: color ?? style.color ?? .black, style: width > 0 ? borderStyle : .none)
            }
            top = edge(style.borderTopWidth, style.borderTopStyle, style.borderTopColor)
            right = edge(style.borderRightWidth, style.borderRightStyle, style.borderRightColor)
            bottom = edge(style.borderBottomWidth, style.borderBottomStyle, style.borderBottomColor)
            left = edge(style.borderLeftWidth, style.borderLeftStyle, style.borderLeftColor)
        }
    }

    /// What a box of a collapsed table paints for borders.
    struct Painted: Equatable {
        var top = BorderEdge.zero, right = BorderEdge.zero, bottom = BorderEdge.zero, left = BorderEdge.zero
    }

    /// Where a border comes from. Between borders of one width and style, the
    /// one from the more specific box wins (§17.6.2.1).
    private enum Origin: Int { case table, rowGroup, row, cell }

    private struct Candidate {
        let edge: BorderEdge
        let origin: Origin
    }

    /// §17.6.2.1: a wider border wins; then the more prominent style; then the
    /// box closer to the content; then the one listed first, which callers make
    /// the one further up or to the left.
    private static func winner(_ candidates: [Candidate]) -> BorderEdge {
        func prominence(_ style: BorderStyle) -> Int {
            switch style {
            case .none: return 0
            case .inset: return 1
            case .outset: return 2
            case .dotted: return 3
            case .dashed: return 4
            case .solid: return 5
            }
        }
        var best: Candidate?
        for candidate in candidates where candidate.edge.isVisible {
            guard let current = best else { best = candidate; continue }
            let lhs = (candidate.edge.width, prominence(candidate.edge.style), candidate.origin.rawValue)
            let rhs = (current.edge.width, prominence(current.edge.style), current.origin.rawValue)
            if lhs > rhs { best = candidate }
        }
        return best?.edge ?? .zero
    }

    private struct Cell {
        let box: BlockBox
        let sides: Sides
        let columns: Range<Int>
    }

    private struct Row {
        let box: BlockBox
        let group: BlockBox?
        let isFirstInGroup: Bool
        let isLastInGroup: Bool
        var cells: [Cell]
    }

    /// Resolves every edge of the grid in `groups` (the table's row groups and
    /// bare rows, in layout order) and returns the table's style for layout.
    static func resolve(table: ComputedStyle, groups: [BlockBox]) -> ComputedStyle {
        var rows: [Row] = []
        for group in groups {
            let bare = group.style.display == .tableRow
            let members = bare ? [group] : group.children
            for (index, row) in members.enumerated() {
                var cursor = 0
                var cells: [Cell] = []
                for cell in row.children {
                    let span = max(1, cell.tableColspan)
                    cells.append(Cell(box: cell, sides: Sides(cell.style), columns: cursor..<(cursor + span)))
                    cursor += span
                }
                rows.append(Row(box: row, group: bare ? nil : group, isFirstInGroup: index == 0,
                                isLastInGroup: index == members.count - 1, cells: cells))
            }
        }
        let tableSides = Sides(table)
        var outer = (top: CGFloat(0), right: CGFloat(0), bottom: CGFloat(0), left: CGFloat(0))

        func own(_ box: BlockBox?) -> Sides { box?.tableOwnBorders ?? Sides() }
        func neighbours(in row: Row?, over columns: Range<Int>) -> [Cell] {
            row?.cells.filter { $0.columns.overlaps(columns) } ?? []
        }

        for (rowIndex, row) in rows.enumerated() {
            let above = rowIndex > 0 ? rows[rowIndex - 1] : nil
            let below = rowIndex + 1 < rows.count ? rows[rowIndex + 1] : nil
            for (cellIndex, cell) in row.cells.enumerated() {
                // Top: what is above first, so it wins a tie.
                var top: [Candidate] = neighbours(in: above, over: cell.columns).map { Candidate(edge: $0.sides.bottom, origin: .cell) }
                top.append(Candidate(edge: cell.sides.top, origin: .cell))
                if let above {
                    top.append(Candidate(edge: own(above.box).bottom, origin: .row))
                    if above.isLastInGroup { top.append(Candidate(edge: own(above.group).bottom, origin: .rowGroup)) }
                }
                top.append(Candidate(edge: own(row.box).top, origin: .row))
                if row.isFirstInGroup { top.append(Candidate(edge: own(row.group).top, origin: .rowGroup)) }
                if above == nil { top.append(Candidate(edge: tableSides.top, origin: .table)) }

                var bottom: [Candidate] = [Candidate(edge: cell.sides.bottom, origin: .cell)]
                bottom += neighbours(in: below, over: cell.columns).map { Candidate(edge: $0.sides.top, origin: .cell) }
                bottom.append(Candidate(edge: own(row.box).bottom, origin: .row))
                if row.isLastInGroup { bottom.append(Candidate(edge: own(row.group).bottom, origin: .rowGroup)) }
                if let below {
                    bottom.append(Candidate(edge: own(below.box).top, origin: .row))
                    if below.isFirstInGroup { bottom.append(Candidate(edge: own(below.group).top, origin: .rowGroup)) }
                } else {
                    bottom.append(Candidate(edge: tableSides.bottom, origin: .table))
                }

                let isFirst = cellIndex == 0, isLast = cellIndex == row.cells.count - 1
                var left: [Candidate] = []
                if !isFirst { left.append(Candidate(edge: row.cells[cellIndex - 1].sides.right, origin: .cell)) }
                left.append(Candidate(edge: cell.sides.left, origin: .cell))
                if isFirst {
                    left.append(Candidate(edge: own(row.box).left, origin: .row))
                    left.append(Candidate(edge: own(row.group).left, origin: .rowGroup))
                    left.append(Candidate(edge: tableSides.left, origin: .table))
                }

                var right: [Candidate] = [Candidate(edge: cell.sides.right, origin: .cell)]
                if !isLast { right.append(Candidate(edge: row.cells[cellIndex + 1].sides.left, origin: .cell)) }
                if isLast {
                    right.append(Candidate(edge: own(row.box).right, origin: .row))
                    right.append(Candidate(edge: own(row.group).right, origin: .rowGroup))
                    right.append(Candidate(edge: tableSides.right, origin: .table))
                }

                let edges = Sides.resolved(top: winner(top), right: winner(right), bottom: winner(bottom), left: winner(left))
                apply(edges, to: cell.box, paintsBottom: below == nil, paintsRight: isLast)
                if above == nil { outer.top = max(outer.top, edges.top.width) }
                if below == nil { outer.bottom = max(outer.bottom, edges.bottom.width) }
                if isFirst { outer.left = max(outer.left, edges.left.width) }
                if isLast { outer.right = max(outer.right, edges.right.width) }
            }
        }

        var style = table
        style.borderTopWidth = outer.top / 2
        style.borderRightWidth = outer.right / 2
        style.borderBottomWidth = outer.bottom / 2
        style.borderLeftWidth = outer.left / 2
        style.paddingTop = .px(0); style.paddingRight = .px(0)
        style.paddingBottom = .px(0); style.paddingLeft = .px(0)
        // Cells are set edge to edge: the model has no border-spacing.
        style.borderSpacingHorizontal = .px(0)
        style.borderSpacingVertical = .px(0)
        return style
    }

    private static func apply(_ edges: Sides, to cell: BlockBox, paintsBottom: Bool, paintsRight: Bool) {
        cell.style.borderTopWidth = edges.top.width / 2
        cell.style.borderRightWidth = edges.right.width / 2
        cell.style.borderBottomWidth = edges.bottom.width / 2
        cell.style.borderLeftWidth = edges.left.width / 2
        func centred(_ edge: BorderEdge) -> BorderEdge {
            var edge = edge
            edge.isCentredOnEdge = true
            return edge
        }
        cell.collapsedBorders = Painted(
            top: centred(edges.top),
            right: paintsRight ? centred(edges.right) : .zero,
            bottom: paintsBottom ? centred(edges.bottom) : .zero,
            left: centred(edges.left))
    }
}

private extension CollapsedTableBorders.Sides {
    static func resolved(top: BorderEdge, right: BorderEdge, bottom: BorderEdge, left: BorderEdge) -> Self {
        var sides = Self()
        sides.top = top; sides.right = right; sides.bottom = bottom; sides.left = left
        return sides
    }
}
