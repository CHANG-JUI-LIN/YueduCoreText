import CoreGraphics
import CoreText
import UIKit
import YueduCoreTextTypography

/// Flex layout (CSS Flexbox Level 1), in horizontal text.
///
/// A flex container's box holds one block box per item (`FlexSupport`).
/// `BlockLayout` resolves the container's own width and box model as for any
/// block and calls `layOutItems` where it would have stacked the children.
/// Each item is sized here, laid out by `BlockLayout` as a block container of
/// exactly that width, and placed by its frame.
///
/// What is done:
/// - rows and columns, `flex-wrap: wrap`, `gap`;
/// - `flex-grow`, `flex-shrink` and `flex-basis` along a row (§9.7), with
///   `min-width`/`max-width` and the content-based minimum of §4.5;
/// - `justify-content`, `align-items`, `align-self`, and `auto` margins;
/// - in a column, `justify-content` and `flex-grow` when the container has a
///   height of its own to share out.
///
/// What is not: reversed directions and `order` (admission turns them away),
/// baseline alignment (items are aligned to the line's start), `align-content`
/// (the lines of a wrapping container are packed at the start), shrinking in a
/// column, and stretching a picture across a row's height.
///
/// Pagination: the items of a row sit side by side, so a line of several
/// items is moved to the next page whole when it does not fit what is left of
/// this one (`FlexItemState.lineRect`). A line taller than a page is walked
/// item by item like a table row. A column, and a line of one item, break
/// between and inside their items like any block.
enum FlexLayout {

    /// What `BlockLayout.layOut` passes down unchanged.
    struct Environment {
        let rootFontSize: CGFloat
        let textWritingMode: ReaderWritingMode?
        let sourceText: String
        let fontResolver: (([String], Int, Bool, CGFloat) -> UIFont?)?
        let cjkTypographyStyle: CJKTypographyStyle?
        let fragmentHeight: CGFloat?
        let viewportHeight: CGFloat?
        let viewportWidth: CGFloat?
        let viewport: BrowserViewportLayoutState?
    }

    private struct Item {
        let box: BlockBox
        var margins = EdgeSizes.zero
        var autoLeft = false, autoRight = false, autoTop = false, autoBottom = false
        var padding = EdgeSizes.zero
        var borders = EdgeSizes.zero
        /// Flex base size (row) or cross size (column), content box.
        var base: CGFloat = 0
        /// `width` when it is not `auto`, content box.
        var specifiedWidth: CGFloat? = nil
        /// `min-width`; nil is `auto`, the content-based minimum.
        var minimum: CGFloat? = nil
        var maximum = CGFloat.greatestFiniteMagnitude
        var grow: CGFloat = 0
        var shrink: CGFloat = 1
        var align = FlexAlignment.stretch
        var hasAutoHeight = true
        var isPicture = false
        var isFlexContainer = false
        /// Used content width.
        var main: CGFloat = 0
        /// Border-box height, once laid out.
        var height: CGFloat = 0

        var chromeWidth: CGFloat { padding.horizontal + borders.horizontal }
        var outerWidth: CGFloat { margins.horizontal + chromeWidth + main }
        var outerHeight: CGFloat { margins.vertical + height }
    }

    private struct Container {
        var isColumn = false
        var wraps = false
        var justify = FlexAlignment.start
        var distribution = FlexDistribution.none
        var rowGap: CGFloat = 0
        var columnGap: CGFloat = 0
        /// Content-box height the container declares, and its minimum.
        var height: CGFloat? = nil
        var minHeight: CGFloat = 0
    }

    /// Sizes, lays out and places the items of `box`, whose content width is
    /// already resolved. Returns the height they take in its content box.
    static func layOutItems(of box: BlockBox, env: Environment) -> CGFloat {
        let container = describe(box, env: env)
        var items = box.children.compactMap { measure($0, in: box, env: env) }
        guard !items.isEmpty else { return 0 }
        return container.isColumn
            ? layOutColumn(&items, container: container, width: box.contentSize.width, env: env)
            : layOutRows(&items, container: container, width: box.contentSize.width, env: env)
    }

    // MARK: - Rows

