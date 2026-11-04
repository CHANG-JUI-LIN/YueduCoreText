import CoreGraphics
import Foundation
import UIKit
import YueduCoreTextTypography

struct EdgeSizes: Equatable {
    var top: CGFloat = 0
    var right: CGFloat = 0
    var bottom: CGFloat = 0
    var left: CGFloat = 0
    static let zero = EdgeSizes()
    var horizontal: CGFloat { left + right }
    var vertical: CGFloat { top + bottom }
}

enum CSSDisplay: Equatable {
    case block, inline, inlineBlock, none
    case table, tableRowGroup, tableHeaderGroup, tableFooterGroup, tableRow, tableCell

    /// Roles inside a table box (everything but the table box itself). A cell is
    /// a block container; groups and rows are pure structure.
    var isTableInternal: Bool {
        switch self {
        case .tableRowGroup, .tableHeaderGroup, .tableFooterGroup, .tableRow, .tableCell: return true
        default: return false
        }
    }
}

enum WhiteSpaceMode: Equatable {
    case normal
    case nowrap
    case pre
    case preWrap
    case preLine
}

/// A resolved `background-image` with its sizing/positioning keywords.
/// Paint-only: presence never affects layout, so it never triggers a
/// capability rejection. The image source is resolved by the caller
/// (document imageLoader) into an actual bitmap at render time.
struct BackgroundImageStyle: Equatable {
    /// The raw `url(...)` source as authored.
    var source: String
    /// `background-size`: cover | contain | explicit size. nil = auto.
    var size: BackgroundSize = .auto
    /// `background-position` keywords (x, y). Default: 0% 0% (top-left).
    var positionX: BackgroundPosition = .percent(0)
    var positionY: BackgroundPosition = .percent(0)
    /// `background-repeat`: repeat | no-repeat. Default repeat.
    var repeatMode: BackgroundRepeatMode = .repeat
    /// `background-attachment`: scroll | fixed. Default scroll.
    var attachment: BackgroundAttachment = .scroll

    enum BackgroundSize: Equatable {
        case auto
        case cover
        case contain
    }

    enum BackgroundPosition: Equatable {
        case percent(CGFloat)     // 0…1
        case keyword(CGFloat)     // resolved offset as fraction of slack (0…1)
        case length(CGFloat)      // absolute offset
    }

    enum BackgroundRepeatMode: Equatable {
        case `repeat`
        case noRepeat
    }

    enum BackgroundAttachment: Equatable {
        case scroll
        case fixed
    }
}

/// Computed style: the result of cascading + inheritance. Box-model measures
/// are stored as `CSSLength` (specified values); the layout stage resolves
/// percentages/auto against the containing block into *used* values.
/// CSS 2.1 §9.5.1 `float`. Initial value `none`; not inherited.
enum CSSFloat: Equatable {
    case none, left, right

    /// The single source of truth for what counts as a valid `float` token.
    /// Returns `nil` for an invalid declaration (`center`, `inline-start`, a
    /// typo), which callers must DROP — dropping leaves the initial `none`.
    ///
    /// Both the style cascade and the capability scanner parse through here so
    /// they can never disagree about whether a box floats. They did disagree
    /// before: the scanner rejected a chapter on the `float` *key* alone, so
    /// Legacy EPUBs carrying only `float: center` (invalid → `none`)
    /// were refused by the browser engine despite having nothing to float.
    static func parse(_ value: String) -> CSSFloat? {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "none": return CSSFloat.none
        case "left": return .left
        case "right": return .right
        default: return nil
        }
    }
}

/// CSS 2.1 §9.5.2 `clear`. Initial value `none`; not inherited.
enum CSSClear: Equatable {
    case none, left, right, both
}

enum CSSVerticalAlign: Equatable {
    /// `sup`/`sub` shift inline runs; `top`/`middle`/`bottom` align table
    /// cells; `baseline` is the initial value.
    case baseline, sup, sub, top, middle, bottom
}

/// CSS 2.1 §17.6. Only the separated model is implemented; collapse is an
/// admission rejection, so layout never sees it.
enum CSSBorderCollapse: Equatable {
    case separate, collapse
}

/// CSS Lists 3 `list-style-type`. Inherited; initial `disc`.
enum CSSListStyleType: Equatable {
    case none
    /// A `<counter-style-name>`, ASCII-lowercased. A name with no counter
    /// style behind it is still a valid declaration and is drawn as `decimal`
    /// (CSS Counter Styles 3 §3), so the cascade keeps it as written.
    case counterStyle(String)

