import Foundation
import SwiftSoup
import UIKit
import YueduCoreTextTypography

/// One node of the computed-style tree. DOM identity is a copied value snapshot;
/// frontend-owned SwiftSoup/Lexbor nodes never cross this boundary.
final class ComputedStyleNode {
    let tag: String
    let semanticElement: HTMLDOMElementSnapshot?
    /// Source-compatibility spelling for diagnostics being migrated during the
    /// frontend cutover. Its type is still the neutral value snapshot.
    var element: HTMLDOMElementSnapshot? { semanticElement }
    let style: ComputedStyle
    let children: [StyleTreeChild]
    /// Stable identity assigned by `ComputedStyleTreeBuilder` (document order).
    /// Fragments carry it so a rendered character can be traced back to its DOM node.
    let nodeID: Int
    /// Resolved href from the nearest ancestor `<a>` (nil when not inside a link).
    let linkTarget: String?
    /// This element's own `id` attribute (anchor target), nil when absent.
    let anchorID: String?
    /// The number this list item counts as (HTML ordinal value), set by
    /// `ListItemOrdinals.assign` once `buildTree` has the whole tree; nil for
    /// anything that is not a list item. Not inherited. The stages after the
    /// cascade rebuild nodes (`LogicalFlow.styleTree` rebuilds every node of a
    /// vertical chapter), so every copy of a node must pass it on.
    var listItemOrdinal: Int?
    init(
        tag: String,
        semanticElement: HTMLDOMElementSnapshot?,
        style: ComputedStyle,
        children: [StyleTreeChild],
        nodeID: Int,
        linkTarget: String?,
        anchorID: String?,
        listItemOrdinal: Int? = nil
    ) {
        self.tag = tag
        self.semanticElement = semanticElement
        self.style = style
        self.children = children
        self.nodeID = nodeID
        self.linkTarget = linkTarget
        self.anchorID = anchorID
        self.listItemOrdinal = listItemOrdinal
    }

    convenience init(
        tag: String,
        element: HTMLDOMElementSnapshot?,
        style: ComputedStyle,
        children: [StyleTreeChild],
        nodeID: Int,
        linkTarget: String?,
        anchorID: String?
    ) {
        self.init(
            tag: tag,
            semanticElement: element,
            style: style,
            children: children,
            nodeID: nodeID,
            linkTarget: linkTarget,
            anchorID: anchorID
        )
    }
}

enum StyleTreeChild {
    case element(ComputedStyleNode)
    case text(String)
}

/// Reader-provided configuration that feeds computed styles: the root font size
/// (rem base), the fallback text/background colors, and the config font family
/// list. Layout stages read `renderWidth`/`renderHeight`/`contentInsets`.
public struct BrowserLayoutConfig {
    public var renderWidth: CGFloat = 320     // body containing-block width (reader content width)
    public var renderHeight: CGFloat = 480    // page content height before page margins apply
    public var rootFontSize: CGFloat = 17
    public var fontFamilies: [String] = []
    public var textColor: UIColor = .black
    public var backgroundColor: UIColor = .white
    public var contentInsets: UIEdgeInsets = .zero   // page margins from reader settings
    public var lineHeight: CGFloat? = nil     // reader default multiplier (author CSS takes precedence)
    public var lineSpacing: CGFloat = 0
    public var paragraphSpacing: CGFloat = 0
    public var letterSpacing: CGFloat = 0
    public var isBold: Bool = false
    /// Reader default; an authored text-align declaration still wins in the cascade.
    public var defaultTextAlignment: NSTextAlignment = .natural
    /// Optional consumer text attributes, applied before shaping without changing UTF-16 content.
    public var textTransform: ((NSMutableAttributedString) -> Void)? = nil
    /// Opt-in local diagnostic sink. Contains CSS/geometry metadata, never chapter text.
    public var onDiagnostic: ((CSSFrontendDiagnostic) -> Void)? = nil
    /// CSS font-family resolver (embedded @font-face families). nil → UIFont(name:).
    public var fontResolver: (([String], Int, Bool, CGFloat) -> UIFont?)?
    /// Explicit document writing mode. Vertical-rl currently accepts normal-flow
    /// text and the shared ruby subset; capability checks report exclusions.
    public var writingMode: ReaderWritingMode = .horizontal
    /// How CJK text is set: where punctuation sits and how much of it squeezes,
    /// and which fonts draw Han and kana. The host decides it from the script of
    /// the text; nil leaves CJK text to the fonts' own defaults.
    public var cjkTypographyStyle: CJKTypographyStyle? = nil
    /// 底部對齊 (legado `textBottomJustify`): a page that ends because its next
    /// text line no longer fits spreads the space left below its last line evenly
    /// over its line gaps, so the last line sits on the content bottom. Paged
    /// horizontal layout only; scroll layout and vertical writing ignore it.
    public var bottomJustify: Bool = false
    public init(
        renderWidth: CGFloat = 320,
        renderHeight: CGFloat = 480,
        rootFontSize: CGFloat = 17,
        fontFamilies: [String] = [],
        textColor: UIColor = .black,
        backgroundColor: UIColor = .white,
        contentInsets: UIEdgeInsets = .zero,
        lineHeight: CGFloat? = nil,
        lineSpacing: CGFloat = 0,
        paragraphSpacing: CGFloat = 0,
        letterSpacing: CGFloat = 0,
        isBold: Bool = false,
        defaultTextAlignment: NSTextAlignment = .natural,
        textTransform: ((NSMutableAttributedString) -> Void)? = nil,
        fontResolver: (([String], Int, Bool, CGFloat) -> UIFont?)? = nil,
        writingMode: ReaderWritingMode = .horizontal,
        cjkTypographyStyle: CJKTypographyStyle? = nil,
        bottomJustify: Bool = false,
        onDiagnostic: ((CSSFrontendDiagnostic) -> Void)? = nil
    ) {
        self.renderWidth = renderWidth
        self.renderHeight = renderHeight
        self.rootFontSize = rootFontSize
        self.fontFamilies = fontFamilies
        self.textColor = textColor
        self.backgroundColor = backgroundColor
        self.contentInsets = contentInsets
        self.lineHeight = lineHeight
        self.lineSpacing = lineSpacing
        self.paragraphSpacing = paragraphSpacing
        self.letterSpacing = letterSpacing
        self.isBold = isBold
        self.defaultTextAlignment = defaultTextAlignment
        self.textTransform = textTransform
        self.fontResolver = fontResolver
        self.writingMode = writingMode
        self.cjkTypographyStyle = cjkTypographyStyle
        self.bottomJustify = bottomJustify
        self.onDiagnostic = onDiagnostic
    }

    /// Whether the paged walker applies 底部對齊. The walker runs in logical
    /// coordinates, so the writing mode is decided here.
    var pagesBottomJustify: Bool {
        bottomJustify && writingMode == .horizontal
    }
}

/// Turns the DOM `<body>` subtree + CSS rule list into a `ComputedStyleNode`
/// tree. Reruns the full cascade per element, mirroring the proven order in
/// `HTMLAttributedStringBuilder.resolvedStyle`:
/// base(inheritance+UA) → normal author rules → normal inline → important
/// author rules → important inline. Selector matching reuses the existing
/// `CSSParser`/`CSSSelector` so behavior stays identical to the legacy renderer.
final class ComputedStyleTreeBuilder {

    private let rules: [CSSRule]
    private let firstLetterRules: [CSSRule]
    private var rootFontSize: CGFloat
    private let textColor: UIColor
    private let backgroundColor: UIColor
    private let configFontFamilies: [String]
    private let readerLineHeightMultiple: CGFloat?
    private let readerConfig: BrowserLayoutConfig
    private var nextNodeID = 1

    /// Admission reads which rules matched at least one element. The cascade already
    /// matches every rule against every element it styles, so it records the hits
    /// here instead of the scanner matching the whole document a second time.
    /// Elements the cascade never styles (the `<head>` subtree, descendants of a
    /// hidden element) are not in `styledElements`; admission matches those itself.
    private(set) var matchedRuleIndices: Set<Int> = []
    private(set) var styledElements: Set<ObjectIdentifier> = []

    init(rules: [CSSRule], config: BrowserLayoutConfig, firstLetterRules: [CSSRule] = []) {
        self.firstLetterRules = firstLetterRules
        self.readerConfig = config
        self.rules = rules
        self.rootFontSize = config.rootFontSize
        self.textColor = config.textColor
        self.backgroundColor = config.backgroundColor
        self.configFontFamilies = config.fontFamilies
        self.readerLineHeightMultiple = config.lineHeight
    }