    private static func layOutRows(_ items: inout [Item], container: Container, width: CGFloat,
                                   env: Environment) -> CGFloat {
        var lineTop: CGFloat = 0
        var start = 0
        while start < items.count {
            let end = container.wraps
                ? lineEnd(from: start, items: items, gap: container.columnGap, width: width)
                : items.count
            let isOnlyLine = start == 0 && end == items.count
            resolveFlexibleLengths(&items, start..<end, gap: container.columnGap, width: width, env: env)
            for index in start..<end {
                items[index].height = layOut(items[index], forcedContentHeight: nil, env: env)
            }
            var cross = items[start..<end].map(\.outerHeight).max() ?? 0
            if isOnlyLine {
                // A single line is as tall as a container with a height (§9.4).
                cross = max(container.height ?? cross, container.minHeight)
            }
            placeAlongRow(&items, start..<end, container: container, width: width)
            for index in start..<end {
                alignInRow(&items[index], lineTop: lineTop, cross: cross, env: env)
            }
            items[start].box.flexItem?.lineRect = end - start > 1
                ? CGRect(x: 0, y: lineTop, width: width, height: cross) : nil
            lineTop += cross + container.rowGap
            start = end
        }
        return max(0, lineTop - container.rowGap)
    }

    /// The first item that no longer fits the line starting at `start`.
    private static func lineEnd(from start: Int, items: [Item], gap: CGFloat, width: CGFloat) -> Int {
        var used: CGFloat = 0
        var index = start
        while index < items.count {
            let next = items[index].margins.horizontal + items[index].chromeWidth + hypothetical(items[index])
            if index > start, used + gap + next > width + 0.001 { break }
            used += (index > start ? gap : 0) + next
            index += 1
        }
        return index
    }

    /// The base size within the declared minimum and maximum.
    private static func hypothetical(_ item: Item) -> CGFloat {
        max(item.minimum ?? 0, min(item.base, item.maximum))
    }

    /// CSS Flexbox §9.7: the used width of every item on one line.
    private static func resolveFlexibleLengths(_ items: inout [Item], _ line: Range<Int>, gap: CGFloat,
                                               width: CGFloat, env: Environment) {
        let gaps = gap * CGFloat(line.count - 1)
        func chrome(_ item: Item) -> CGFloat { item.margins.horizontal + item.chromeWidth }
        let hypotheticalSum = items[line].reduce(0) { $0 + chrome($1) + hypothetical($1) }
        let grows = hypotheticalSum + gaps < width
        if !grows, line.count > 1 {
            // The content-based minimum only matters to an item that may shrink
            // beside another: alone on its line, an item narrower than its
            // longest word overflows the same way either side of the floor.
            for index in line where items[index].minimum == nil && items[index].shrink > 0 {
                let content = minContentWidth(of: items[index].box, containerWidth: width, env: env)
                let floor = min(content, items[index].specifiedWidth ?? content, items[index].maximum)
                items[index].minimum = min(floor, items[index].base)
            }
        }
        var frozen = Set<Int>()
        for index in line {
            let item = items[index]
            let factor = grows ? item.grow : item.shrink
            let size = hypothetical(item)
            if factor == 0 || (grows && item.base > size) || (!grows && item.base < size) {
                items[index].main = size
                frozen.insert(index)
            } else {
                items[index].main = item.base
            }
        }
        // Frozen items count at their size, the others at their base (their `main` so far).
        let initialFree = width - gaps - items[line].reduce(0) { $0 + chrome($1) + $1.main }
        while frozen.count < line.count {
            var free = width - gaps - items[line].reduce(0) { $0 + chrome($1) }
            for index in line { free -= frozen.contains(index) ? items[index].main : items[index].base }
            let unfrozen = line.filter { !frozen.contains($0) }
            let factorSum = unfrozen.reduce(0) { $0 + (grows ? items[$1].grow : items[$1].shrink) }
            if factorSum < 1, abs(initialFree * factorSum) < abs(free) { free = initialFree * factorSum }
            let scaledShrinkSum = unfrozen.reduce(0) { $0 + items[$1].shrink * items[$1].base }
            var violation: CGFloat = 0
            var clamped: [(index: Int, isMinimum: Bool)] = []
            for index in unfrozen {
                let item = items[index]
                var target = item.base
                if grows, factorSum > 0 {
                    target += free * item.grow / factorSum
                } else if !grows, scaledShrinkSum > 0 {
                    target += free * item.shrink * item.base / scaledShrinkSum
                }
                let used = max(item.minimum ?? 0, min(target, item.maximum), 0)
                items[index].main = used
                violation += used - target
                if used > target + 0.0001 { clamped.append((index, true)) }
                if used < target - 0.0001 { clamped.append((index, false)) }
            }
            if abs(violation) < 0.0001 {
                frozen.formUnion(unfrozen)
            } else {
                for entry in clamped where entry.isMinimum == (violation > 0) { frozen.insert(entry.index) }
            }
        }
    }

