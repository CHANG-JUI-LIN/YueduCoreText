import CoreGraphics
import Foundation
import UIKit

/// Phase 2C coordinate contract — five explicit coordinate spaces, each a
/// distinct type so a rect can NEVER be silently used in the wrong space.
/// All conversion goes through NAMED functions in `CoordinateSpace` — raw
/// rect arithmetic across spaces is forbidden.
///
/// | Type             | Space             | Producer                          |
/// |------------------|-------------------|-----------------------------------|
/// | `ParentLocalRect`| parent content    | `BlockBox.frame`                  |
/// | `DocumentRect`   | document absolute | `PageWalker` steps (pre-place)    |
/// | `PageLocalRect`  | page canvas       | `Fragment` / `DisplayItem`        |
/// | `ViewportRect`   | view bounds       | page viewport (== page canvas)    |
/// | `WindowRect`     | window            | `UIView.convert(_:to: window)`    |
///
/// For the paged reader, the page CANVAS equals the actual viewport: origin
/// (0,0) = viewport top-left, size = viewport size. Content sits inside
/// `contentInsets` within it.

/// Parent content-local coordinates (block layout stage).
public struct ParentLocalRect: Equatable, Sendable {
    public init(rawValue: CGRect) { self.rawValue = rawValue }
    public var rawValue: CGRect

    public var minX: CGFloat { rawValue.minX }
    public var minY: CGFloat { rawValue.minY }
    public var maxX: CGFloat { rawValue.maxX }
    public var maxY: CGFloat { rawValue.maxY }
    public var width: CGFloat { rawValue.width }
    public var height: CGFloat { rawValue.height }
    public var origin: CGPoint { rawValue.origin }
    public var size: CGSize { rawValue.size }

    public static let zero = ParentLocalRect(rawValue: .zero)
}

/// Document-absolute coordinates (walker steps before paging).
public struct DocumentRect: Equatable, Sendable {
    public init(rawValue: CGRect) { self.rawValue = rawValue }
    public var rawValue: CGRect

    public var minX: CGFloat { rawValue.minX }
    public var minY: CGFloat { rawValue.minY }
    public var maxX: CGFloat { rawValue.maxX }
    public var maxY: CGFloat { rawValue.maxY }
    public var width: CGFloat { rawValue.width }
    public var height: CGFloat { rawValue.height }
    public var origin: CGPoint { rawValue.origin }
    public var size: CGSize { rawValue.size }

    public static let zero = DocumentRect(rawValue: .zero)
}

/// Page canvas-local coordinates (fragments, display items, painting).
/// The page canvas IS the viewport: origin (0,0) = viewport top-left.
public struct PageLocalRect: Equatable, Sendable {
    public init(rawValue: CGRect) { self.rawValue = rawValue }
    public var rawValue: CGRect

    public var minX: CGFloat { rawValue.minX }
    public var minY: CGFloat { rawValue.minY }
    public var maxX: CGFloat { rawValue.maxX }
    public var maxY: CGFloat { rawValue.maxY }
    public var width: CGFloat { rawValue.width }
    public var height: CGFloat { rawValue.height }
    public var origin: CGPoint { rawValue.origin }
    public var size: CGSize { rawValue.size }
    public var midX: CGFloat { rawValue.midX }
    public var midY: CGFloat { rawValue.midY }

    public static let zero = PageLocalRect(rawValue: .zero)
    public static let null = PageLocalRect(rawValue: .null)

    public func contains(_ point: CGPoint) -> Bool {
        rawValue.contains(point)
    }
}

/// The page viewport (== page canvas for the paged reader).
public struct ViewportRect: Equatable, Sendable {
    public init(rawValue: CGRect) { self.rawValue = rawValue }
    public var rawValue: CGRect
    public static let zero = ViewportRect(rawValue: .zero)
}

/// Window coordinates (the final screen space).
public struct WindowRect: Equatable, Sendable {
    public init(rawValue: CGRect) { self.rawValue = rawValue }
    public var rawValue: CGRect
    public static let zero = WindowRect(rawValue: .zero)
}

/// The single, named coordinate-conversion surface. Layout/paint code must
/// NOT add or subtract rects across spaces directly.
public enum CoordinateSpace {

    /// LayoutBox: parent content-local → document absolute.
    /// `childParentLocalOrigin` is the child's border-box origin in the
    /// parent's content box; `parentDocumentOrigin` is the parent's content
    /// origin in document space.
    public static func parentLocalToDocument(
        _ rect: ParentLocalRect,
        parentDocumentOrigin: CGPoint
    ) -> DocumentRect {
        DocumentRect(rawValue: CGRect(
            x: rect.minX + parentDocumentOrigin.x,
            y: rect.minY + parentDocumentOrigin.y,
            width: rect.width,
            height: rect.height
        ))
    }

    /// Tree assertion: child.documentOrigin == parent.documentContentOrigin +
    /// child.parentLocalOrigin (border-box + parent border/padding).
    static func childDocumentOrigin(
        child: ParentLocalRect,
        parentDocumentContentOrigin: CGPoint,
        parentBorders: EdgeSizes,
        parentPadding: EdgeSizes
    ) -> CGPoint {
        CGPoint(
            x: parentDocumentContentOrigin.x + child.minX + parentBorders.left + parentPadding.left,
            y: parentDocumentContentOrigin.y + child.minY + parentBorders.top + parentPadding.top
        )
    }