    func buildTree(body: Element) -> ComputedStyleNode {
        // The root body element goes through the SAME cascade as every other
        // element (author rules like `body { margin: 0 }` must apply).
        var defaultParent = ComputedStyle(
            fontSize: rootFontSize,
            fontFamilies: configFontFamilies,
            color: textColor,
            backgroundColor: backgroundColor,
            textAlign: readerConfig.defaultTextAlignment
        )
        // 行距. `BrowserLayoutConfig.lineHeight` was set from the reader
        // setting and then read by nobody, so the slider moved and the page did
        // not. Seeded as an inherited MULTIPLIER, not an absolute length: that
        // is what an unitless CSS `line-height` means, so a heading at a larger
        // font size scales with it, and any author `line-height` still wins on
        // the element that declares it.
        if let readerLineHeightMultiple, readerLineHeightMultiple > 0 {
            defaultParent.lineHeightMultiplier = readerLineHeightMultiple
            defaultParent.lineHeight = max(0, rootFontSize * readerLineHeightMultiple)
        }
        defaultParent.configLineSpacing = max(0, readerConfig.lineSpacing)
        defaultParent.configParagraphSpacing = max(0, readerConfig.paragraphSpacing)
        defaultParent.configLetterSpacing = readerConfig.letterSpacing
        defaultParent.configBold = readerConfig.isBold
        if let html = body.parent(), html.tagName().lowercased() == "html" {
            defaultParent = resolvedStyle(for: html, semanticElement: SwiftSoupHTMLSemanticAdapter.snapshot(html), parent: defaultParent, parentElement: html.parent())
            rootFontSize = defaultParent.fontSize
        }
        let bodySemantic = SwiftSoupHTMLSemanticAdapter.snapshot(body)
        let bodyStyle = resolvedStyle(
            for: body,
            semanticElement: bodySemantic,
            parent: defaultParent,
            parentElement: body.parent()
        )
        let root = ComputedStyleNode(
            tag: "body", semanticElement: bodySemantic, style: bodyStyle,
            children: children(of: body, parentStyle: bodyStyle, parentElement: body, inheritedLink: nil),
            nodeID: nextNodeID,
            linkTarget: nil,
            anchorID: linkAnchorID(of: bodySemantic)
        )
        nextNodeID += 1
        ListItemOrdinals.assign(in: root)
        return root
    }

    // MARK: - Children

    private func children(
        of element: Element,
        parentStyle: ComputedStyle,
        parentElement: Element,
        inheritedLink: String?
    ) -> [StyleTreeChild] {
        var result: [StyleTreeChild] = []
        for node in element.getChildNodes() {
            if let text = node as? TextNode {
                result.append(.text(text.getWholeText()))
            } else if let child = node as? Element {
                let semanticElement = SwiftSoupHTMLSemanticAdapter.snapshot(child)
                let style = resolvedStyle(
                    for: child,
                    semanticElement: semanticElement,
                    parent: parentStyle,
                    parentElement: element
                )
                if style.isHidden { continue }
                let childLink: String?
                if child.tagName().lowercased() == "a",
                   let href = semanticElement.attribute("href"),
                   !href.isEmpty {
                    childLink = href
                } else {
                    childLink = inheritedLink
                }
                let childNode = ComputedStyleNode(
                    tag: child.tagName().lowercased(),
                    semanticElement: semanticElement,
                    style: style,
                    children: children(of: child, parentStyle: style, parentElement: child, inheritedLink: childLink),
                    nodeID: nextNodeID,
                    linkTarget: childLink,
                    anchorID: linkAnchorID(of: semanticElement)
                )
                nextNodeID += 1
                if let report = readerConfig.onDiagnostic {
                    report(CSSFrontendDiagnostic(stage:.style,stylesheet:nil,semanticPath:Self.diagnosticPath(child),property:nil,
                        message:"layoutNode=\(childNode.nodeID)"))
                }
                result.append(.element(childNode))
            }
        }
        return applyingFirstLetter(to: result, element: element, style: parentStyle)
    }

    /// Materialize the pseudo-element before box construction. The source
    /// characters remain ordinary text; the existing float/inline pipeline
    /// owns layout, drawing and geometry for the initial just like other boxes.
    private func applyingFirstLetter(to children: [StyleTreeChild], element: Element, style: ComputedStyle) -> [StyleTreeChild] {
        guard style.display == .block else { return children }
        let matched = firstLetterRules.filter { !$0.isDarkMedia && $0.selector.matches(element: element, parent: element.parent()) }
            .sorted { $0.specificity == $1.specificity ? $0.order < $1.order : $0.specificity < $1.specificity }
        guard !matched.isEmpty else { return children }
        func text(_ children: [StyleTreeChild]) -> String {
            var result = ""
            for child in children {
                switch child {
                case .text(let value): result += value
                case .element(let node):
                    // An inline-block is atomic: its text is not on this line.
                    if [.block, .inlineBlock].contains(node.style.display) || node.style.isFloated
                        || ["img", "br", "ruby"].contains(node.tag) { return result }
                    result += text(node.children)
                }
            }
            return result
        }
        let content = text(children)
        var count = 0
        var hasLetter = false
        for character in content {
            let punctuation = character.unicodeScalars.allSatisfy { CharacterSet.punctuationCharacters.contains($0) }
            if !hasLetter && character.isWhitespace { count += String(character).utf16.count; continue }
            if hasLetter && !punctuation { break }
            count += String(character).utf16.count
            if !punctuation { hasLetter = true }
        }
        guard hasLetter else { return children }
        func styled(_ original: ComputedStyle) -> ComputedStyle {
            var value = original.inherited(from: original)
            let ctx = ApplyContext(parent: original, rootFontSize: rootFontSize, textColor: textColor, backgroundColor: backgroundColor, configFontFamilies: configFontFamilies, writingMode: readerConfig.writingMode)
            for rule in matched { cascadeApply(rule.declarations, order: rule.declarationOrder, to: &value, ctx: ctx) }
            for rule in matched { cascadeApply(rule.importantDeclarations, order: rule.declarationOrder, to: &value, ctx: ctx) }
            value.finalizeLineHeight(rootFontSize: rootFontSize)
            value.finalizeLetterSpacing(rootFontSize: rootFontSize)
            return value
        }
        func split(_ children: [StyleTreeChild], remaining: inout Int) -> ([StyleTreeChild], [StyleTreeChild]) {
            var prefix: [StyleTreeChild] = []; var suffix: [StyleTreeChild] = []
            for child in children {
                guard remaining > 0 else { suffix.append(child); continue }
                switch child {
                case .text(let value):
                    let ns = value as NSString; let length = min(remaining, ns.length)
                    prefix.append(.text(ns.substring(to: length)))
                    if length < ns.length { suffix.append(.text(ns.substring(from: length))) }
                    remaining -= length
                case .element(let node):
                    let (a, b) = split(node.children, remaining: &remaining)
                    var inlineStyle = styled(node.style)
                    inlineStyle.cssFloat = .none; inlineStyle.display = .inline
                    inlineStyle.marginTop = .px(0); inlineStyle.marginBottom = .px(0)
                    inlineStyle.marginLeft = .px(0); inlineStyle.marginRight = .px(0)
                    if !a.isEmpty {
                        prefix.append(.element(ComputedStyleNode(tag: node.tag, semanticElement: node.semanticElement, style: inlineStyle, children: a, nodeID: node.nodeID, linkTarget: node.linkTarget, anchorID: node.anchorID)))
                    }
                    if !b.isEmpty {
                        suffix.append(.element(ComputedStyleNode(tag: node.tag, semanticElement: node.semanticElement, style: node.style, children: b, nodeID: nextNodeID, linkTarget: node.linkTarget, anchorID: a.isEmpty ? node.anchorID : nil)))
                        nextNodeID += 1
                    }
                }
            }
            return (prefix, suffix)
        }
        let (prefix, suffix) = split(children, remaining: &count)
        var initialStyle = styled(style)
        initialStyle.textIndent = .initial
        initialStyle.display = initialStyle.isFloated ? .block : .inline
        let initial = ComputedStyleNode(tag: "::first-letter", semanticElement: nil, style: initialStyle, children: prefix, nodeID: nextNodeID, linkTarget: nil, anchorID: nil)
        nextNodeID += 1
        return [.element(initial)] + suffix
    }

    private func linkAnchorID(of element: HTMLDOMElementSnapshot) -> String? {
        let value = element.attribute("id") ?? ""
        return value.isEmpty ? nil : value
    }

    // MARK: - Link anchors (Phase 3A)