    /// Sets each item's inline position: `auto` margins take the free space
    /// first, then `justify-content` (§9.5).
    private static func placeAlongRow(_ items: inout [Item], _ line: Range<Int>, container: Container,
                                      width: CGFloat) {
        let gaps = container.columnGap * CGFloat(line.count - 1)
        let free = width - gaps - items[line].reduce(0) { $0 + $1.outerWidth }
        let autoCount = items[line].reduce(0) { $0 + ($1.autoLeft ? 1 : 0) + ($1.autoRight ? 1 : 0) }
        var cursor: CGFloat = 0
        var between: CGFloat = 0
        if autoCount > 0, free > 0 {
            let share = free / CGFloat(autoCount)
            for index in line {
                if items[index].autoLeft { items[index].margins.left += share }
                if items[index].autoRight { items[index].margins.right += share }
            }
        } else {
            let count = CGFloat(line.count)
            switch container.distribution {
            case .spaceBetween where free > 0 && line.count > 1:
                between = free / (count - 1)
            case .spaceAround where free > 0:
                between = free / count
                cursor = between / 2
            case .spaceEvenly where free > 0:
                between = free / (count + 1)
                cursor = between
            default:
                switch container.justify {
                case .center: cursor = free / 2
                case .end: cursor = free
                case .start, .stretch: cursor = 0
                }
            }
        }
        for index in line {
            items[index].box.logicalInlineOrigin = cursor + items[index].margins.left
            cursor += items[index].outerWidth + container.columnGap + between
        }
    }

    /// Sets the item's block position on its line and its frame (§9.4 steps 11–14).
    private static func alignInRow(_ item: inout Item, lineTop: CGFloat, cross: CGFloat, env: Environment) {
        let free = cross - item.outerHeight
        var shift: CGFloat = 0
        if item.autoTop || item.autoBottom {
            if free > 0 {
                if item.autoTop { item.margins.top += item.autoBottom ? free / 2 : free }
                if item.autoBottom { item.margins.bottom += item.autoTop ? free / 2 : free }
            }
        } else {
            switch item.align {
            case .stretch:
                if item.hasAutoHeight, !item.isPicture, free > 0 { stretch(&item, by: free, env: env) }
            case .center: shift = free / 2
            case .end: shift = free
            case .start: break
            }
        }
        place(item, x: item.box.logicalInlineOrigin, y: lineTop + item.margins.top + shift)
    }

    // MARK: - Columns

