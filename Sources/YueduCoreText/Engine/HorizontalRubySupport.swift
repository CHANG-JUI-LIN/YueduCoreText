import Foundation

enum RubyAlignment: Equatable {
    case center
    case unsupported(String)

    static func parse(_ raw: String) -> RubyAlignment {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return value == "center" ? .center : .unsupported(value)
    }
}

/// `ruby-position`, and WebKit's older `-webkit-ruby-position` keywords: `before` is `over`,
/// `after` `under`. In vertical-rl, over is the right of the base and under the left.
enum RubyPosition: Equatable {
    case over
    case under
    case unsupported(String)

    static func parse(_ raw: String) -> RubyPosition {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch value {
        case "over", "before": return .over
        case "under", "after": return .under
        default: return .unsupported(value)
        }
    }

    var isSupported: Bool { self == .over || self == .under }
}

enum RubyMerge: Equatable {
    case separate
    case unsupported(String)

    static func parse(_ raw: String) -> RubyMerge {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return value == "separate" ? .separate : .unsupported(value)
    }
}

struct HorizontalRubyStructure {
    let ruby: ComputedStyleNode
    let baseChildren: [StyleTreeChild]
    let annotation: ComputedStyleNode
    /// The element the base's text is styled by: an inner ruby for a nested one, else `ruby`.
    var baseNode: ComputedStyleNode? = nil
    /// A nested ruby's own `rt`, annotating the inner ruby: Aozora's readings on both sides of a
    /// word, or a note over a word with ruby.
    var outer: ComputedStyleNode? = nil
}

struct HorizontalRubyValidation {
    let structures: [HorizontalRubyStructure]
    let isSupported: Bool
}

/// Shared structural admission for horizontal and vertical-rl ruby. Both layout admission and the capability scanner consume this
/// predicate so parsing support cannot drift from geometry support.
enum HorizontalRubySupport {
    private static let structuralTags: Set<String> = [
        "ruby", "rt", "rp", "rtc", "br", "img", "svg",
    ]

    static func validate(
        _ root: ComputedStyleNode,
        writingMode: ReaderWritingMode = .horizontal
    ) -> HorizontalRubyValidation {
        let hasRubyMarkup = containsTag(
            root,
            names: ["ruby", "rt", "rp", "rb", "rtc"],
            excludingRoot: false
        )
        guard hasRubyMarkup else {
            return HorizontalRubyValidation(structures: [], isSupported: true)
        }

        var structures: [HorizontalRubyStructure] = []
        var valid = true
        walk(root, insideRuby: false, structures: &structures, valid: &valid)
        return HorizontalRubyValidation(structures: structures, isSupported: valid)
    }

    static func rubyNodes(in root: ComputedStyleNode) -> [ComputedStyleNode] {
        validate(root).structures.map(\.ruby)
    }

    static func structure(for node: ComputedStyleNode) -> HorizontalRubyStructure? {
        guard let pairs = structures(for: node), pairs.count == 1 else { return nil }
        return pairs.first
    }

    /// Group and paired ruby use the same atomic unit in either writing mode.
    /// Each direct rt consumes the preceding base; rb is an optional wrapper. A ruby whose base is
    /// one ruby with one rt is one unit with two annotations (`nestedStructure`). WebKit lays out
    /// no `rtc` (iOS 27.2: its text sits on the line, as base text), so neither does this.
    static func structures(for node: ComputedStyleNode) -> [HorizontalRubyStructure]? {
        guard isSupportedRuby(node), !containsTag(node, names: ["rtc"], excludingRoot: true) else { return nil }
        if let nested = nestedStructure(for: node) { return [nested] }
        guard !containsTag(node, names: ["ruby"], excludingRoot: true) else { return nil }
        var pending: [StyleTreeChild] = []
        var pairs: [HorizontalRubyStructure] = []
        for child in node.children {
            if child.elementNode?.tag == "rp" { continue }
            if let rt = child.elementNode, rt.tag == "rt" {
                guard isSupportedAnnotation(rt), containsVisibleBase(pending), supportedInlineBase(pending)
                else { return nil }
                pairs.append(HorizontalRubyStructure(ruby: node, baseChildren: pending, annotation: rt))
                pending.removeAll()
            } else {
                pending.append(child)
            }
        }
        guard !pairs.isEmpty, !containsVisibleBase(pending) else { return nil }
        return pairs
    }