    /// nodeID → the `<a href>` that owns it, for the anchor AND every node
    /// inside it.
    ///
    /// A separate walk over the FINISHED tree rather than bookkeeping during the
    /// build, because `nextNodeID` is consumed by the recursion into a node's
    /// children before the node itself is numbered: while an `<a>`'s subtree is
    /// being built its own nodeID does not exist yet. Renumbering to pre-order
    /// would change `nodeCount` (the root's id doubles as the node total) and
    /// every fragment's nodeID with it; one extra walk costs nothing by
    /// comparison.
    ///
    /// Only nodes under a link are recorded, so this map stays tiny for ordinary
    /// prose.
    static func collectLinkAnchors(_ root: ComputedStyleNode) -> [Int: LinkAnchorInfo] {
        var map: [Int: LinkAnchorInfo] = [:]
        walkLinkAnchors(root, inherited: nil, into: &map)
        return map
    }

    private static func walkLinkAnchors(
        _ node: ComputedStyleNode,
        inherited: LinkAnchorInfo?,
        into map: inout [Int: LinkAnchorInfo]
    ) {
        var current = inherited
        if let element = node.semanticElement, node.tag == "a",
           let href = element.attribute("href"), !href.isEmpty {
            current = LinkAnchorInfo(
                anchorNodeID: node.nodeID,
                semantic: element.linkSemantic
            )
        }
        if let current {
            map[node.nodeID] = current
        }
        for child in node.children {
            guard case .element(let childNode) = child else { continue }
            walkLinkAnchors(childNode, inherited: current, into: &map)
        }
    }

    // MARK: - Cascade for one element

    private func resolvedStyle(
        for element: Element,
        semanticElement: HTMLDOMElementSnapshot,
        parent: ComputedStyle,
        parentElement: Element?
    ) -> ComputedStyle {
        var style = parent.inherited(from: parent)
        let tag = element.tagName().lowercased()
        let ua = UserAgentStyle.basis(for: tag)
        style = style.applyingUA(ua)
        if tag == "rt" {
            style.fontSize = parent.fontSize * 0.5
        }
        // html.css: `dialog { display: none }`, `dialog[open] { display: block }`.
        // Hidden after the cascade only if no author rule shows it.
        let closedDialog = tag == "dialog" && element.hasAttr("open") == false
        if tag == "dialog" { style.display = closedDialog ? .none : .block }
        let ctx = ApplyContext(parent: parent, rootFontSize: rootFontSize, textColor: textColor, backgroundColor: backgroundColor, configFontFamilies: configFontFamilies, writingMode: readerConfig.writingMode)
        var nestedInList = false
        if UserAgentStyle.nestedListMarginAncestors.contains(tag) {
            var listAncestors = 0
            var cursor = element.parent()
            while let ancestor = cursor {
                let name = ancestor.tagName().lowercased()
                if UserAgentStyle.listContainerTags.contains(name) { listAncestors += 1 }
                if UserAgentStyle.nestedListMarginAncestors.contains(name) { nestedInList = true }
                cursor = ancestor.parent()
            }
            if let type = UserAgentStyle.listStyleType(for: tag, listAncestors: listAncestors) {
                style.listStyleType = type
            }
        }
        for (property, value) in UserAgentStyle.declarations(for: tag, nestedInList: nestedInList) {
            ComputedStylePropertyApplier.apply(key: property, value: value, to: &style, ctx: ctx)
        }

        // HTML presentational hints form their own cascade origin between UA
        // defaults and author CSS. Keep normalization outside the CSS frontend
        // so a future Lexbor DOM adapter can feed the same typed declarations.
        Self.applyPresentationalHints(
            HTMLPresentationalHintExtractor.extract(
                from: semanticElement.htmlSemanticElement
            ),
            to: &style,
            rootFontSize: rootFontSize
        )

        let matchedIndices = rules.indices.filter { rules[$0].selector.matches(element: element, parent: parentElement) }
        matchedRuleIndices.formUnion(matchedIndices)
        styledElements.insert(ObjectIdentifier(element))
        let matched = matchedIndices.map { rules[$0] }
            .sorted { lhs, rhs in
                if lhs.specificity == rhs.specificity { return lhs.order < rhs.order }
                return lhs.specificity < rhs.specificity
            }

        for rule in matched {
            cascadeApply(rule.declarations, order: rule.declarationOrder, to: &style, ctx: ctx)
        }

        let inlineDecl = CSSParser.parseDeclarationBlock((try? element.attr("style")) ?? "")
        cascadeApply(inlineDecl.normal, order: inlineDecl.order, to: &style, ctx: ctx)

        for rule in matched {
            cascadeApply(rule.importantDeclarations, order: rule.declarationOrder, to: &style, ctx: ctx)
        }
        cascadeApply(inlineDecl.important, order: inlineDecl.order, to: &style, ctx: ctx)

        if let language = semanticElement.attribute("lang") ?? semanticElement.attribute("xml:lang") {
            style.language = language.isEmpty ? nil : language
        }
        if tag == "q" { style.quoteDepth = parent.quoteDepth + 1 }
        if semanticElement.attribute("hidden") != nil { style.isHidden = true }
        if closedDialog, style.display == .none { style.isHidden = true }
        if case .length(let length) = style.textIndent {
            switch length {
            case .em, .rem, .pt:
                if let pixels = CSSLengthResolver.resolve(length, emBase: style.fontSize, remBase: rootFontSize, percentBase: 0) {
                    style.textIndent = .length(.px(pixels))
                }
            default: break
            }
        }
        style.finalizeLineHeight(rootFontSize: rootFontSize)
        style.finalizeLetterSpacing(rootFontSize: rootFontSize)
        style.finalizeBorderLengths(rootFontSize: rootFontSize)
        // vertical-align shifts inline-level boxes only (CSS 2.1 §10.8.1): a
        // block container or table cell never raises its own text, and a cell
        // reads the keyword as its alignment instead.
        if style.display != .inline, style.display != .inlineBlock {
            style.verticalAlignOffset = 0
        }
        style.textDecorationsInEffect = style.decorationsInEffect(inheriting: parent.textDecorationsInEffect)
        if let report = readerConfig.onDiagnostic {
            let path = Self.diagnosticPath(element)
            for rule in matched {
                report(CSSFrontendDiagnostic(stage:.selector,stylesheet:rule.sourceStylesheet,semanticPath:path,property:nil,
                    message:"matched selector=\(rule.sourceSelector) order=\(rule.order) specificity=\(rule.specificity) normal=\(rule.declarations.sorted { $0.key < $1.key }) important=\(rule.importantDeclarations.sorted { $0.key < $1.key })"))
            }
            let declarations = matched.map { "order=\($0.order) specificity=\($0.specificity) normal=\($0.declarations.sorted { $0.key < $1.key }) important=\($0.importantDeclarations.sorted { $0.key < $1.key })" }.joined(separator:"; ")
            report(CSSFrontendDiagnostic(stage:.style,stylesheet:nil,semanticPath:path,property:nil,
                message:"\(declarations); inline=\(inlineDecl.merged.sorted { $0.key < $1.key }); computed font=\(style.fontFamilies) size=\(style.fontSize) lineHeight=\(String(describing:style.lineHeight)) indent=\(style.textIndent) align=\(style.textAlign.rawValue) hyphens=\(style.hyphens) lang=\(style.language ?? "unknown")"))
        }
        return style
    }

    private static func diagnosticPath(_ element: Element) -> String {
        var components: [String] = []
        var cursor: Element? = element
        while let current = cursor {
            let siblings = current.parent()?.getChildNodes().compactMap { $0 as? Element } ?? []
            let index = (siblings.firstIndex { $0 == current } ?? 0) + 1
            components.insert("\(current.tagName())[\(index)]", at:0)
            cursor = current.parent()
        }
        return components.joined(separator:"/")
    }