    static let initial = CSSListStyleType.counterStyle("disc")

    /// The one parser for a `list-style-type` value, shared by the longhand and
    /// the `list-style` shorthand. `value` is already folded; nil is an invalid
    /// declaration, which callers drop. A `<string>` or `symbols()` value is not
    /// implemented and is dropped the same way.
    static func parse(_ value: String) -> CSSListStyleType? {
        if value == "none" { return CSSListStyleType.none }
        return isCustomIdent(value) ? .counterStyle(value) : nil
    }

    /// CSS Values 4 `<custom-ident>`, minus escapes: name characters only, no
    /// leading digit or `-digit`, and none of the reserved keywords.
    private static func isCustomIdent(_ token: String) -> Bool {
        let scalars = Array(token.unicodeScalars)
        func isNameStart(_ scalar: Unicode.Scalar) -> Bool {
            ("a"..."z").contains(scalar) || scalar == "_" || scalar.value >= 0x80
        }
        func isName(_ scalar: Unicode.Scalar) -> Bool {
            isNameStart(scalar) || ("0"..."9").contains(scalar) || scalar == "-"
        }
        guard !scalars.isEmpty, scalars.allSatisfy(isName) else { return false }
        let start = scalars[0] == "-" ? 1 : 0
        guard start < scalars.count, isNameStart(scalars[start]) || scalars[start] == "-" else { return false }
        return !["initial", "inherit", "unset", "revert", "revert-layer", "default"].contains(token)
    }

    /// The `list-style` shorthand (CSS Lists 3 §3.4). Any sub-property it leaves
    /// out resets to its initial value. nil is an invalid declaration: a token
    /// that is no sub-property's value, or one sub-property given twice.
    /// `list-style-image` is parsed only so the declaration validates; the image
    /// is never drawn (the marker falls back to the type, as a browser draws it
    /// when the image fails to load).
    static func parseShorthand(_ value: String) -> (type: CSSListStyleType, position: CSSListStylePosition)? {
        var type: CSSListStyleType?
        var position: CSSListStylePosition?
        var hasImage = false
        var noneCount = 0
        for token in shorthandTokens(value) {
            if token == "none" {
                noneCount += 1
            } else if let parsed = CSSListStylePosition.parse(token) {
                guard position == nil else { return nil }
                position = parsed
            } else if isImage(token) {
                guard !hasImage else { return nil }
                hasImage = true
            } else if let parsed = parse(token) {
                guard type == nil else { return nil }
                type = parsed
            } else {
                return nil
            }
        }
        // `none` is a value of both the type and the image, so it goes to
        // whichever of the two the shorthand has not set otherwise.
        for _ in 0..<noneCount {
            if type == nil {
                type = CSSListStyleType.none
            } else if !hasImage {
                hasImage = true
            } else {
                return nil
            }
        }
        return (type ?? .initial, position ?? .outside)
    }

