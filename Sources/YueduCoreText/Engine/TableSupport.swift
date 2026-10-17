import Foundation

/// Admission boundary for the table subset (CSS 2.1 §17, separated borders
/// only). Anything BoxTreeBuilder/TableLayout cannot honor exactly keeps the
/// chapter on the webview path. The validator mirrors the structure buildTable
/// consumes: table → (row groups | rows) → cells, horizontal only, no nesting,
/// no rowspan, no foster-parented text.
enum TableSupport {

    /// Raw `display` values that compute into the layout. `inline-table` and
    /// the column/caption roles are rejected by the scanner from the raw
    /// declaration, before the cascade ever runs.
    static let supportedDisplayValues: Set<String> = [
        "table", "table-row-group", "table-header-group",
        "table-footer-group", "table-row", "table-cell",
    ]

    static func validate(root: ComputedStyleNode, writingMode: ReaderWritingMode) -> [UnsupportedFeature] {
        var rejected = false
        walk(root, insideTable: false, writingMode: writingMode, rejected: &rejected)
        return rejected ? [.table] : []
    }

    private static func walk(
        _ node: ComputedStyleNode,
        insideTable: Bool,
        writingMode: ReaderWritingMode,
        rejected: inout Bool
    ) {
        guard !rejected else { return }
        let display = node.style.display

        if display == .table {
            guard !insideTable, writingMode == .horizontal,
                node.style.borderCollapse == .separate
            else {
                rejected = true
                return
            }
            for child in node.children {
                if !acceptable(child, roles: [.tableRowGroup, .tableHeaderGroup, .tableFooterGroup, .tableRow]) {
                    rejected = true
                    return
                }
            }
        } else if display == .tableRow {
            guard insideTable else {
                rejected = true
                return
            }
            for child in node.children where !acceptable(child, roles: [.tableCell]) {
                rejected = true
                return
            }
        } else if display == .tableRowGroup || display == .tableHeaderGroup || display == .tableFooterGroup {
            guard insideTable else {
                rejected = true
                return
            }
            for child in node.children where !acceptable(child, roles: [.tableRow]) {
                rejected = true
                return
            }
        } else if display == .tableCell {
            guard insideTable else {
                rejected = true
                return
            }
            // rowspan spans rows; colspan: 0 spans to the table's end. Neither
            // is in the subset. Unparseable values compute to 1 in HTML.
            if let span = integerAttribute("rowspan", of: node), span > 1 {
                rejected = true
                return
            }
            if let span = integerAttribute("colspan", of: node), span < 1 {
                rejected = true
                return
            }
        }

        let entersTable = display == .table
        for child in node.children {
            guard case .element(let element) = child else { continue }
            walk(element, insideTable: insideTable || entersTable, writingMode: writingMode, rejected: &rejected)
        }
    }

    /// A table-structure child is either whitespace or an element playing one
    /// of the expected roles. Anything else would be foster-parented by a
    /// browser — text lifted out of the table — which the box tree never does.
    private static func acceptable(_ child: StyleTreeChild, roles: Set<CSSDisplay>) -> Bool {
        switch child {
        case .text(let raw):
            return InlineLayout.collapseText(raw, mode: .normal).allSatisfy { $0 == " " || $0 == "\t" }
        case .element(let element):
            return roles.contains(element.style.display)
        }
    }

    private static func integerAttribute(_ name: String, of node: ComputedStyleNode) -> Int? {
        guard let raw = node.semanticElement?.attribute(name) else { return nil }
        return Int(raw.trimmingCharacters(in: .whitespaces))
    }
}