    static func applyPresentationalHints(
        _ hints: [HTMLPresentationalHint],
        to style: inout ComputedStyle,
        rootFontSize: CGFloat
    ) {
        func length(_ dimension: HTMLPresentationalDimension) -> CSSLength {
            switch dimension {
            case .pixels(let value): return .px(value)
            case .percentage(let fraction): return .percent(fraction)
            }
        }
        func uiColor(_ color: CSSRGB) -> UIColor {
            UIColor(red: CGFloat(color.red) / 255, green: CGFloat(color.green) / 255,
                    blue: CGFloat(color.blue) / 255, alpha: 1)
        }
        for hint in hints {
            switch (hint.property, hint.value) {
            case (.width, .dimension(let dimension)):
                style.width = length(dimension)
            case (.height, .dimension(let dimension)):
                style.height = length(dimension)
            case (.listStyleType, .listStyleType(let type)):
                style.listStyleType = type == .none ? .none : .counterStyle(type.rawValue)
            case (.color, .color(let color)):
                style.color = uiColor(color)
            case (.backgroundColor, .color(let color)):
                style.backgroundColor = uiColor(color)
            case (.borderColor, .color(let color)):
                let c = uiColor(color)
                style.borderTopColor = c; style.borderRightColor = c
                style.borderBottomColor = c; style.borderLeftColor = c
            case (.borderStyle, .solidBorderStyle):
                style.borderTopStyle = .solid; style.borderRightStyle = .solid
                style.borderBottomStyle = .solid; style.borderLeftStyle = .solid
            case (.borderBottomWidth, .dimension(let dimension)):
                style.pendingBorderBottomWidth = length(dimension)
            case (.marginLeft, .dimension(let dimension)):
                style.marginLeft = length(dimension)
            case (.marginLeft, .auto):
                style.marginLeft = .auto
            case (.marginRight, .dimension(let dimension)):
                style.marginRight = length(dimension)
            case (.marginRight, .auto):
                style.marginRight = .auto
            case (.fontSize, .fontSize(let keyword)):
                // An absolute keyword; the parent size is never read.
                if let size = ComputedStylePropertyApplier.resolveFontSize(
                    keyword.rawValue, parentSize: style.fontSize, root: rootFontSize) {
                    style.fontSize = size
                }
            case (.fontFamily, .fontFamily(let list)):
                style.fontFamilies = ComputedStylePropertyApplier.fontFamilyList(list.lowercased())
            default:
                // The extractor pairs every property with its own kind of value.
                continue
            }
        }
    }
}

fileprivate struct ApplyContext {
    let parent: ComputedStyle
    let rootFontSize: CGFloat
    let textColor: UIColor
    let backgroundColor: UIColor
    let configFontFamilies: [String]
    /// Logical properties map to physical sides for this writing mode.
    let writingMode: ReaderWritingMode
}

extension ComputedStyle {
    /// Applies UA defaults onto an inherited style: UA sets non-inherited box
    /// props. Font sizes are relative and go through the cascade
    /// (`UserAgentStyle.declarations`), except `rt`'s half size, which
    /// `resolvedStyle` sets itself.
    mutating func applyingUA(_ ua: ComputedStyle) -> ComputedStyle {
        display = ua.display
        isListItem = ua.isListItem
        isHidden = ua.isHidden
        width = ua.width
        height = ua.height
        marginTop = ua.marginTop
        marginRight = ua.marginRight
        marginBottom = ua.marginBottom
        marginLeft = ua.marginLeft
        paddingTop = ua.paddingTop
        paddingRight = ua.paddingRight
        paddingBottom = ua.paddingBottom
        paddingLeft = ua.paddingLeft
        // Non-inherited table roles: the UA gives rows middle alignment and
        // tables the separated-borders defaults.
        verticalAlign = ua.verticalAlign
        borderCollapse = ua.borderCollapse
        borderSpacingHorizontal = ua.borderSpacingHorizontal
        borderSpacingVertical = ua.borderSpacingVertical
        // `white-space` is inherited; a UA default (only `<pre>`) overrides it.
        if ua.whiteSpace != .normal { whiteSpace = ua.whiteSpace }
        if ua.fontWeight != 400 { fontWeight = ua.fontWeight }
        if ua.isItalic { isItalic = true }
        return self
    }
}

private extension ComputedStyleTreeBuilder {
    /// Applies a declaration block. `order` carries the SOURCE order of the
    /// property names; iterating `declarations` directly would apply them in
    /// Swift's per-process randomized dictionary order, which made the cascade
    /// non-deterministic across runs.
    func cascadeApply(
        _ declarations: [String: String],
        order: [String],
        to style: inout ComputedStyle,
        ctx: ApplyContext
    ) {
        // `line-height` percentages resolve against the element's COMPUTED
        // font-size, and `font-size` in the same block is always computed
        // first per CSS. Dictionary iteration order is not guaranteed, so
        // apply font-size explicitly before everything else — otherwise
        // line-height flips between runs (27.1pt vs 33.3pt on 145%).
        if let fontSize = declarations["font-size"] {
            ComputedStylePropertyApplier.apply(key: "font-size", value: fontSize, to: &style, ctx: ctx)
        }
        for key in order where key != "font-size" {
            guard let value = declarations[key] else { continue }
            ComputedStylePropertyApplier.apply(key: key, value: value, to: &style, ctx: ctx)
        }
    }
}