    /// Whitespace-separated, but a function's arguments stay one token, so a
    /// `url()` with a space in it is one image.
    private static func shorthandTokens(_ value: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var depth = 0
        for character in value {
            if character == "(" { depth += 1 } else if character == ")" { depth = max(0, depth - 1) }
            if character.isWhitespace && depth == 0 {
                if !current.isEmpty { tokens.append(current) }
                current = ""
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    private static func isImage(_ token: String) -> Bool {
        guard token.hasSuffix(")"), let open = token.firstIndex(of: "(") else { return false }
        let function = token[..<open]
        return ["url", "image-set", "-webkit-image-set"].contains(function) || function.hasSuffix("gradient")
    }
}

/// CSS Lists 3 `list-style-position`. Inherited; initial `outside`.
enum CSSListStylePosition: Equatable {
    case outside, inside

    static func parse(_ value: String) -> CSSListStylePosition? {
        switch value {
        case "outside": return .outside
        case "inside": return .inside
        default: return nil
        }
    }
}

struct ComputedStyle: Equatable {
    var display: CSSDisplay = .block
    var isHidden = false
    /// Used `float`. STRICT: any token outside {none,left,right} leaves this at
    /// `.none`, because an invalid declaration is dropped and the property keeps
    /// its initial value. Some legacy EPUBs declare invalid `float: center`.
    /// on 51 of its 57 float-classed boxes — `center` is not a float value, so a
    /// browser renders those as ordinary blocks. Anything that dispatches on the
    /// CLASS NAME instead of this computed value floats 89% of them wrongly.
    var cssFloat: CSSFloat = .none
    /// Used `clear`. Same strict rule.
    var cssClear: CSSClear = .none
    var verticalAlign: CSSVerticalAlign = .baseline

    /// Resolved super/sub baseline shift from the line's baseline (0 for
    /// baseline). CSS 2.1 §10.8.1 leaves the amount UA-defined; each step is
    /// computed from the PARENT box's font-size, never this element's own —
    /// see the vertical-align handling in ComputedStyleTreeBuilder. Text
    /// inside a shifted inline box moves with it, so an inline element
    /// starts from its parent's shift: `<sup><a>1</a></sup>` raises the `1`.
    var verticalAlignOffset: CGFloat = 0

    /// Table `border-collapse`; layout only ever runs on `.separate`.
    var borderCollapse: CSSBorderCollapse = .separate
    /// `border-spacing` horizontal/vertical. nil = the UA default (2px), applied
    /// to tables by `UserAgentStyle`; kept as lengths because em resolves
    /// against the table's font size at layout time.
    var borderSpacingHorizontal: CSSLength? = nil
    var borderSpacingVertical: CSSLength? = nil

    var isFloated: Bool {
        cssFloat == .left || cssFloat == .right
    }

    /// `display: list-item`: a block box that generates a marker. A flag on the
    /// block instead of a `CSSDisplay` case, so every `switch display` keeps
    /// treating it as the block it is. Not inherited; any other `display`
    /// keyword clears it, so `li { display: block }` has no marker.
    var isListItem = false
    /// Inherited. The UA sets it on list containers (`UserAgentStyle.listStyleType`).
    var listStyleType: CSSListStyleType = .initial
    /// Inherited.
    var listStylePosition: CSSListStylePosition = .outside

    // Inline text
    var fontSize: CGFloat
    var fontFamilies: [String]
    var fontWeight: Int
    var isItalic: Bool
    var color: UIColor?
    var backgroundColor: UIColor?
    /// Authored `background-image` (paint-only; resolved to a bitmap by the
    /// document imageLoader). nil = none.
    var backgroundImage: BackgroundImageStyle? = nil
    var textAlign: NSTextAlignment = .natural
    /// Set by WebKit's `-webkit-center`/`-left`/`-right` text alignment, which
    /// also places block children; inherited with `text-align`.
    var blockAlignment: NSTextAlignment? = nil
    var lineHeight: CGFloat?            // nil = normal (ascent/descent)
    /// Unitless line-height is inherited as a multiplier and recomputed from
    /// each descendant's own font size. Length/percentage values are finalized
    /// to an absolute computed length before inheritance.
    var lineHeightMultiplier: CGFloat? = nil
    /// Transient winning specified length. The style builder resolves this only
    /// after the complete cascade has selected the final font size.
    var pendingLineHeightLength: CSSLength? = nil
    /// Resolved `letter-spacing` in px; nil = unspecified, so the reader-config
    /// default (`configLetterSpacing`) applies — authored declarations win over
    /// the reader default, as in the browser cascade. em resolves against this
    /// element's final font size, so the value inherits as an absolute length.
    var letterSpacing: CGFloat? = nil
    /// Transient winning specified length, resolved only after the complete
    /// cascade has selected the final font size.
    var pendingLetterSpacingLength: CSSLength? = nil
    var whiteSpace: WhiteSpaceMode = .normal
    /// Inherited specified/computed value. Percentages remain symbolic until
    /// BlockLayout has resolved this block container's final inline size.
    var textIndent: CSSTextIndent = .initial
    var hyphens: String = "manual"
    var language: String? = nil
    /// `quotes`, inherited: nil is `auto`, the marks of the content language
    /// (`QuoteMarks`); an empty list is `none`.
    var quotes: [QuotePair]? = nil
    /// How many `q` elements hold this one, itself included. A `q` opens and
    /// closes with the pair at depth - 1 (CSS Generated Content 3 §3.1.2).
    var quoteDepth = 0
    /// `text-decoration-line`, not inherited: the lines this box sets. What it
    /// and its ancestors set together is `textDecorationsInEffect`.
    var textDecorationLine: TextDecorationLines = []
    /// nil is `currentColor`.
    var textDecorationColor: UIColor? = nil
    var textDecorationStyle: TextDecorationStyle = .solid
    var textDecorationThickness: TextDecorationThickness = .auto
    /// `text-underline-offset`, inherited.
    var textUnderlineOffset: CSSLength = .auto
    /// `text-underline-position`, inherited.
    var textUnderlinePosition = TextUnderlinePosition()
    /// `text-decoration-skip-ink`, inherited: `auto` and `all` skip, `none`
    /// draws through the glyphs.
    var textDecorationSkipsInk = true
    /// The decorations this box draws (`decorationsInEffect(inheriting:)`).
    var textDecorationsInEffect: [AppliedTextDecoration] = []
    var overflowWrap: String = "normal"
    var wordBreak: String = "normal"
    var textAlignLast: NSTextAlignment? = nil
    var rubyAlign: RubyAlignment = .center
    var rubyPosition: RubyPosition = .over
    var rubyMerge: RubyMerge = .separate
    var textCombineUpright: TextCombineUpright = .none

    // Box model (specified)
    var width: CSSLength = .auto
    var height: CSSLength = .auto
    var minHeight: CSSLength? = nil
    var maxHeight: CSSLength? = nil
    var maxWidth: CSSLength? = nil      // nil = none
    /// Set only by `min-inline-size` (horizontal) or, canonically, by `LogicalFlow`
    /// from a vertical inline minimum. nil = auto.
    var minWidth: CSSLength? = nil
    var marginTop: CSSLength = .px(0)
    var marginRight: CSSLength = .px(0)
    var marginBottom: CSSLength = .px(0)
    var marginLeft: CSSLength = .px(0)
    var paddingTop: CSSLength = .px(0)
    var paddingRight: CSSLength = .px(0)
    var paddingBottom: CSSLength = .px(0)
    var paddingLeft: CSSLength = .px(0)
    var borderTopWidth: CGFloat = 0
    var borderRightWidth: CGFloat = 0
    var borderBottomWidth: CGFloat = 0
    var borderLeftWidth: CGFloat = 0
    var pendingBorderTopWidth: CSSLength? = nil
    var pendingBorderRightWidth: CSSLength? = nil
    var pendingBorderBottomWidth: CSSLength? = nil
    var pendingBorderLeftWidth: CSSLength? = nil
    /// Per-side border styles (Phase 2C: dotted/dashed must render).
    var borderTopStyle: BorderStyle = .solid
    var borderRightStyle: BorderStyle = .solid
    var borderBottomStyle: BorderStyle = .solid
    var borderLeftStyle: BorderStyle = .solid
    /// Per-side border colours. nil is `currentColor`, the initial value: the
    /// side paints the element's own `color`.
    var borderTopColor: UIColor?
    var borderRightColor: UIColor?
    var borderBottomColor: UIColor?
    var borderLeftColor: UIColor?
    var borderRadius: CGFloat = 0
    var pendingBorderRadius: CSSLength? = nil
    /// Authored `transform: rotate(<angle>)` in degrees (paint-only; layout is
    /// unaffected per CSS). nil = none. Other transform functions and
    /// `transform-origin` are not parsed.
    var transformRotate: CGFloat? = nil
    var configParagraphSpacing: CGFloat = 0
    var configLineSpacing: CGFloat = 0
    var configLetterSpacing: CGFloat = 0
    var configBold = false

    init(
        fontSize: CGFloat = 17,
        fontFamilies: [String] = [],
        fontWeight: Int = 400,
        isItalic: Bool = false,
        color: UIColor? = nil,
        backgroundColor: UIColor? = nil,
        textAlign: NSTextAlignment = .natural,
        lineHeight: CGFloat? = nil,
        whiteSpace: WhiteSpaceMode = .normal
    ) {
        self.fontSize = fontSize
        self.fontFamilies = fontFamilies
        self.fontWeight = fontWeight
        self.isItalic = isItalic
        self.color = color
        self.backgroundColor = backgroundColor
        self.textAlign = textAlign
        self.lineHeight = lineHeight
        self.whiteSpace = whiteSpace
    }
}

extension ComputedStyle {
    mutating func finalizeLineHeight(rootFontSize: CGFloat) {
        if let multiplier = lineHeightMultiplier {
            lineHeight = max(0, fontSize * multiplier)
            pendingLineHeightLength = nil
            return
        }
        guard let length = pendingLineHeightLength else { return }
        lineHeight = CSSLengthResolver.resolve(
            length,
            emBase: fontSize,
            remBase: rootFontSize,
            percentBase: fontSize
        ).map { max(0, $0) }
        // CSS length/percentage line-height inherits as its absolute computed
        // value, unlike a unitless multiplier.
        pendingLineHeightLength = nil
    }

    mutating func finalizeLetterSpacing(rootFontSize: CGFloat) {
        guard let length = pendingLetterSpacingLength else { return }
        // letter-spacing may go negative (title pages tighten glyphs with it).
        letterSpacing = CSSLengthResolver.resolve(
            length,
            emBase: fontSize,
            remBase: rootFontSize,
            percentBase: fontSize
        )
        pendingLetterSpacingLength = nil
    }

    mutating func finalizeBorderLengths(rootFontSize: CGFloat) {
        func resolved(_ length: CSSLength?) -> CGFloat? {
            guard let length else { return nil }
            return CSSLengthResolver.resolve(
                length,
                emBase: fontSize,
                remBase: rootFontSize,
                percentBase: 0
            ).map { max(0, $0) }
        }
        if let value = resolved(pendingBorderTopWidth) { borderTopWidth = value }
        if let value = resolved(pendingBorderRightWidth) { borderRightWidth = value }
        if let value = resolved(pendingBorderBottomWidth) { borderBottomWidth = value }
        if let value = resolved(pendingBorderLeftWidth) { borderLeftWidth = value }
        if let value = resolved(pendingBorderRadius) { borderRadius = value }
        // A side styled `none` or `hidden` has a computed width of 0 (CSS
        // Backgrounds §3.3), so `hr { border: none }` drops the UA's 1px.
        if borderTopStyle == .none { borderTopWidth = 0 }
        if borderRightStyle == .none { borderRightWidth = 0 }
        if borderBottomStyle == .none { borderBottomWidth = 0 }
        if borderLeftStyle == .none { borderLeftWidth = 0 }
        pendingBorderTopWidth = nil
        pendingBorderRightWidth = nil
        pendingBorderBottomWidth = nil
        pendingBorderLeftWidth = nil
        pendingBorderRadius = nil
    }

    func inherited(from parent: ComputedStyle) -> ComputedStyle {
        var style = ComputedStyle(
            fontSize: parent.fontSize,
            fontFamilies: parent.fontFamilies,
            fontWeight: parent.fontWeight,
            isItalic: parent.isItalic,
            color: parent.color,
            backgroundColor: nil,
            textAlign: parent.textAlign,
            lineHeight: parent.lineHeight,
            whiteSpace: parent.whiteSpace
        )
        style.configParagraphSpacing = parent.configParagraphSpacing
        style.configLineSpacing = parent.configLineSpacing
        style.configLetterSpacing = parent.configLetterSpacing
        style.configBold = parent.configBold
        style.rubyAlign = parent.rubyAlign
        style.rubyPosition = parent.rubyPosition
        style.rubyMerge = parent.rubyMerge
        style.textCombineUpright = parent.textCombineUpright
        style.textIndent = parent.textIndent
        style.hyphens = parent.hyphens
        style.language = parent.language
        style.quotes = parent.quotes
        style.quoteDepth = parent.quoteDepth
        style.textUnderlineOffset = parent.textUnderlineOffset
        style.textUnderlinePosition = parent.textUnderlinePosition
        style.textDecorationSkipsInk = parent.textDecorationSkipsInk
        style.textDecorationsInEffect = parent.textDecorationsInEffect
        style.overflowWrap = parent.overflowWrap
        style.wordBreak = parent.wordBreak
        style.textAlignLast = parent.textAlignLast
        style.blockAlignment = parent.blockAlignment
        // Not `vertical-align` itself, which is not inherited, but the shifted
        // baseline an inline box gives what it holds. An inline-block's
        // contents lay out on their own lines; blocks never carry a shift.
        style.verticalAlignOffset = parent.display == .inline ? parent.verticalAlignOffset : 0
        style.lineHeightMultiplier = parent.lineHeightMultiplier
        style.letterSpacing = parent.letterSpacing
        style.listStyleType = parent.listStyleType
        style.listStylePosition = parent.listStylePosition
        style.pendingLineHeightLength = nil
        return style
    }
}

/// Minimal user-agent stylesheet, rendered as a base `ComputedStyle` per tag.
enum UserAgentStyle {
    /// `display` follows WebKit html.css (iOS 27.2 runtime), which names every
    /// element it makes block or hidden; every other element keeps CSS's
    /// initial `display: inline` — `font`, `big`, `var`, `del`, a custom tag.
    static func basis(for tag: String) -> ComputedStyle {
        var style = ComputedStyle()
        switch tag {
        case "html", "body", "p", "div", "section", "article", "header", "footer", "hgroup",
             "main", "aside", "nav", "search", "address", "center",
             "blockquote", "figure", "figcaption",
             "h1", "h2", "h3", "h4", "h5", "h6",
             "ul", "ol", "menu", "dir", "li", "dl", "dt", "dd", "hr",
             "pre", "xmp", "plaintext", "listing",
             "form", "fieldset", "legend", "details", "summary", "optgroup", "option",
             "frameset", "frame":
            // html.css leaves `legend` inline, but the fieldset's legend is
            // blockified when rendered (HTML Standard §15.3.13).
            style.display = .block
        case "video":
            // WebKit lays `video` out as an inline replaced element. Here the
            // media pass turns it into a placeholder image that keeps this
            // style, and that placeholder has always been a block image.
            style.display = .block
        case "table":
            style.display = .table
            // HTML UA default (WebKit html.css): separated borders, 2px spacing.
            style.borderSpacingHorizontal = .px(2)
            style.borderSpacingVertical = .px(2)
        case "thead":
            style.display = .tableHeaderGroup
        case "tbody":
            style.display = .tableRowGroup
        case "tfoot":
            style.display = .tableFooterGroup
        case "tr":
            style.display = .tableRow
            // HTML UA: rows are middle-aligned and cells inherit that alignment.
            style.verticalAlign = .middle
        case "td", "th":
            style.display = .tableCell
            if tag == "th" { style.fontWeight = 700; style.textAlign = .center }
        case "img", "svg", "canvas":
            style.display = .inlineBlock
        case "head", "script", "style", "title", "meta", "link", "template",
             "area", "base", "basefont", "datalist", "noembed", "noframes", "param",
             "noscript":
            // `noscript` is hidden under html.css's `@media (scripting)`, and a
            // WKWebView runs scripts by default.
            style.display = .none
            style.isHidden = true
        default:
            style.display = .inline
        }

        // Logical margins and paddings and relative font sizes go through the
        // cascade (`declarations(for:nestedInList:)`), not here.
        switch tag {
        case "em", "i":
            style.isItalic = true
        case "strong", "b":
            style.fontWeight = 700
        case "h1", "h2", "h3", "h4", "h5", "h6":
            style.fontWeight = 700
        case "li":
            style.isListItem = true
        case "body":
            style.marginTop = .px(8); style.marginRight = .px(8)
            style.marginBottom = .px(8); style.marginLeft = .px(8)
        case "pre", "xmp", "plaintext", "listing":
            style.whiteSpace = .pre
        default:
            break
        }
        return style
    }

    static let listContainerTags: Set<String> = ["dir", "menu", "ol", "ul"]

    /// The UA declarations that need the cascade, from WebKit html.css (read
    /// out of the iOS 27.2 runtime):
    /// - `p { margin-block: 1em }`
    /// - `pre, xmp, plaintext, listing { font-family: monospace; margin-block:
    ///   1em }` and `tt, code, kbd, samp { font-family: monospace }`
    /// - `:heading(1)`…`(6)`: `font-size` 2, 1.5, 1.17, inherited, 0.83,
    ///   0.67em of the parent's; `margin-block` 0.67, 0.83, 1, 1.33, 1.67,
    ///   2.33em of their own
    /// - `blockquote, figure { margin-block: 1em; margin-inline: 40px }`
    /// - `hr { color: gray; margin-block: 0.5em; margin-inline: auto;
    ///   border-style: inset; border-width: 1px }`: the border is
    ///   `currentColor`, so an author's `hr { color: … }` recolours it, as in
    ///   WebKit. html.css gives `hr` no width; the auto width fills the line
    ///   and the auto margins resolve to 0
    /// - `dd { margin-inline-start: 40px }`
    /// - `big { font-size: larger }`, `small { font-size: smaller }`, `sub {
    ///   vertical-align: sub; font-size: smaller }`, `sup { vertical-align:
    ///   super; font-size: smaller }`
    /// - `i, cite, em, var, address, dfn { font-style: italic }` (`em` and `i`
    ///   are set in `basis(for:)`), `nobr { white-space: nowrap }`, `center {
    ///   text-align: -webkit-center }`
    /// - `u, ins { text-decoration: underline }`, `s, strike, del {
    ///   text-decoration: line-through }`
    /// - `ul, menu, dir, ol { margin-block: 1em; padding-inline-start: 40px }`
    ///   and `dl { margin-block: 1em }`, with `margin-block: 0` for one inside
    ///   a `dir`, `dl`, `menu`, `ol` or `ul`, at any depth (`nestedInList`,
    ///   read only for these five).
    ///
    /// Logical, so the cascade maps them to the writing mode's sides as it does
    /// an author's: in vertical-rl paragraphs are spaced between columns and a
    /// list is indented from the top. Relative, so a heading follows the
    /// reader's font size. html.css writes the block-start margins as `__qem`,
    /// which is `em` outside quirks mode; EPUB XHTML is never in quirks mode.
    static func declarations(for tag: String, nestedInList: Bool) -> [(property: String, value: String)] {
        func block(_ margin: String) -> [(property: String, value: String)] {
            [("margin-block-start", margin), ("margin-block-end", margin)]
        }
        func inline(_ margin: String) -> [(property: String, value: String)] {
            [("margin-inline-start", margin), ("margin-inline-end", margin)]
        }
        switch tag {
        case "p": return block("1em")
        case "pre", "xmp", "plaintext", "listing": return [("font-family", "monospace")] + block("1em")
        case "tt", "code", "kbd", "samp": return [("font-family", "monospace")]
        case "h1": return [("font-size", "2em")] + block("0.67em")
        case "h2": return [("font-size", "1.5em")] + block("0.83em")
        case "h3": return [("font-size", "1.17em")] + block("1em")
        case "h4": return block("1.33em")
        case "h5": return [("font-size", "0.83em")] + block("1.67em")
        case "h6": return [("font-size", "0.67em")] + block("2.33em")
        case "blockquote", "figure": return block("1em") + inline("40px")
        case "hr":
            return block("0.5em") + inline("auto") + [
                ("color", "gray"), ("border-width", "1px"), ("border-style", "inset"),
            ]
        case "dd": return [("margin-inline-start", "40px")]
        case "big": return [("font-size", "larger")]
        case "small": return [("font-size", "smaller")]
        case "sub": return [("vertical-align", "sub"), ("font-size", "smaller")]
        case "sup": return [("vertical-align", "super"), ("font-size", "smaller")]
        case "cite", "var", "dfn", "address": return [("font-style", "italic")]
        case "nobr": return [("white-space", "nowrap")]
        case "center": return [("text-align", "-webkit-center")]
        case "u", "ins": return [("text-decoration", "underline")]
        case "s", "strike", "del": return [("text-decoration", "line-through")]
        case "dl": return block(nestedInList ? "0" : "1em")
        case _ where listContainerTags.contains(tag):
            return block(nestedInList ? "0" : "1em") + [("padding-inline-start", "40px")]
        default: return []
        }
    }

    /// The ancestors that take a list container's or a `dl`'s block margins
    /// away; the same five are the ones whose margins they take.
    static let nestedListMarginAncestors: Set<String> = ["dir", "dl", "menu", "ol", "ul"]

    /// WebKit html.css: `ul, menu, dir` are `disc` and `ol` is `decimal`; a
    /// `dir`, `menu` or `ul` inside one list container is `circle`, inside two
    /// or more `square`. nil for every other element, which inherits.
    /// `listAncestors` counts ancestors in `listContainerTags`. It is a UA rule
    /// set apart from `basis(for:)` because the inherited value it replaces can
    /// equal the initial one (`ol { list-style-type: none }` around a `ul`).
    static func listStyleType(for tag: String, listAncestors: Int) -> CSSListStyleType? {
        switch tag {
        case "ol":
            return .counterStyle("decimal")
        case "ul", "menu", "dir":
            switch listAncestors {
            case 0: return .counterStyle("disc")
            case 1: return .counterStyle("circle")
            default: return .counterStyle("square")
            }
        default:
            return nil
        }
    }
}
