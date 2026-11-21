import CoreGraphics

/// Where a CSS background image is painted: its first tile, the axes it
/// repeats along and the area that clips it (CSS Backgrounds 3 §3.3–§3.9).
public struct BackgroundTiling: Equatable, Sendable {
    /// The positioned tile; every other tile is this one stepped by its own
    /// width or height.
    public let tile: CGRect
    public let repeatsX: Bool
    public let repeatsY: Bool
    /// The background painting area. Nothing is drawn outside it.
    public let clip: CGRect

    public init(tile: CGRect, repeatsX: Bool, repeatsY: Bool, clip: CGRect) {
        self.tile = tile
        self.repeatsX = repeatsX
        self.repeatsY = repeatsY
        self.clip = clip
    }

    public func offsetBy(dx: CGFloat, dy: CGFloat) -> BackgroundTiling {
        BackgroundTiling(tile: tile.offsetBy(dx: dx, dy: dy), repeatsX: repeatsX, repeatsY: repeatsY,
                         clip: clip.offsetBy(dx: dx, dy: dy))
    }

    /// Every tile that shows inside `bounds` (the painting area when nil), in
    /// reading order. Tiles are whole: one that crosses the edge is returned
    /// unclipped, for the caller to clip.
    public func tiles(in bounds: CGRect? = nil) -> [CGRect] {
        let visible = (bounds ?? clip).intersection(clip)
        guard !visible.isNull, visible.width > 0, visible.height > 0, tile.width > 0, tile.height > 0 else { return [] }
        func steps(_ repeats: Bool, origin: CGFloat, size: CGFloat, from: CGFloat, to: CGFloat) -> ClosedRange<Int>? {
            guard repeats else { return origin < to && origin + size > from ? 0...0 : nil }
            let first = Int(((from - origin) / size).rounded(.down))
            let last = Int(((to - origin) / size).rounded(.up)) - 1
            return first <= last ? first...last : nil
        }
        guard let columns = steps(repeatsX, origin: tile.minX, size: tile.width, from: visible.minX, to: visible.maxX),
              let rows = steps(repeatsY, origin: tile.minY, size: tile.height, from: visible.minY, to: visible.maxY) else { return [] }
        var result: [CGRect] = []
        result.reserveCapacity(columns.count * rows.count)
        for row in rows {
            for column in columns {
                result.append(tile.offsetBy(dx: CGFloat(column) * tile.width, dy: CGFloat(row) * tile.height))
            }
        }
        return result
    }
}

enum BackgroundImageGeometry {
    /// Sizes and places `style`'s image in `area`, which is both the
    /// positioning area and the painting area. nil when there is nothing to
    /// paint (an empty image or area, or a size that resolves to zero).
    static func tiling(for imageSize: CGSize, style: BackgroundImageStyle, area: CGRect,
                       emBase: CGFloat, remBase: CGFloat) -> BackgroundTiling? {
        guard imageSize.width > 0, imageSize.height > 0, area.width > 0, area.height > 0 else { return nil }
        let size = tileSize(for: imageSize, size: style.size, area: area.size, emBase: emBase, remBase: remBase)
        guard size.width > 0, size.height > 0 else { return nil }
        func origin(_ position: BackgroundImageStyle.BackgroundPosition, room: CGFloat) -> CGFloat {
            switch position {
            case .percent(let fraction):
                return fraction * room
            case .length(let length, let fromEnd):
                let offset = CSSLengthResolver.resolve(length, emBase: emBase, remBase: remBase, percentBase: room,
                                                       viewportHeight: area.height, viewportWidth: area.width) ?? 0
                return fromEnd ? room - offset : offset
            }
        }
        let x = origin(style.positionX, room: area.width - size.width)
        let y = origin(style.positionY, room: area.height - size.height)
        return BackgroundTiling(tile: CGRect(x: area.minX + x, y: area.minY + y, width: size.width, height: size.height),
                                repeatsX: style.repeatsX, repeatsY: style.repeatsY, clip: area)
    }

    private static func tileSize(for image: CGSize, size: BackgroundImageStyle.BackgroundSize, area: CGSize,
                                 emBase: CGFloat, remBase: CGFloat) -> CGSize {
        switch size {
        case .auto:
            return image
        case .cover:
            let scale = max(area.width / image.width, area.height / image.height)
            return CGSize(width: image.width * scale, height: image.height * scale)
        case .contain:
            let scale = min(area.width / image.width, area.height / image.height)
            return CGSize(width: image.width * scale, height: image.height * scale)
        case .explicit(let width, let height):
            func resolve(_ length: CSSLength, against extent: CGFloat) -> CGFloat? {
                CSSLengthResolver.resolve(length, emBase: emBase, remBase: remBase, percentBase: extent,
                                          viewportHeight: area.height, viewportWidth: area.width).map { max(0, $0) }
            }
            switch (resolve(width, against: area.width), resolve(height, against: area.height)) {
            case (let w?, let h?): return CGSize(width: w, height: h)
            case (let w?, nil): return CGSize(width: w, height: w * image.height / image.width)
            case (nil, let h?): return CGSize(width: h * image.width / image.height, height: h)
            case (nil, nil): return image
            }
        }
    }
}