enum ComputedStylePropertyApplier {
    fileprivate static func apply(key: String, value raw: String, to style: inout ComputedStyle, ctx: ApplyContext) {
        // CSS keywords are case-insensitive, so the folded value drives every
        // keyword comparison below. A `url()` payload is NOT a keyword — it is a
        // path, and paths are case-sensitive. Folding it produced
        // `../images/x.jpg` for an authored `../Images/x.jpg` (and
        // `reader-book://id/oebps/…` for a stylesheet URL already rewritten by
        // `EPUBStyleResolver.rewriteResourceURLs`), so the source the style tree
        // asked the image loader for could never equal the key the prefetcher
        // stored: every authored body background-image silently resolved to nil.
        // `preserved` therefore feeds anything that carries a URL.
        let preserved = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = preserved.lowercased()
        guard !value.isEmpty else { return }
        if let longhands = logicalShorthandLonghands(key: key, value: preserved) {
            for (longhand, longhandValue) in longhands {
                apply(key: longhand, value: longhandValue, to: &style, ctx: ctx)
            }
            return
        }
        if let physical = LogicalGeometry.physicalProperty(forLogical: key, mode: ctx.writingMode) {
            apply(key: physical, value: raw, to: &style, ctx: ctx)
            return
        }
        switch key {
        case "display":
            let display: CSSDisplay
            switch value {
            case "none": display = .none
            // A list item is a block that also generates a marker.
            case "block", "list-item": display = .block
            case "inline": display = .inline
            case "inline-block": display = .inlineBlock
            case "table": display = .table
            case "table-row-group": display = .tableRowGroup
            case "table-header-group": display = .tableHeaderGroup
            case "table-footer-group": display = .tableFooterGroup
            case "table-row": display = .tableRow
            case "table-cell": display = .tableCell
            // `display` is not inherited: `unset` is its initial value, inline.
            case "initial", "unset": display = .inline
            case "inherit":
                style.display = ctx.parent.display
                if ctx.parent.display == .none { style.isHidden = true }
                style.isListItem = ctx.parent.isListItem
                return
            // inline-table and the column/caption roles stay unparsed: the
            // admission scanner rejects them from the raw declaration. An
            // unparsed value is dropped and changes nothing, list item included.
            default: return
            }
            style.display = display
            if display == .none { style.isHidden = true }
            style.isListItem = value == "list-item"
        case "list-style-type":
            switch value {
            case "inherit", "unset": style.listStyleType = ctx.parent.listStyleType
            case "initial": style.listStyleType = .initial
            default: if let type = CSSListStyleType.parse(value) { style.listStyleType = type }
            }
        case "list-style-position":
            switch value {
            case "inherit", "unset": style.listStylePosition = ctx.parent.listStylePosition
            case "initial": style.listStylePosition = .outside
            default: if let position = CSSListStylePosition.parse(value) { style.listStylePosition = position }
            }
        case "list-style":
            switch value {
            case "inherit", "unset":
                style.listStyleType = ctx.parent.listStyleType
                style.listStylePosition = ctx.parent.listStylePosition
            case "initial":
                style.listStyleType = .initial
                style.listStylePosition = .outside
            default:
                guard let parsed = CSSListStyleType.parseShorthand(value) else { break }
                style.listStyleType = parsed.type
                style.listStylePosition = parsed.position
            }
        case "color":
            // On `color` itself `currentColor` is the inherited colour.
            if value == "currentcolor" { style.color = ctx.parent.color }
            else if let c = parseColor(value) { style.color = c }
        case "background-color":
            if let c = parseColor(value) { style.backgroundColor = c }
        case "float":
            // Whitelist only, via the shared parser. An unrecognised value
            // (`center`, `inline-start`, a typo) is an invalid declaration: it
            // is DROPPED, leaving the initial `none`. Never map an unknown
            // token onto a side.
            if let parsed = CSSFloat.parse(value) { style.cssFloat = parsed }
        case "clear":
            switch value {
            case "none": style.cssClear = .none
            case "left": style.cssClear = .left
            case "right": style.cssClear = .right
            case "both": style.cssClear = .both
            default: break
            }
        case "vertical-align":
            // super/sub shift the baseline; top/middle/bottom align table
            // cells. Length values degrade to baseline instead of rejecting
            // the chapter. The shift matches WebKit
            // (InlineLineBoxVerticalAligner): the PARENT box's font-size / 3 + 1
            // up (sub: / 5 + 1 down), from the parent's own shifted baseline
            // (measured: a `sup` in a `sup` sits 6.67 + 5.72 up).
            let parentShift = ctx.parent.verticalAlignOffset
            switch value {
            case "baseline":
                style.verticalAlign = .baseline
                style.verticalAlignOffset = parentShift
            case "super", "-epub-super":
                style.verticalAlign = .sup
                style.verticalAlignOffset = parentShift + ctx.parent.fontSize / 3 + 1
            case "sub", "-epub-sub":
                style.verticalAlign = .sub
                style.verticalAlignOffset = parentShift - (ctx.parent.fontSize / 5 + 1)
            case "top":
                style.verticalAlign = .top
                style.verticalAlignOffset = parentShift
            case "middle":
                style.verticalAlign = .middle
                style.verticalAlignOffset = parentShift
            case "bottom":
                style.verticalAlign = .bottom
                style.verticalAlignOffset = parentShift
            default: break
            }
        case "border-collapse":
            switch value {
            case "collapse": style.borderCollapse = .collapse
            case "separate": style.borderCollapse = .separate
            default: break
            }
        case "border-spacing":
            let parts = value.split(separator: " ").map(String.init).map { CSSLengthResolver.parse($0) }
            switch parts.count {
            case 1:
                if let v = parts[0] { style.borderSpacingHorizontal = v; style.borderSpacingVertical = v }
            default:
                if let h = parts.first { style.borderSpacingHorizontal = h }
                if let v = parts.dropFirst().first { style.borderSpacingVertical = v }
            }
        case "background-image":
            if let source = parseBackgroundImageSource(preserved) {
                var bg = style.backgroundImage ?? BackgroundImageStyle(source: source)
                bg.source = source
                style.backgroundImage = bg
            }
        case "background-size":
            guard var bg = style.backgroundImage else { break }
            bg.size = parseBackgroundSize(value)
            style.backgroundImage = bg
        case "background-position":
            guard var bg = style.backgroundImage else { break }
            let pos = parseBackgroundPosition(value)
            bg.positionX = pos.x
            bg.positionY = pos.y
            style.backgroundImage = bg
        case "background-repeat":
            guard var bg = style.backgroundImage else { break }
            bg.repeatMode = value.contains("no-repeat") ? .noRepeat : .repeat
            style.backgroundImage = bg
        case "background-attachment":
            guard var bg = style.backgroundImage else { break }
            bg.attachment = value.contains("fixed") ? .fixed : .scroll
            style.backgroundImage = bg
        case "font-size":
            if let px = resolveFontSize(value, parentSize: ctx.parent.fontSize, root: ctx.rootFontSize) {
                style.fontSize = px
            }
        case "font-family":
            style.fontFamilies = fontFamilyList(value)
        case "font-weight":
            style.fontWeight = cssFontWeight(value, current: style.fontWeight)
        case "font-style":
            style.isItalic = value.contains("italic") || value.contains("oblique")
        case "text-align":
            if ["left", "right", "center", "justify", "start", "end"].contains(value) {
                style.textAlign = cssAlignment(value)
                style.blockAlignment = nil
            } else if value == "-webkit-center" || value == "-webkit-left" || value == "-webkit-right" {
                // WebKit's legacy alignments (html.css `center`, `<div
                // align>`) align the text and also every block child that has
                // no auto inline margin (`RenderBox::computeInlineDirectionMargins`).
                let side = String(value.dropFirst("-webkit-".count))
                style.textAlign = cssAlignment(side)
                style.blockAlignment = cssAlignment(side)
            } else if value == "inherit" || value == "unset" {
                style.textAlign = ctx.parent.textAlign
                style.blockAlignment = ctx.parent.blockAlignment
            } else if value == "initial" {
                style.textAlign = .natural
                style.blockAlignment = nil
            }
        case "hyphens", "-webkit-hyphens", "-epub-hyphens", "-moz-hyphens", "-ms-hyphens":
            if ["none", "manual", "auto"].contains(value) { style.hyphens = value }
            else if value == "inherit" || value == "unset" { style.hyphens = ctx.parent.hyphens }
            else if value == "initial" { style.hyphens = "manual" }
        case "overflow-wrap", "word-wrap":
            if ["normal", "break-word", "anywhere"].contains(value) { style.overflowWrap = value }
        case "word-break":
            if ["normal", "break-all", "keep-all", "break-word"].contains(value) { style.wordBreak = value }
        case "text-align-last":
            if value == "auto" { style.textAlignLast = nil }
            else if ["left", "right", "center", "justify", "start", "end"].contains(value) { style.textAlignLast = cssAlignment(value) }
        case "text-indent":
            switch value {
            case "inherit", "unset": style.textIndent = ctx.parent.textIndent
            case "initial": style.textIndent = .initial
            default: if let indent = CSSTextIndent.declaration(value) { style.textIndent = indent }
            }
        case "line-height":
            if value == "inherit" || value == "unset" {
                style.lineHeight = ctx.parent.lineHeight
                style.lineHeightMultiplier = ctx.parent.lineHeightMultiplier
                style.pendingLineHeightLength = nil
            } else if value == "normal" || value == "initial" {
                style.lineHeight = nil
                style.lineHeightMultiplier = nil
                style.pendingLineHeightLength = nil
            } else if let unitless = Double(value), unitless.isFinite, unitless >= 0 {
                style.lineHeight = nil
                style.lineHeightMultiplier = CGFloat(unitless)
                style.pendingLineHeightLength = nil
            } else if let length = CSSLengthResolver.parse(value) {
                style.lineHeight = nil
                style.lineHeightMultiplier = nil
                style.pendingLineHeightLength = length
            }
        case "letter-spacing":
            if value == "inherit" || value == "unset" {
                style.letterSpacing = ctx.parent.letterSpacing
                style.pendingLetterSpacingLength = nil
            } else if value == "normal" || value == "initial" {
                style.letterSpacing = 0
                style.pendingLetterSpacingLength = nil
            } else if let length = CSSLengthResolver.parse(value) {
                style.letterSpacing = nil
                style.pendingLetterSpacingLength = length
            }
        case "quotes":
            if value == "inherit" || value == "unset" {
                style.quotes = ctx.parent.quotes
            } else if let quotes = QuoteMarks.parse(preserved) {
                style.quotes = quotes
            }
        case "text-decoration-line":
            switch value {
            case "inherit": style.textDecorationLine = ctx.parent.textDecorationLine
            case "initial", "unset": style.textDecorationLine = []
            default: if let lines = TextDecorationValue.lines(value) { style.textDecorationLine = lines }
            }
        case "text-decoration-style":
            switch value {
            case "inherit": style.textDecorationStyle = ctx.parent.textDecorationStyle
            case "initial", "unset": style.textDecorationStyle = .solid
            default: if let parsed = TextDecorationValue.style(value) { style.textDecorationStyle = parsed }
            }
        case "text-decoration-color":
            switch value {
            case "inherit": style.textDecorationColor = ctx.parent.textDecorationColor
            case "initial", "unset": style.textDecorationColor = nil
            default: if let parsed = decorationColorToken(value) { style.textDecorationColor = parsed }
            }
        case "text-decoration-thickness":
            switch value {
            case "inherit": style.textDecorationThickness = ctx.parent.textDecorationThickness
            case "initial", "unset": style.textDecorationThickness = .auto
            default: if let parsed = TextDecorationValue.thickness(value) { style.textDecorationThickness = parsed }
            }
        case "text-decoration":
            switch value {
            case "inherit":
                style.textDecorationLine = ctx.parent.textDecorationLine
                style.textDecorationStyle = ctx.parent.textDecorationStyle
                style.textDecorationColor = ctx.parent.textDecorationColor
                style.textDecorationThickness = ctx.parent.textDecorationThickness
            case "initial", "unset":
                style.textDecorationLine = []
                style.textDecorationStyle = .solid
                style.textDecorationColor = nil
                style.textDecorationThickness = .auto
            default:
                guard let parsed = TextDecorationValue.shorthand(components(preserved), color: { decorationColorToken($0.lowercased()) })
                else { break }
                style.textDecorationLine = parsed.lines
                style.textDecorationStyle = parsed.style
                style.textDecorationColor = parsed.color
                style.textDecorationThickness = parsed.thickness
            }
        case "text-underline-offset":
            switch value {
            case "inherit", "unset": style.textUnderlineOffset = ctx.parent.textUnderlineOffset
            case "initial": style.textUnderlineOffset = .auto
            default:
                if let length = CSSLengthResolver.parse(value) {
                    // A font-relative offset inherits as an absolute length.
                    switch length {
                    case .em, .rem, .pt:
                        style.textUnderlineOffset = CSSLengthResolver.resolve(length, emBase: style.fontSize,
                            remBase: ctx.rootFontSize, percentBase: 0).map { .px($0) } ?? length
                    default: style.textUnderlineOffset = length
                    }
                }
            }
        case "text-underline-position":
            switch value {
            case "inherit", "unset": style.textUnderlinePosition = ctx.parent.textUnderlinePosition
            case "initial": style.textUnderlinePosition = TextUnderlinePosition()
            default: if let parsed = TextDecorationValue.underlinePosition(value) { style.textUnderlinePosition = parsed }
            }
        case "text-emphasis-style", "-webkit-text-emphasis-style", "-epub-text-emphasis-style":
            switch value {
            case "inherit", "unset": style.textEmphasisStyle = ctx.parent.textEmphasisStyle
            case "initial": style.textEmphasisStyle = nil
            default: if let parsed = TextEmphasisValue.style(preserved) { style.textEmphasisStyle = parsed }
            }
        case "text-emphasis-color", "-webkit-text-emphasis-color", "-epub-text-emphasis-color":
            switch value {
            case "inherit", "unset": style.textEmphasisColor = ctx.parent.textEmphasisColor
            case "initial": style.textEmphasisColor = nil
            default: if let parsed = decorationColorToken(value) { style.textEmphasisColor = parsed }
            }
        case "text-emphasis-position", "-webkit-text-emphasis-position", "-epub-text-emphasis-position":
            switch value {
            case "inherit", "unset": style.textEmphasisPosition = ctx.parent.textEmphasisPosition
            case "initial": style.textEmphasisPosition = TextEmphasisPosition()
            default: if let parsed = TextEmphasisValue.position(value) { style.textEmphasisPosition = parsed }
            }
        case "text-emphasis", "-webkit-text-emphasis", "-epub-text-emphasis":
            switch value {
            case "inherit", "unset":
                style.textEmphasisStyle = ctx.parent.textEmphasisStyle
                style.textEmphasisColor = ctx.parent.textEmphasisColor
            case "initial":
                style.textEmphasisStyle = nil
                style.textEmphasisColor = nil
            default:
                guard let parsed = TextEmphasisValue.shorthand(components(preserved), color: { decorationColorToken($0.lowercased()) })
                else { break }
                style.textEmphasisStyle = parsed.style
                style.textEmphasisColor = parsed.color
            }
        case "text-decoration-skip-ink":
            switch value {
            case "inherit", "unset": style.textDecorationSkipsInk = ctx.parent.textDecorationSkipsInk
            case "initial", "auto", "all": style.textDecorationSkipsInk = true
            case "none": style.textDecorationSkipsInk = false
            default: break
            }
        case "white-space":
            switch value {
            case "normal": style.whiteSpace = .normal
            case "nowrap": style.whiteSpace = .nowrap
            case "pre": style.whiteSpace = .pre
            case "pre-wrap": style.whiteSpace = .preWrap
            case "pre-line": style.whiteSpace = .preLine
            default: break
            }
        case "ruby-align", "-epub-ruby-align", "-webkit-ruby-align":
            style.rubyAlign = RubyAlignment.parse(value)
        case "ruby-position", "-epub-ruby-position", "-webkit-ruby-position":
            style.rubyPosition = RubyPosition.parse(value)
        case "ruby-merge", "-epub-ruby-merge", "-webkit-ruby-merge":
            style.rubyMerge = RubyMerge.parse(value)
        case "text-combine-upright", "-epub-text-combine-horizontal", "-ms-text-combine-horizontal",
             "-webkit-text-combine", "-epub-text-combine":
            if value == "inherit" || value == "unset" { style.textCombineUpright = ctx.parent.textCombineUpright }
            else if value == "initial" { style.textCombineUpright = .none }
            else if key == "-webkit-text-combine" || key == "-epub-text-combine" {
                style.textCombineUpright = TextCombineUpright.parseLegacy(value)
            } else {
                style.textCombineUpright = TextCombineUpright.parse(value)
            }
        case "width": if let l = CSSLengthResolver.parse(value) { style.width = l }
        case "height": if let l = CSSLengthResolver.parse(value) { style.height = l }
        case "transform", "-webkit-transform":
            style.transformRotate = Self.parseTransformRotate(value)
        case "min-height": style.minHeight = CSSLengthResolver.parse(value)
        case "max-height": style.maxHeight = CSSLengthResolver.parse(value)
        case "max-width": if let l = CSSLengthResolver.parse(value) { style.maxWidth = l }
        case "max-inline-size":
            // `none` lifts an earlier limit on the same side; an unparseable value is dropped.
            let length = value == "none" ? nil : CSSLengthResolver.parse(value)
            guard value == "none" || length != nil else { break }
            if ctx.writingMode == .horizontal { style.maxWidth = length } else { style.maxHeight = length }
        case "min-inline-size":
            // Physical `min-width` stays unparsed, as before; vertical admission
            // still refuses physical `min-height` (the scanner's declaration check).
            let length = value == "auto" ? nil : CSSLengthResolver.parse(value)
            guard value == "auto" || length != nil else { break }
            if ctx.writingMode == .horizontal { style.minWidth = length } else { style.minHeight = length }
        case "margin": applyMarginShorthand(value, to: &style)
        case "margin-top": if let l = CSSLengthResolver.parse(value) { style.marginTop = l }
        case "margin-right": if let l = CSSLengthResolver.parse(value) { style.marginRight = l }
        case "margin-bottom": if let l = CSSLengthResolver.parse(value) { style.marginBottom = l }
        case "margin-left": if let l = CSSLengthResolver.parse(value) { style.marginLeft = l }
        case "padding":
            let parts = value.split(separator: " ").map(String.init).map { CSSLengthResolver.parse($0) }
            assignPadding(parts, to: &style)
        case "padding-top": if let l = CSSLengthResolver.parse(value) { style.paddingTop = l }
        case "padding-right": if let l = CSSLengthResolver.parse(value) { style.paddingRight = l }
        case "padding-bottom": if let l = CSSLengthResolver.parse(value) { style.paddingBottom = l }
        case "padding-left": if let l = CSSLengthResolver.parse(value) { style.paddingLeft = l }
        case "border-top-width": if let length = borderLength(value) { style.pendingBorderTopWidth = length }
        case "border-right-width": if let length = borderLength(value) { style.pendingBorderRightWidth = length }
        case "border-bottom-width": if let length = borderLength(value) { style.pendingBorderBottomWidth = length }
        case "border-left-width": if let length = borderLength(value) { style.pendingBorderLeftWidth = length }
        case "border-width": applyBorderWidthShorthand(value, to: &style)
        case "border":
            // `border: <width> <style> <color>` shorthand. Width + color + style.
            // A colour left out resets to `currentColor`, as a shorthand resets
            // every longhand it omits.
            var color: UIColor? = nil
            for part in components(value) {
                if let length = borderLength(part) {
                    style.pendingBorderTopWidth = length; style.pendingBorderRightWidth = length
                    style.pendingBorderBottomWidth = length; style.pendingBorderLeftWidth = length
                } else if let token = borderColorToken(part) {
                    color = token
                } else if BorderStyle.from(cssRaw: part) != .solid || isBorderStyleKeyword(part) {
                    let s = BorderStyle.from(cssRaw: part)
                    style.borderTopStyle = s; style.borderRightStyle = s
                    style.borderBottomStyle = s; style.borderLeftStyle = s
                }
            }
            style.borderTopColor = color; style.borderRightColor = color
            style.borderBottomColor = color; style.borderLeftColor = color
        case "border-top": applyBorderSideShorthand(part: value, style: &style, side: "top")
        case "border-right": applyBorderSideShorthand(part: value, style: &style, side: "right")
        case "border-bottom": applyBorderSideShorthand(part: value, style: &style, side: "bottom")
        case "border-left": applyBorderSideShorthand(part: value, style: &style, side: "left")
        case "border-style": applyBorderStyleShorthand(value, to: &style)
        case "border-top-style": style.borderTopStyle = BorderStyle.from(cssRaw: value)
        case "border-right-style": style.borderRightStyle = BorderStyle.from(cssRaw: value)
        case "border-bottom-style": style.borderBottomStyle = BorderStyle.from(cssRaw: value)
        case "border-left-style": style.borderLeftStyle = BorderStyle.from(cssRaw: value)
        case "border-color":
            let tokens = components(value).map(borderColorToken)
            guard (1...4).contains(tokens.count), tokens.allSatisfy({ $0 != nil }) else { break }
            let colors = tokens.map { $0! }
            func c(_ i: Int) -> UIColor? { colors[i] }
            switch colors.count {
            case 1: style.borderTopColor = c(0); style.borderRightColor = c(0); style.borderBottomColor = c(0); style.borderLeftColor = c(0)
            case 2: style.borderTopColor = c(0); style.borderRightColor = c(1); style.borderBottomColor = c(0); style.borderLeftColor = c(1)
            case 3: style.borderTopColor = c(0); style.borderRightColor = c(1); style.borderBottomColor = c(2); style.borderLeftColor = c(1)
            default: style.borderTopColor = c(0); style.borderRightColor = c(1); style.borderBottomColor = c(2); style.borderLeftColor = c(3)
            }
        case "border-top-color": if let token = borderColorToken(value) { style.borderTopColor = token }
        case "border-right-color": if let token = borderColorToken(value) { style.borderRightColor = token }
        case "border-bottom-color": if let token = borderColorToken(value) { style.borderBottomColor = token }
        case "border-left-color": if let token = borderColorToken(value) { style.borderLeftColor = token }
        case "border-radius": if let length = borderLength(value) { style.pendingBorderRadius = length }
        case "background":
            if let c = parseColor(shorthandBackgroundColor(value)) { style.backgroundColor = c }
            if let source = parseBackgroundImageSource(preserved) {
                var bg = style.backgroundImage ?? BackgroundImageStyle(source: source)
                bg.source = source
                if value.contains("no-repeat") { bg.repeatMode = .noRepeat }
                if value.contains("cover") { bg.size = .cover }
                else if value.contains("contain") { bg.size = .contain }
                if value.contains("fixed") { bg.attachment = .fixed }
                if value.contains("center") {
                    bg.positionX = .keyword(0.5)
                    bg.positionY = .keyword(0.5)
                }
                style.backgroundImage = bg
            }
        default:
            break // unimplemented properties are ignored (Phase 1)
        }
    }

