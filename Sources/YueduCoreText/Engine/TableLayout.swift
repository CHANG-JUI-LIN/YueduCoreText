import CoreGraphics
import UIKit
import YueduCoreTextTypography

/// Automatic table layout for the separated-borders model (CSS 2.1 §17.5).
///
/// Column max-content widths are measured by BoxTreeBuilder (it owns the font
/// resolver); this stage distributes the table's final content width into the
/// columns, lays each cell out as an ordinary block container at its column
/// width, sizes rows to their tallest cell, and aligns cell content with the
/// row's `vertical-align` chain (cell → row → row group, defaulting to the
/// row's UA `middle`).
///
/// Rows and cells are ordinary block children, so pagination splits between
/// them through the normal PageWalker flow.
enum TableLayout {

    @discardableResult
    static func layOut(
        table box: BlockBox,
        containerWidth: CGFloat,
        rootFontSize: CGFloat,
        sourceText: String = "",
        fontResolver: (([String], Int, Bool, CGFloat) -> UIFont?)? = nil,
        cjkTypographyStyle: CJKTypographyStyle? = nil,
        fragmentHeight: CGFloat? = nil,
        viewportHeight: CGFloat? = nil,
        viewportWidth: CGFloat? = nil,
        viewport: BrowserViewportLayoutState? = nil
    ) -> CGFloat {
        let sides = BlockLayout.resolveSides(
            box, containerWidth: containerWidth, rootFontSize: rootFontSize, writingMode: .horizontal
        )
        box.margins = sides.margins
        box.padding = sides.padding
        box.borders = sides.borders
        box.contentSize.width = sides.contentWidth
        box.frame = ParentLocalRect(rawValue: CGRect(x: 0, y: 0, width: sides.borderBoxWidth, height: 0))

        let rows = flattenedRows(of: box)
        let bases = box.tableColumnMaxContent ?? []
        guard !rows.isEmpty, !bases.isEmpty else {
            box.contentSize.height = 0
            box.frame = ParentLocalRect(
                rawValue: CGRect(
                    x: 0, y: 0, width: sides.borderBoxWidth,
                    height: box.borders.vertical + box.padding.vertical
                ))
            return 0
        }

        let spacing = borderSpacing(of: box.style, rootFontSize: rootFontSize)
        let columns = distribute(
            bases: bases, spacingH: spacing.horizontal, contentWidth: box.contentSize.width
        )

        var cursorY = spacing.vertical
        for group in box.children {
            let isBareRow = group.style.display == .tableRow
            let groupRows = isBareRow ? [group] : group.children
            var localY: CGFloat = 0
            for row in groupRows {
                var cells: [(box: BlockBox, x: CGFloat, width: CGFloat, contentHeight: CGFloat)] = []
                var x = spacing.horizontal
                var columnCursor = 0
                for cell in row.children {
                    let span = min(max(cell.tableColspan, 1), columns.count - columnCursor)
                    let width =
                        (columnCursor..<(columnCursor + span)).reduce(0) { $0 + columns[$1] }
                        + spacing.horizontal * CGFloat(span - 1)
                    let contentHeight = BlockLayout.layOut(
                        root: cell,
                        containerWidth: width,
                        rootFontSize: rootFontSize,
                        writingMode: .horizontal,
                        floatContext: nil,
                        sourceText: sourceText,
                        fontResolver: fontResolver,
                        cjkTypographyStyle: cjkTypographyStyle,
                        fragmentHeight: fragmentHeight,
                        viewportHeight: viewportHeight, viewportWidth: viewportWidth, viewport: viewport
                    )
                    cells.append((cell, x, width, contentHeight))
                    x += width + spacing.horizontal
                    columnCursor += span
                }

                // Cell and row heights are minima (CSS 2.1 §17.5.3).
                var rowHeight =
                    CSSLengthResolver.resolve(
                        row.style.height, emBase: row.style.fontSize, remBase: rootFontSize, percentBase: 0,
                        viewportHeight: viewportHeight, viewportWidth: viewportWidth
                    ) ?? 0
                for cell in cells {
                    let specified =
                        CSSLengthResolver.resolve(
                            cell.box.style.height, emBase: cell.box.style.fontSize, remBase: rootFontSize,
                            percentBase: 0, viewportHeight: viewportHeight, viewportWidth: viewportWidth
                        ) ?? 0
                    rowHeight = max(
                        rowHeight,
                        cell.box.borders.vertical + cell.box.padding.vertical + cell.contentHeight,
                        cell.box.borders.vertical + cell.box.padding.vertical + specified
                    )
                }

                for cell in cells {
                    let area = max(0, rowHeight - cell.box.borders.vertical - cell.box.padding.vertical)
                    let slack = area - cell.contentHeight
                    let shift: CGFloat
                    switch alignment(of: cell.box, row: row) {
                    case .middle: shift = max(0, slack / 2)
                    case .bottom: shift = max(0, slack)
                    default: shift = 0
                    }
                    if shift > 0.001 {
                        cell.box.style.paddingTop = .px(cell.box.padding.top + shift)
                        BlockLayout.layOut(
                            root: cell.box,
                            containerWidth: cell.width,
                            rootFontSize: rootFontSize,
                            writingMode: .horizontal,
                            floatContext: nil,
                            sourceText: sourceText,
                            fontResolver: fontResolver,
                            cjkTypographyStyle: cjkTypographyStyle,
                            fragmentHeight: fragmentHeight,
                            viewportHeight: viewportHeight, viewportWidth: viewportWidth, viewport: viewport
                        )
                    }
                    cell.box.contentSize.height = area
                    cell.box.logicalInlineOrigin = cell.x
                    cell.box.logicalBlockOrigin = 0
                    cell.box.frame = ParentLocalRect(
                        rawValue: CGRect(
                            x: cell.x, y: 0, width: cell.width, height: rowHeight
                        ))
                }
                // Row frames are relative to their GROUP's content box; a bare
                // row's group IS the table's content box.
                let rowY = isBareRow ? cursorY : localY
                row.contentSize = CGSize(width: box.contentSize.width, height: rowHeight)
                row.logicalInlineOrigin = 0
                row.logicalBlockOrigin = rowY
                row.frame = ParentLocalRect(
                    rawValue: CGRect(
                        x: 0, y: rowY, width: box.contentSize.width, height: rowHeight
                    ))
                localY += rowHeight + spacing.vertical
            }

            // Group frames span their rows so a styled group background paints
            // over the whole band. Bare rows carry their own background.
            let groupHeight = max(0, localY - spacing.vertical)
            if !isBareRow {
                group.contentSize = CGSize(width: box.contentSize.width, height: groupHeight)
                group.logicalInlineOrigin = 0
                group.logicalBlockOrigin = cursorY
                group.frame = ParentLocalRect(
                    rawValue: CGRect(
                        x: 0, y: cursorY, width: box.contentSize.width, height: groupHeight
                    ))
            }
            cursorY += groupHeight + spacing.vertical
        }

        box.contentSize.height = max(0, cursorY)
        if let used = CSSLengthResolver.resolve(
            box.style.height, emBase: box.style.fontSize, remBase: rootFontSize, percentBase: 0,
            viewportHeight: viewportHeight, viewportWidth: viewportWidth
        ) {
            box.contentSize.height = max(box.contentSize.height, used)
        }
        box.frame = ParentLocalRect(
            rawValue: CGRect(
                x: 0, y: 0, width: sides.borderBoxWidth,
                height: box.borders.vertical + box.padding.vertical + box.contentSize.height
            ))
        return box.contentSize.height
    }