    private static func layOutColumn(_ items: inout [Item], container: Container, width: CGFloat,
                                     env: Environment) -> CGFloat {
        var total: CGFloat = 0
        for index in items.indices {
            var item = items[index]
            let available = width - item.margins.horizontal - item.chromeWidth
            let stretches = item.align == .stretch && !item.autoLeft && !item.autoRight
            // Stretched, an item is as wide as the container; otherwise as wide
            // as its content, at most what the container leaves it (§9.4 step 7).
            let size = item.specifiedWidth ?? (stretches ? available : min(item.base, available))
            item.main = max(item.minimum ?? 0, min(size, item.maximum), 0)
            item.height = layOut(item, forcedContentHeight: nil, env: env)
            total += item.outerHeight
            items[index] = item
        }
        total += container.rowGap * CGFloat(items.count - 1)

        // Free space along the column exists only when the container has a
        // height of its own; in a book it is a page-high title or picture page.
        var free = max(container.height ?? total, container.minHeight) - total
        var cursor: CGFloat = 0
        var between: CGFloat = 0
        if free > 0 {
            let growSum = items.reduce(0) { $0 + $1.grow }
            let autoCount = items.reduce(0) { $0 + ($1.autoTop ? 1 : 0) + ($1.autoBottom ? 1 : 0) }
            if growSum > 0 {
                let shared = growSum < 1 ? free * growSum : free
                for index in items.indices where items[index].grow > 0 && items[index].hasAutoHeight {
                    stretch(&items[index], by: shared * items[index].grow / growSum, env: env)
                }
                free = max(container.height ?? 0, container.minHeight)
                    - items.reduce(0) { $0 + $1.outerHeight } - container.rowGap * CGFloat(items.count - 1)
            }
            if free > 0.0001, autoCount > 0 {
                let share = free / CGFloat(autoCount)
                for index in items.indices {
                    if items[index].autoTop { items[index].margins.top += share }
                    if items[index].autoBottom { items[index].margins.bottom += share }
                }
            } else if free > 0.0001 {
                let count = CGFloat(items.count)
                switch container.distribution {
                case .spaceBetween where items.count > 1: between = free / (count - 1)
                case .spaceAround: between = free / count; cursor = between / 2
                case .spaceEvenly: between = free / (count + 1); cursor = between
                default:
                    switch container.justify {
                    case .center: cursor = free / 2
                    case .end: cursor = free
                    case .start, .stretch: cursor = 0
                    }
                }
            }
        }
        for index in items.indices {
            var item = items[index]
            let space = width - item.outerWidth
            var x = item.margins.left
            if item.autoLeft || item.autoRight {
                if space > 0 { x += item.autoLeft ? (item.autoRight ? space / 2 : space) : 0 }
            } else {
                switch item.align {
                case .center: x += space / 2
                case .end: x += space
                case .start, .stretch: break
                }
            }
            place(item, x: x, y: cursor + item.margins.top)
            item.box.flexItem?.lineRect = nil
            cursor += item.outerHeight + container.rowGap + between
            items[index] = item
        }
        return max(0, total)
    }

    // MARK: - Items

    /// Lays `item` out as a block container whose content box is `item.main`
    /// wide; returns its border-box height.
    private static func layOut(_ item: Item, forcedContentHeight: CGFloat?, env: Environment) -> CGFloat {
        prepare(item, forcedContentHeight: forcedContentHeight)
        BlockLayout.layOut(
            root: item.box,
            containerWidth: item.main + item.chromeWidth,
            rootFontSize: env.rootFontSize,
            writingMode: .horizontal,
            textWritingMode: env.textWritingMode,
            floatContext: nil,
            sourceText: env.sourceText,
            fontResolver: env.fontResolver,
            cjkTypographyStyle: env.cjkTypographyStyle,
            fragmentHeight: env.fragmentHeight,
            viewportHeight: env.viewportHeight, viewportWidth: env.viewportWidth, viewport: env.viewport
        )
        return item.box.frame.height
    }

    /// Writes the used values into the box's style, from the authored one: the
    /// block layout that follows resolves percentages against the item's own
    /// width, where the item's are measured against its container.
    private static func prepare(_ item: Item, forcedContentHeight: CGFloat?) {
        guard var style = item.box.flexItem?.authored else { return }
        style.marginTop = .px(0); style.marginRight = .px(0)
        style.marginBottom = .px(0); style.marginLeft = .px(0)
        style.paddingTop = .px(item.padding.top); style.paddingRight = .px(item.padding.right)
        style.paddingBottom = .px(item.padding.bottom); style.paddingLeft = .px(item.padding.left)
        style.minWidth = nil
        style.maxWidth = nil
        // The used width, stated as the content box's: left to `auto`, it would
        // be what the container's width leaves after the padding and borders,
        // which rounding can make a hair narrower than the text measured for it.
        style.width = .px(item.main + (style.boxSizingBorderBox ? item.chromeWidth : 0))
        if let height = forcedContentHeight {
            style.height = .px(height + (style.boxSizingBorderBox ? item.padding.vertical + item.borders.vertical : 0))
        }
        item.box.style = style
    }

    /// Makes the item `extra` taller: stretched across its line, or grown down
    /// its column. A flex container is laid out again, as its own alignment
    /// depends on the height it now has.
    private static func stretch(_ item: inout Item, by extra: CGFloat, env: Environment) {
        let box = item.box
        let contentHeight = box.contentSize.height + extra
        if item.isFlexContainer {
            item.height = layOut(item, forcedContentHeight: contentHeight, env: env)
            return
        }
        box.contentSize.height = contentHeight
        item.height += extra
        box.frame = ParentLocalRect(rawValue: CGRect(
            x: box.frame.minX, y: box.frame.minY, width: box.frame.width, height: item.height))
    }