    /// Document absolute → page canvas-local.
    /// `pageDocumentOrigin` is this page's document offset (pageIndex × page
    /// content height); `pageContentInset` is the viewport inset.
    public static func documentToPageLocal(
        _ rect: DocumentRect,
        pageDocumentOrigin: CGPoint,
        pageContentInset: CGPoint
    ) -> PageLocalRect {
        PageLocalRect(rawValue: CGRect(
            x: rect.minX - pageDocumentOrigin.x + pageContentInset.x,
            y: rect.minY - pageDocumentOrigin.y + pageContentInset.y,
            width: rect.width,
            height: rect.height
        ))
    }

    /// Tree/geometry assertion for every visible fragment:
    /// pageLocalOrigin == documentOrigin - pageDocumentOrigin + pageContentInset.
    public static func pageLocalOrigin(
        documentOrigin: CGPoint,
        pageDocumentOrigin: CGPoint,
        pageContentInset: CGPoint
    ) -> CGPoint {
        CGPoint(
            x: documentOrigin.x - pageDocumentOrigin.x + pageContentInset.x,
            y: documentOrigin.y - pageDocumentOrigin.y + pageContentInset.y
        )
    }
}

/// One edge of a border box.
public struct BorderEdge: Equatable, Sendable {
    public var width: CGFloat = 0
    public var color: UIColor = .black
    public var style: BorderStyle = .solid

    public static let zero = BorderEdge()

    public var isVisible: Bool { width > 0 && style != .none }
}

public enum BorderStyle: Equatable, Sendable {
    case none
    case solid
    case dotted
    case dashed
    /// Solid, darkened on the physical top and left and lightened on the
    /// bottom and right. The painter resolves the colours
    /// (`BorderEdge.paintedBevel(topOrLeft:)`).
    case inset
    /// `inset` with the darkened and lightened sides swapped.
    case outset

    public static func from(cssRaw: String?) -> BorderStyle {
        switch (cssRaw ?? "solid").lowercased() {
        case "dotted": return .dotted
        case "dashed": return .dashed
        case "inset": return .inset
        case "outset": return .outset
        case "none", "hidden": return .none
        default: return .solid
        }
    }
}

extension BorderEdge {
    /// An `inset` or `outset` edge as the solid edge WebKit paints on one
    /// physical side; any other edge unchanged.
    ///
    /// WebKit (`BorderPainter::calculateBorderStyleColor`) darkens the top and
    /// left of an inset border and lightens its bottom and right, and the
    /// reverse for outset, by physical side: a vertical-rl `hr` is dark on its
    /// physical left. Darkening skips colours at or below the luminance of
    /// rgb(32,32,32), lightening those at or above rgb(235,235,235). Measured on
    /// iOS 27.2: `hr`'s rgb(128,128,128) paints 44 and 212.
    func paintedBevel(topOrLeft: Bool) -> BorderEdge {
        let darkens: Bool
        switch style {
        case .inset: darkens = topOrLeft
        case .outset: darkens = !topOrLeft
        case .none, .solid, .dotted, .dashed: return self
        }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        // A type guard, not a fallback: every CSS-parsed colour is RGB or gray,
        // which `getRed` converts; only a pattern colour has no channels.
        guard color.getRed(&r, green: &g, blue: &b, alpha: &a) else {
            return BorderEdge(width: width, color: color, style: .solid)
        }
        // A CSS colour is 8-bit in WebKit; quantizing keeps rgb(32,32,32)
        // itself on the right side of the threshold it defines.
        func quantized(_ c: CGFloat) -> CGFloat { (min(max(c, 0), 1) * 255).rounded() / 255 }
        (r, g, b) = (quantized(r), quantized(g), quantized(b))
        func linear(_ c: CGFloat) -> CGFloat { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        func luminance(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> CGFloat {
            0.2126729 * linear(r) + 0.7151522 * linear(g) + 0.0721750 * linear(b)
        }
        let v = max(r, g, b)
        let multiplier: CGFloat
        if darkens {
            guard luminance(r, g, b) > luminance(32 / 255, 32 / 255, 32 / 255)
            else { return BorderEdge(width: width, color: color, style: .solid) }
            multiplier = max(0, (v - 0.33) / v)
        } else {
            guard luminance(r, g, b) < luminance(235 / 255, 235 / 255, 235 / 255)
            else { return BorderEdge(width: width, color: color, style: .solid) }
            // WebKit's `lightenedBlack`: black has no hue to scale.
            guard v > 0 else {
                return BorderEdge(width: width, color: UIColor(white: 84 / 255, alpha: a), style: .solid)
            }
            multiplier = min(1, v + 0.33) / v
        }
        // WebKit rounds the result to 8-bit sRGB.
        func byte(_ c: CGFloat) -> CGFloat { (min(max(c * multiplier, 0), 1) * 255).rounded() / 255 }
        return BorderEdge(
            width: width,
            color: UIColor(red: byte(r), green: byte(g), blue: byte(b), alpha: a),
            style: .solid
        )
    }
}

/// How a replaced element (image) paginates when it does not fit the current
/// page (Phase 2C).
enum ReplacedElementPaginationPolicy {
    /// Move the whole element to the next page when it fits there.
    case moveToNextPage
    /// Scale the element to fit the page (aspect preserved) when its intrinsic
    /// size exceeds a whole page. Never split into fragments.
    case scaleToFitPage
    /// Allow overflow (no scaling/clipping handling).
    case overflowVisible
}
