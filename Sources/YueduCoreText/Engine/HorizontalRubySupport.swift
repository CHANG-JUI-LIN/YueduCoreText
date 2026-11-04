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
    /// The base, which for a nested ruby holds its inner rubies, each one base and one `rt`
    /// (`HorizontalRubySupport.innerRuby`), beside text or inside inline elements.
    let baseChildren: [StyleTreeChild]
    let annotation: ComputedStyleNode
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
    /// Each direct rt consumes the preceding base; rb is an optional wrapper. A ruby whose base
    /// holds rubies is one unit with an annotation over each inner ruby and its own over the whole
    /// base (`nestedStructure`). WebKit lays out no `rtc` (iOS 27.2: its text sits on the line, as
    /// base text), so neither does this.
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

    /// `<ruby><ruby>base<rt>inner</rt></ruby><rt>outer</rt></ruby>`, and a ruby whose base holds
    /// rubies beside other text, `<ruby>辞<ruby>義<rt>ママ</rt></ruby><rt>じぎ</rt></ruby>`, the
    /// inner ones perhaps inside an inline element: each inner annotation over its own base, the
    /// outer one over the whole base, beyond the inner ones on a side they share (measured, WKWebView
    /// iOS 27.2, the app's S001m and S001n fixtures; iOS 26.5, S001o and S001p).
    private static func nestedStructure(for node: ComputedStyleNode) -> HorizontalRubyStructure? {
        let children = node.children.filter { $0.elementNode?.tag != "rp" }
        guard let rt = children.last?.elementNode, rt.tag == "rt", isSupportedAnnotation(rt) else { return nil }
        let base = Array(children.dropLast())
        var inner = 0
        guard containsVisibleBase(base), nestedBase(base, rubies: &inner), inner > 0 else { return nil }
        return HorizontalRubyStructure(ruby: node, baseChildren: base, annotation: rt)
    }

    /// Whether `children` are text, inline elements and inner rubies only, counting the rubies.
    private static func nestedBase(_ children: [StyleTreeChild], rubies: inout Int) -> Bool {
        children.allSatisfy { child in
            guard case .element(let element) = child else { return true }
            if element.tag == "ruby" {
                rubies += 1
                return innerRuby(element) != nil
            }
            guard element.style.display == .inline, !element.style.isFloated,
                  !structuralTags.contains(element.tag) else { return false }
            return nestedBase(element.children, rubies: &rubies)
        }
    }

    /// A ruby inside another's base: one base and one `rt`, with no ruby or `rtc` of its own.
    static func innerRuby(_ node: ComputedStyleNode) -> HorizontalRubyStructure? {
        guard isSupportedRuby(node), !containsTag(node, names: ["ruby", "rtc"], excludingRoot: true),
              let pairs = structures(for: node), pairs.count == 1 else { return nil }
        return pairs[0]
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

/// A ruby inside another's base: the base pieces it covers, and its annotation and side.
struct RubyInnerAnnotation {
    let pieces: Range<Int>
    let annotation: RubyAnnotation
    let position: RubyPosition
}

/// Semantic Ruby content before shaping. The base remains in the chapter's
/// source coordinate space; the annotation deliberately has no independent
/// source range and maps back to the complete base range later.
struct RubyInlineUnit {
    let base: [RubyInlinePiece]
    /// The ruby's own annotation, over the whole base.
    let annotation: RubyAnnotation
    let sourceRange: NSRange
    let nodeID: Int
    let linkTarget: String?
    let alignment: RubyAlignment
    /// `annotation`'s side.
    let position: RubyPosition
    /// The rubies inside the base, in order: Aozora's readings on both sides of a word (one inner
    /// ruby over the whole base), or a note on part of a word with ruby.
    var inner: [RubyInnerAnnotation] = []

    /// The annotation spoken as the base's reading: of a word with readings on both sides, the
    /// one over the base (right of it), the inner one when both or neither are; a left reading is
    /// often a gloss (刺, テフダ). The ruby's own when an inner ruby covers only part of the base.
    var reading: RubyAnnotation {
        guard inner.count == 1, let only = inner.first, only.pieces == base.indices else { return annotation }
        return only.position == .under && position == .over ? annotation : only.annotation
    }
}