    private static func place(_ item: Item, x: CGFloat, y: CGFloat) {
        let box = item.box
        box.margins = item.margins
        box.logicalInlineOrigin = x
        box.logicalBlockOrigin = y
        box.frame = ParentLocalRect(rawValue: CGRect(x: x, y: y, width: box.frame.width, height: item.height))
    }

    // MARK: - Reading styles

    private static func describe(_ box: BlockBox, env: Environment) -> Container {
        let style = box.style
        func length(_ value: CSSLength?) -> CGFloat? {
            guard let value else { return nil }
            if case .percent = value { return nil }
            return CSSLengthResolver.resolve(
                value, emBase: style.fontSize, remBase: env.rootFontSize, percentBase: 0,
                viewportHeight: env.viewportHeight, viewportWidth: env.viewportWidth)
        }
        let extras = style.boxSizingBorderBox ? box.padding.vertical + box.borders.vertical : 0
        var container = Container()
        container.isColumn = style.flexIsColumn
        container.wraps = style.flex.wraps && !style.flexIsColumn
        container.justify = style.justifyContent
        container.distribution = style.flex.distribution
        container.rowGap = max(0, length(style.flex.rowGap) ?? 0)
        container.columnGap = max(0, length(style.flex.columnGap) ?? 0)
        container.height = length(style.height).map { max(0, $0 - extras) }
        container.minHeight = max(0, (length(style.minHeight) ?? 0) - extras)
        return container
    }

    /// The item for `child`, nil when it is not one (an absolutely positioned
    /// child is placed by `BlockLayout`).
    private static func measure(_ child: BlockBox, in parent: BlockBox, env: Environment) -> Item? {
        guard let state = child.flexItem else { return nil }
        state.lineRect = nil
        let style = state.authored
        let width = parent.contentSize.width
        func length(_ value: CSSLength?) -> CGFloat? {
            guard let value else { return nil }
            return CSSLengthResolver.resolve(
                value, emBase: style.fontSize, remBase: env.rootFontSize, percentBase: width,
                viewportHeight: env.viewportHeight, viewportWidth: env.viewportWidth)
        }
        var item = Item(box: child)
        item.padding = EdgeSizes(
            top: length(style.paddingTop) ?? 0, right: length(style.paddingRight) ?? 0,
            bottom: length(style.paddingBottom) ?? 0, left: length(style.paddingLeft) ?? 0)
        item.borders = EdgeSizes(
            top: style.borderTopWidth, right: style.borderRightWidth,
            bottom: style.borderBottomWidth, left: style.borderLeftWidth)
        let top = length(style.marginTop), right = length(style.marginRight)
        let bottom = length(style.marginBottom), left = length(style.marginLeft)
        item.margins = EdgeSizes(top: top ?? 0, right: right ?? 0, bottom: bottom ?? 0, left: left ?? 0)
        item.autoTop = top == nil; item.autoRight = right == nil
        item.autoBottom = bottom == nil; item.autoLeft = left == nil
        item.grow = style.flex.grow
        item.shrink = style.flex.shrink
        item.align = style.flex.alignSelf ?? parent.style.alignItems
        item.isFlexContainer = style.isFlexContainer
        switch style.height {
        case .auto, .percent: item.hasAutoHeight = true
        default: item.hasAutoHeight = false
        }
        let extras = style.boxSizingBorderBox ? item.chromeWidth : 0
        item.specifiedWidth = length(style.width).map { max(0, $0 - extras) }
        if let minimum = style.minWidth, let used = length(minimum) { item.minimum = max(0, used - extras) }
        if let maximum = style.maxWidth, let used = length(maximum) { item.maximum = max(0, used - extras) }
        if child.imageAttachment != nil {
            item.isPicture = true
            // The picture's own size: what `width`, `height` and `max-width`
            // make of it in this container.
            child.style = style
            BlockLayout.resolvePictureSize(in: child, containingInlineSize: width, env: env)
            item.base = child.imageAttachment?.usedSize.width ?? 0
            item.specifiedWidth = parent.style.flexIsColumn ? item.base : item.specifiedWidth
        } else {
            item.base = item.specifiedWidth ?? state.maxContentWidth
        }
        if !parent.style.flexIsColumn, let basis = style.flex.basis, let used = length(basis) {
            item.base = max(0, used - extras)
        }
        return item
    }

