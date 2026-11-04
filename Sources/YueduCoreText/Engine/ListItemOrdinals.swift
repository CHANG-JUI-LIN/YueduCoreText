import Foundation

/// The number each list item counts as: the HTML Standard's "ordinal value"
/// (§4.4.8). It runs over the finished computed-style tree because only an
/// element whose computed `display` is `list-item` is an item. An `li` set to
/// `display: block` takes no number, a hidden one is not in the tree, and an
/// `li` wrapped in a `div` still counts in its list, as WebKit numbers them.
enum ListItemOrdinals {
    /// The elements that own the list items under them.
    static let ownerTags: Set<String> = ["ol", "ul", "menu"]

    static func assign(in root: ComputedStyleNode) {
        // An item's owner is its nearest `ol`/`ul`/`menu` ancestor, else its
        // parent. Owners and their items are collected in tree order.
        var owners: [ComputedStyleNode] = []
        var items: [ObjectIdentifier: [ComputedStyleNode]] = [:]
        func walk(_ node: ComputedStyleNode, nearestOwner: ComputedStyleNode?) {
            for child in node.children {
                guard case .element(let element) = child else { continue }
                // The item joins its owner before it may become an owner itself,
                // so an `ol` that is a list item counts in the list around it.
                if element.style.isListItem {
                    let owner = nearestOwner ?? node
                    let key = ObjectIdentifier(owner)
                    if items[key] == nil { owners.append(owner) }
                    items[key, default: []].append(element)
                }
                walk(element, nearestOwner: ownerTags.contains(element.tag) ? element : nearestOwner)
            }
        }
        walk(root, nearestOwner: nil)
        for owner in owners {
            number(items[ObjectIdentifier(owner)] ?? [], ownedBy: owner)
        }
    }

    private static func number(_ items: [ComputedStyleNode], ownedBy owner: ComputedStyleNode) {
        let isOrderedList = owner.tag == "ol"
        let isReversed = isOrderedList && owner.semanticElement?.attribute("reversed") != nil
        var numbering: Int
        if isOrderedList, let start = owner.semanticElement?.attribute("start").flatMap(parseInteger) {
            numbering = start
        } else if isReversed {
            numbering = items.count
        } else {
            numbering = 1
        }
        for item in items {
            if item.tag == "li", let value = item.semanticElement?.attribute("value").flatMap(parseInteger) {
                numbering = value
            }
            item.listItemOrdinal = numbering
            numbering += isReversed ? -1 : 1
        }
    }

    /// The HTML "rules for parsing integers": leading ASCII whitespace, an
    /// optional sign, then at least one ASCII digit; whatever follows the digits
    /// is ignored (`"5abc"` is 5). nil is a parse error, which leaves the
    /// attribute without effect. WebKit parses into a 32-bit int, so a value
    /// outside that range is an error too.
    static func parseInteger(_ raw: String) -> Int? {
        var scalars = raw.unicodeScalars[...]
        while let first = scalars.first, [0x09, 0x0A, 0x0C, 0x0D, 0x20].contains(first.value) {
            scalars.removeFirst()
        }
        var sign = 1
        if scalars.first == "-" {
            sign = -1
            scalars.removeFirst()
        } else if scalars.first == "+" {
            scalars.removeFirst()
        }
        var magnitude = 0
        var digits = 0
        while let first = scalars.first, ("0"..."9").contains(first) {
            magnitude = magnitude * 10 + Int(first.value - 0x30)
            guard magnitude <= Int(Int32.max) + 1 else { return nil }
            digits += 1
            scalars.removeFirst()
        }
        guard digits > 0 else { return nil }
        let value = sign * magnitude
        return (Int(Int32.min)...Int(Int32.max)).contains(value) ? value : nil
    }
}