    /// A `font-family` list's names, unquoted.
    fileprivate static func fontFamilyList(_ value: String) -> [String] {
        value.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'"))) }
    }

    fileprivate static func applyMarginShorthand(_ value: String, to style: inout ComputedStyle) {
        let parts = value.split(separator: " ").map(String.init).map(CSSLengthResolver.parse)
        switch parts.count {
        case 1: if let v = parts[0] { style.marginTop = v; style.marginRight = v; style.marginBottom = v; style.marginLeft = v }
        case 2:
            if let v = parts[0] { style.marginTop = v; style.marginBottom = v }
            if let v = parts[1] { style.marginLeft = v; style.marginRight = v }
        case 3:
            if let v = parts[0] { style.marginTop = v }
            if let v = parts[1] { style.marginLeft = v; style.marginRight = v }
            if let v = parts[2] { style.marginBottom = v }
        case 4:
            if let v = parts[0] { style.marginTop = v }
            if let v = parts[1] { style.marginRight = v }
            if let v = parts[2] { style.marginBottom = v }
            if let v = parts[3] { style.marginLeft = v }
        default: break
        }
    }

    fileprivate static func assignPadding(_ parts: [CSSLength?], to style: inout ComputedStyle) {
        guard !parts.isEmpty else { return }
        func value(_ i: Int) -> CSSLength { if let v = parts[i] { return v }; return .px(0) }
        switch parts.count {
        case 1: style.paddingTop = value(0); style.paddingRight = value(0); style.paddingBottom = value(0); style.paddingLeft = value(0)
        case 2: style.paddingTop = value(0); style.paddingRight = value(1); style.paddingBottom = value(0); style.paddingLeft = value(1)
        case 3: style.paddingTop = value(0); style.paddingRight = value(1); style.paddingBottom = value(2); style.paddingLeft = value(1)
        default: style.paddingTop = value(0); style.paddingRight = value(1); style.paddingBottom = value(2); style.paddingLeft = value(3)
        }
    }