    /// Rows in paint order: header groups, body groups and bare rows, footer
    /// groups (build-time order is already reordered per CSS 2.1 §17.2.1).
    private static func flattenedRows(of table: BlockBox) -> [BlockBox] {
        var rows: [BlockBox] = []
        for group in table.children {
            if group.style.display == .tableRow {
                rows.append(group)
            } else {
                rows.append(contentsOf: group.children)
            }
        }
        return rows
    }

    /// Grows or shrinks the measured columns into the table's final content
    /// width, proportionally to their max-content bases.
    private static func distribute(bases: [CGFloat], spacingH: CGFloat, contentWidth: CGFloat) -> [CGFloat] {
        let baseSum = bases.reduce(0, +)
        let slack = contentWidth - spacingH * CGFloat(bases.count + 1) - baseSum
        guard abs(slack) > 0.001, baseSum > 0 else { return bases }
        return bases.map { max(0, $0 + slack * $0 / baseSum) }
    }

    /// `vertical-align` is not inherited, so the UA chain (rows middle, cells
    /// `inherit`) is resolved structurally: the cell's own top/middle/bottom,
    /// else the row's, else middle. An authored `baseline` on a cell therefore
    /// renders as middle — first-baseline row alignment is outside the subset.
    /// `super`/`sub` act as `baseline` on a cell (CSS 2.1 §17.5.3).
    private static func alignment(of cell: BlockBox, row: BlockBox) -> CSSVerticalAlign {
        for align in [cell.style.verticalAlign, row.style.verticalAlign] {
            switch align {
            case .top, .middle, .bottom: return align
            case .baseline, .sup, .sub: continue
            }
        }
        return .middle
    }

    /// Resolved border-spacing; em resolves against the table's own font size.
    /// Percentages are invalid for this property and compute to zero here.
    static func borderSpacing(
        of style: ComputedStyle,
        rootFontSize: CGFloat
    ) -> (horizontal: CGFloat, vertical: CGFloat) {
        func resolve(_ length: CSSLength?) -> CGFloat {
            guard let length else { return 0 }
            return CSSLengthResolver.resolve(
                length, emBase: style.fontSize, remBase: rootFontSize, percentBase: 0
            ).map { max(0, $0) } ?? 0
        }
        return (resolve(style.borderSpacingHorizontal), resolve(style.borderSpacingVertical))
    }
}