    /// `<ruby><ruby>base<rt>inner</rt></ruby><rt>outer</rt></ruby>`: the inner annotation next to
    /// the base on its own side, the outer one on its side, beyond the inner one when the sides are
    /// the same (measured, WKWebView iOS 27.2, the app's S001m and S001n fixtures).
    private static func nestedStructure(for node: ComputedStyleNode) -> HorizontalRubyStructure? {
        let children = node.children.filter { child in
            if case .text(let text) = child { return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            return child.elementNode?.tag != "rp"
        }
        guard children.count == 2, let inner = children[0].elementNode, inner.tag == "ruby",
              let rt = children[1].elementNode, rt.tag == "rt", isSupportedAnnotation(rt),
              isSupportedRuby(inner), !containsTag(inner, names: ["ruby", "rtc"], excludingRoot: true),
              let pairs = structures(for: inner), pairs.count == 1 else { return nil }
        return HorizontalRubyStructure(ruby: node, baseChildren: pairs[0].baseChildren, annotation: pairs[0].annotation,
                                       baseNode: inner, outer: rt)
    }

    private static func isSupportedRuby(_ node: ComputedStyleNode) -> Bool {
        node.tag == "ruby" && node.style.display == .inline && node.style.rubyAlign == .center
            && node.style.rubyPosition.isSupported && node.style.rubyMerge == .separate
    }

    private static func isSupportedAnnotation(_ rt: ComputedStyleNode) -> Bool {
        rt.style.display == .inline && !rt.style.isFloated && rt.style.rubyPosition.isSupported
            && containsVisibleBase(rt.children) && supportedInlineBase(rt.children)
    }

    private static func walk(
        _ node: ComputedStyleNode,
        insideRuby: Bool,
        structures: inout [HorizontalRubyStructure],
        valid: inout Bool
    ) {
        guard valid else { return }
        if node.tag == "ruby" {
            guard !insideRuby, let accepted = Self.structures(for: node) else {
                valid = false
                return
            }
            structures.append(contentsOf: accepted)
            return
        }
        if ["rt", "rp", "rb", "rtc"].contains(node.tag) {
            valid = false
            return
        }
        for child in node.children {
            guard case .element(let element) = child else { continue }
            walk(element, insideRuby: false, structures: &structures, valid: &valid)
        }
    }

    private static func containsVisibleBase(_ children: [StyleTreeChild]) -> Bool {
        children.contains { child in
            switch child {
            case .text(let text):
                return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            case .element(let element):
                return containsVisibleBase(element.children)
            }
        }
    }

    private static func supportedInlineBase(_ children: [StyleTreeChild]) -> Bool {
        children.allSatisfy { child in
            switch child {
            case .text:
                return true
            case .element(let element):
                guard element.style.display == .inline,
                      !element.style.isFloated,
                      !structuralTags.contains(element.tag) else {
                    return false
                }
                return supportedInlineBase(element.children)
            }
        }
    }

    private static func containsTag(
        _ node: ComputedStyleNode,
        names: Set<String>,
        excludingRoot: Bool
    ) -> Bool {
        if !excludingRoot, names.contains(node.tag) { return true }
        for child in node.children {
            guard case .element(let element) = child else { continue }
            if names.contains(element.tag)
                || containsTag(element, names: names, excludingRoot: true) {
                return true
            }
        }
        return false
    }
}

private extension StyleTreeChild {
    var elementNode: ComputedStyleNode? {
        guard case .element(let node) = self else { return nil }
        return node
    }
}

struct RubyInlinePiece {
    let text: String
    let style: ComputedStyle
    let sourceRange: NSRange
    let nodeID: Int
    let linkTarget: String?
}

struct RubyAnnotationPiece {
    let text: String
    let style: ComputedStyle
    let nodeID: Int
    let linkTarget: String?
}

struct RubyAnnotation {
    let pieces: [RubyAnnotationPiece]

    var text: String {
        pieces.map(\.text).joined()
    }
}

/// Semantic Ruby content before shaping. The base remains in the chapter's
/// source coordinate space; the annotation deliberately has no independent
/// source range and maps back to the complete base range later.
struct RubyInlineUnit {
    let base: [RubyInlinePiece]
    let annotation: RubyAnnotation
    let sourceRange: NSRange
    let nodeID: Int
    let linkTarget: String?
    let alignment: RubyAlignment
    /// `annotation`'s side.
    let position: RubyPosition
    /// A nested ruby's outer annotation, and its side.
    var outer: RubyAnnotation? = nil
    var outerPosition: RubyPosition = .over

    /// The annotation spoken as the base's reading: the one over the base (right of it), the
    /// inner one when both or neither are. A left reading is often a gloss (刺, テフダ).
    var reading: RubyAnnotation {
        if let outer, position == .under, outerPosition == .over { return outer }
        return annotation
    }
}