    fileprivate static func borderLength(_ value: String) -> CSSLength? {
        guard let length = CSSLengthResolver.parse(value) else { return nil }
        // Percentages are invalid for border-width. Percentage border-radius
        // needs final border-box axes and remains outside the current typed
        // radius model; never turn either form into a magic 400pt-based value.
        if case .percent = length { return nil }
        if case .auto = length { return nil }
        return length
    }

    /// Degrees for a bare `rotate(<angle>)` transform — the only parsed
    /// function. Anything else (lists, scale/translate/matrix) computes to
    /// none rather than being half-applied.
    fileprivate static func parseTransformRotate(_ value: String) -> CGFloat? {
        let s = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let pattern = #"^rotate\(\s*(-?(?:\d+\.?\d*|\.\d+))(deg|rad|turn)?\s*\)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
              let amountRange = Range(match.range(at: 1), in: s),
              let amount = Double(s[amountRange]) else { return nil }
        let unit = match.range(at: 2).location != NSNotFound
            ? Range(match.range(at: 2), in: s).map { String(s[$0]) } : nil
        switch unit {
        case nil, "deg": return CGFloat(amount)
        case "rad": return CGFloat(amount * 180 / .pi)
        case "turn": return CGFloat(amount * 360)
        default: return nil
        }
    }

    fileprivate static func applyBorderWidthShorthand(
        _ value: String,
        to style: inout ComputedStyle
    ) {
        let widths = value.split(separator: " ").map(String.init).map(borderLength)
        guard !widths.isEmpty else { return }
        func w(_ i: Int) -> CSSLength? { widths[min(i, widths.count - 1)] }
        switch widths.count {
        case 1: style.pendingBorderTopWidth = w(0); style.pendingBorderRightWidth = w(0); style.pendingBorderBottomWidth = w(0); style.pendingBorderLeftWidth = w(0)
        case 2: style.pendingBorderTopWidth = w(0); style.pendingBorderRightWidth = w(1); style.pendingBorderBottomWidth = w(0); style.pendingBorderLeftWidth = w(1)
        case 3: style.pendingBorderTopWidth = w(0); style.pendingBorderRightWidth = w(1); style.pendingBorderBottomWidth = w(2); style.pendingBorderLeftWidth = w(1)
        default: style.pendingBorderTopWidth = w(0); style.pendingBorderRightWidth = w(1); style.pendingBorderBottomWidth = w(2); style.pendingBorderLeftWidth = w(3)
        }
    }

    fileprivate static func shorthandBackgroundColor(_ value: String) -> String {
        value.split(separator: " ")
            .map(String.init)
            .first { $0.hasPrefix("#") || $0.hasPrefix("rgb") || $0.hasPrefix("hsl") }
            ?? ""
    }

    /// True for border-style keywords so `border: 1px dotted #3a4431` can
    /// distinguish the style word from width/color tokens.
    fileprivate static func isBorderStyleKeyword(_ part: String) -> Bool {
        switch part.lowercased() {
        case "solid", "dotted", "dashed", "double", "none", "hidden", "groove", "ridge", "inset", "outset":
            return true
        default:
            return false
        }
    }

    /// A decoration colour: `.some(nil)` for `currentColor`, clear for
    /// `transparent`, nil for a token that is not a colour.
    fileprivate static func decorationColorToken(_ part: String) -> UIColor?? {
        if part == "transparent" { return .some(.clear) }
        return borderColorToken(part)
    }

    /// A border colour: `.some(nil)` for `currentColor`, nil for a token that
    /// is not a colour.
    fileprivate static func borderColorToken(_ part: String) -> UIColor?? {
        if part.lowercased() == "currentcolor" { return .some(nil) }
        return parseColor(part).map { .some($0) }
    }