    // MARK: - Content-based minimum

    /// The narrowest the box's content can be set without overflowing: its
    /// longest unbreakable piece. Content box.
    private static func minContentWidth(of box: BlockBox, containerWidth: CGFloat, env: Environment) -> CGFloat {
        if let attachment = box.imageAttachment { return attachment.usedSize.width }
        let style = box.flexItem?.authored ?? box.style
        var widest = minContentWidth(of: box.inlineRuns, env: env)
        var sum: CGFloat = 0
        var count = 0
        for child in box.children where !child.isAbsolutelyPositioned {
            let childStyle = child.flexItem?.authored ?? child.style
            func length(_ value: CSSLength?) -> CGFloat {
                value.flatMap {
                    CSSLengthResolver.resolve($0, emBase: childStyle.fontSize, remBase: env.rootFontSize,
                                              percentBase: containerWidth)
                } ?? 0
            }
            let chrome = length(childStyle.paddingLeft) + length(childStyle.paddingRight)
                + childStyle.borderLeftWidth + childStyle.borderRightWidth
            let margins = length(childStyle.marginLeft) + length(childStyle.marginRight)
            let content: CGFloat
            if case .auto = childStyle.width {
                content = minContentWidth(of: child, containerWidth: containerWidth, env: env) + chrome
            } else {
                content = length(childStyle.width) + (childStyle.boxSizingBorderBox ? 0 : chrome)
            }
            widest = max(widest, content + margins)
            sum += content + margins
            count += 1
        }
        // A row that does not wrap is as narrow as its items together.
        if style.isFlexContainer, !style.flexIsColumn, !style.flex.wraps {
            let gap = style.flex.columnGap.flatMap {
                CSSLengthResolver.resolve($0, emBase: style.fontSize, remBase: env.rootFontSize, percentBase: 0)
            } ?? 0
            return max(widest, sum + gap * CGFloat(max(0, count - 1)))
        }
        return widest
    }

    /// The widest piece of `runs` no line break can divide: a word, a picture,
    /// an inline-block, a run that does not wrap. A Han or kana character
    /// breaks on either side, so each is a piece of its own.
    private static func minContentWidth(of runs: [InlineRun], env: Environment) -> CGFloat {
        var widest: CGFloat = 0
        let token = NSMutableAttributedString()
        func flush() {
            guard token.length > 0 else { return }
            let line = CTLineCreateWithAttributedString(token)
            widest = max(widest, CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)))
            token.deleteCharacters(in: NSRange(location: 0, length: token.length))
        }
        for run in runs {
            if run.isHardBreak { flush(); continue }
            if let atomic = run.atomic {
                flush()
                widest = max(widest, atomic.usedSize.width)
                continue
            }
            if let unit = run.inlineBlock {
                flush()
                let content = unit.shrinkToFitContentWidth
                    ?? CSSLengthResolver.resolve(unit.style.width, emBase: unit.style.fontSize,
                                                 remBase: env.rootFontSize, percentBase: 0) ?? 0
                widest = max(widest, content)
                continue
            }
            let attributes = InlineLayout.textAttributes(for: run.style, resolver: env.fontResolver)
            if run.style.whiteSpace == .nowrap || run.style.whiteSpace == .pre {
                token.append(NSAttributedString(string: run.shapedText, attributes: attributes))
                continue
            }
            for character in run.shapedText {
                if character.isWhitespace || character == "\u{200B}" {
                    flush()
                } else if character.breaksOnEitherSide {
                    flush()
                    widest = max(widest, run.style.fontSize)
                } else {
                    token.append(NSAttributedString(string: String(character), attributes: attributes))
                }
            }
        }
        flush()
        return widest
    }
}

private extension Character {
    /// Han, kana, hangul and their full-width punctuation: a line may break
    /// before and after each (UAX #14 class ID and its neighbours).
    var breaksOnEitherSide: Bool {
        guard let scalar = unicodeScalars.first else { return false }
        switch scalar.value {
        case 0x2E80...0x9FFF, 0xAC00...0xD7AF, 0xF900...0xFAFF, 0xFF00...0xFFEF, 0x20000...0x3FFFF: return true
        default: return false
        }
    }
}