    /// A value's space-separated components, keeping a function's arguments
    /// (`rgb(0, 0, 0)`) in one.
    fileprivate static func components(_ value: String) -> [String] {
        var result: [String] = []
        var current = ""
        var depth = 0
        for character in value {
            switch character {
            case "(": depth += 1; current.append(character)
            case ")": depth = max(0, depth - 1); current.append(character)
            case " ", "\t", "\n", "\r":
                if depth > 0 { current.append(character) }
                else if !current.isEmpty { result.append(current); current = "" }
            default: current.append(character)
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    /// The longhands of a logical two-sided shorthand: `margin-block`,
    /// `margin-inline`, `padding-block`, `padding-inline` and
    /// `border-{block,inline}-{width,style,color}` take a start and an
    /// optional end value; `border-block` and `border-inline` give both sides
    /// the same `border-*` value. nil for any other property.
    fileprivate static func logicalShorthandLonghands(key: String, value: String) -> [(String, String)]? {
        switch key {
        case "margin-block", "margin-inline", "padding-block", "padding-inline",
             "border-block-width", "border-inline-width", "border-block-style",
             "border-inline-style", "border-block-color", "border-inline-color":
            let parts = components(value)
            guard (1...2).contains(parts.count) else { return [] }
            let segments = key.split(separator: "-").map(String.init)
            let base = segments[0] == "border"
                ? "border-\(segments[1])-%@-\(segments[2])"
                : "\(segments[0])-\(segments[1])-%@"
            return [(base.replacingOccurrences(of: "%@", with: "start"), parts[0]),
                    (base.replacingOccurrences(of: "%@", with: "end"), parts.count == 2 ? parts[1] : parts[0])]
        case "border-block", "border-inline":
            return [("\(key)-start", value), ("\(key)-end", value)]
        default:
            return nil
        }
    }

    fileprivate static func applyBorderStyleShorthand(_ value: String, to style: inout ComputedStyle) {
        let styles = value.split(separator: " ").map(String.init).map { BorderStyle.from(cssRaw: $0) }
        guard !styles.isEmpty else { return }
        func s(_ i: Int) -> BorderStyle { styles[min(i, styles.count - 1)] }
        switch styles.count {
        case 1: style.borderTopStyle = s(0); style.borderRightStyle = s(0); style.borderBottomStyle = s(0); style.borderLeftStyle = s(0)
        case 2: style.borderTopStyle = s(0); style.borderRightStyle = s(1); style.borderBottomStyle = s(0); style.borderLeftStyle = s(1)
        case 3: style.borderTopStyle = s(0); style.borderRightStyle = s(1); style.borderBottomStyle = s(2); style.borderLeftStyle = s(1)
        default: style.borderTopStyle = s(0); style.borderRightStyle = s(1); style.borderBottomStyle = s(2); style.borderLeftStyle = s(3)
        }
    }

    /// `border-top: <width> <style> <color>` side shorthand.
    fileprivate static func applyBorderSideShorthand(
        part value: String,
        style: inout ComputedStyle,
        side: String
    ) {
        // The side's colour alone; one left out resets to `currentColor`.
        var color: UIColor? = nil
        defer {
            switch side {
            case "top": style.borderTopColor = color
            case "right": style.borderRightColor = color
            case "bottom": style.borderBottomColor = color
            default: style.borderLeftColor = color
            }
        }
        for part in components(value) {
            if let length = borderLength(part) {
                switch side {
                case "top": style.pendingBorderTopWidth = length
                case "right": style.pendingBorderRightWidth = length
                case "bottom": style.pendingBorderBottomWidth = length
                default: style.pendingBorderLeftWidth = length
                }
            } else if let token = borderColorToken(part) {
                color = token
            } else if isBorderStyleKeyword(part) {
                let s = BorderStyle.from(cssRaw: part)
                switch side {
                case "top": style.borderTopStyle = s
                case "right": style.borderRightStyle = s
                case "bottom": style.borderBottomStyle = s
                default: style.borderLeftStyle = s
                }
            }
        }
    }

    /// Extracts `url(...)` from a background declaration; returns the raw source
    /// (quotes stripped). nil when no url() is present.
    /// Not fileprivate: `EPUBBrowserLayoutResourceAdapter` prefetches the root
    /// background with the SAME parser, so the fetched key can never disagree
    /// with the source the style tree resolves.
    static func parseBackgroundImageSource(_ value: String) -> String? {
        // Case-insensitive on the FUNCTION NAME only (CSS function names are
        // case-insensitive), while the payload keeps the authored case — it is
        // a path. Callers pass the unfolded declaration value for that reason.
        guard let range = value.range(of: "url(", options: .caseInsensitive) else { return nil }
        let rest = value[range.upperBound...]
        guard let close = rest.firstIndex(of: ")") else { return nil }
        var source = String(rest[..<close]).trimmingCharacters(in: .whitespacesAndNewlines)
        source = source.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        return source.isEmpty ? nil : source
    }

    fileprivate static func parseBackgroundSize(_ value: String) -> BackgroundImageStyle.BackgroundSize {
        let v = value.lowercased()
        if v.contains("cover") { return .cover }
        if v.contains("contain") { return .contain }
        return .auto
    }

    /// Two-keyword position (x y). Keywords map to slack fractions; the layout
    /// resolves them against the container/slack at paint time.
    fileprivate static func parseBackgroundPosition(_ value: String) -> (x: BackgroundImageStyle.BackgroundPosition, y: BackgroundImageStyle.BackgroundPosition) {
        let parts = value.lowercased().split(separator: " ").map(String.init)
        func keywordFraction(_ s: String) -> CGFloat? {
            switch s {
            case "left", "top": return 0
            case "center": return 0.5
            case "right", "bottom": return 1
            default: return nil
            }
        }
        // Default: 0% 0% (top-left).
        var x: BackgroundImageStyle.BackgroundPosition = .percent(0)
        var y: BackgroundImageStyle.BackgroundPosition = .percent(0)
        for part in parts {
            if part.hasSuffix("%"), let v = Double(part.dropLast()) {
                let frac = CGFloat(v) / 100
                if case .percent = x { x = .percent(frac); continue }
                if case .percent = y { y = .percent(frac) }
                continue
            }
            if let f = keywordFraction(part) {
                if f == 0 || f == 0.5 || f == 1 {
                    // First keyword → x (left/center/right); second → y.
                    if part == "left" || part == "right" || part == "center" {
                        if case .percent(0) = x { x = .keyword(f) } else { y = .keyword(f) }
                    } else {
                        // top/bottom always land on y.
                        y = .keyword(f)
                    }
                }
            }
        }
        return (x, y)
    }

    /// Absolute keywords keep WebKit's proportions (its sizes at the default
    /// 16px `medium` are 9, 10, 13, 16, 18, 24, 32, 48; measured through
    /// `<font size>` 1–7 on iOS 27.2) about the reader's root size, so a book's
    /// `small` follows the reader's font size where WebKit's would not.
    /// `larger`/`smaller` are WebKit's ×1.2 and ÷1.2 of the parent's size
    /// (measured: `big` 20.4, `small` 14.17 in 17px text).
    fileprivate static func resolveFontSize(_ raw: String, parentSize: CGFloat, root: CGFloat) -> CGFloat? {
        switch raw {
        case "xx-small": return root * 9 / 16
        case "x-small": return root * 10 / 16
        case "small": return root * 13 / 16
        case "medium": return root
        case "large": return root * 18 / 16
        case "x-large": return root * 24 / 16
        case "xx-large": return root * 2
        case "xxx-large", "-webkit-xxx-large": return root * 3
        case "smaller": return parentSize / 1.2
        case "larger": return parentSize * 1.2
        default:
            guard let parsed = CSSLengthResolver.parse(raw) else { return nil }
            return CSSLengthResolver.resolve(parsed, emBase: parentSize, remBase: root, percentBase: parentSize)
        }
    }

    fileprivate static func cssFontWeight(_ raw: String, current: Int) -> Int {
        switch raw {
        case "normal": return 400
        case "bold": return 700
        case "bolder": return min(900, current + 100)
        case "lighter": return max(100, current - 100)
        default: return Int(raw).map { min(900, max(100, $0)) } ?? current
        }
    }

    fileprivate static func cssAlignment(_ raw: String) -> NSTextAlignment {
        switch raw {
        case "left": return .left
        case "right", "end": return .right
        case "center": return .center
        case "justify": return .justified
        default: return .natural
        }
    }

    fileprivate static func parseColor(_ raw: String) -> UIColor? {
        if raw == "transparent" { return nil }
        if raw == "currentcolor" { return nil }
        if raw.hasPrefix("#") {
            let hex = raw.replacingOccurrences(of: "#", with: "")
            guard let value = UInt64(hex, radix: 16) else { return nil }
            switch hex.count {
            case 3:
                let r = CGFloat((value >> 8) & 0xF) / 15
                let g = CGFloat((value >> 4) & 0xF) / 15
                let b = CGFloat(value & 0xF) / 15
                return UIColor(red: r, green: g, blue: b, alpha: 1)
            case 6:
                let r = CGFloat((value >> 16) & 0xFF) / 255
                let g = CGFloat((value >> 8) & 0xFF) / 255
                let b = CGFloat(value & 0xFF) / 255
                return UIColor(red: r, green: g, blue: b, alpha: 1)
            default: return nil
            }
        }
        if raw.hasPrefix("rgb(") {
            let inner = raw.dropFirst(4).dropLast()
            let comps = inner.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            guard comps.count == 3 else { return nil }
            return UIColor(red: comps[0]/255, green: comps[1]/255, blue: comps[2]/255, alpha: 1)
        }
        if raw.hasPrefix("rgba(") {
            let inner = raw.dropFirst(5).dropLast()
            let comps = inner.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            guard comps.count == 4 else { return nil }
            return UIColor(red: comps[0]/255, green: comps[1]/255, blue: comps[2]/255, alpha: comps[3])
        }
        // CSS's values, not UIKit's: `UIColor.gray` is 127.5 and
        // `UIColor.green` is #00FF00 where CSS has 128 and #008000.
        guard let named = CSSNamedColors.table[raw] else { return nil }
        return UIColor(red: CGFloat(named.red) / 255, green: CGFloat(named.green) / 255,
                       blue: CGFloat(named.blue) / 255, alpha: 1)
    }
}
