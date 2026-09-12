import CoreGraphics
import Foundation

/// Phase 3A — Link / Annotation interaction.
///
/// One pipeline, no per-kind special cases:
///
///     DOM <a href> → LinkAnchorInfo → LayoutBox/Fragment → PageFragment
///     → LinkInteractionRegion → hitTest → pressed → LinkResolver → destination
///
/// A link exists because the DOM says so. Nothing here inspects class names,
/// image file names, `duokan-*` conventions, or "looks like a footnote":
/// `linkTarget` is resolved once, in `ComputedStyleTreeBuilder`, from the
/// nearest ancestor `<a href>`, and every later stage only carries it forward.

// MARK: - Semantics

/// EPUB 3 structural semantics of an `<a>`, read from its `epub:type`.
///
/// Deliberately only the ONE value that changes behaviour. `epub:type` carries
/// dozens of tokens; mapping more of them onto reader actions would be guessing
/// at author intent, and an unknown token must behave exactly like a plain link.
public enum LinkSemantic: Equatable {
    /// An ordinary link: navigate to its target.
    case plain
    /// `<a epub:type="noteref" href="#n1">` — a note reference. Opens the note
    /// body in the existing popup instead of paging to where the note lives.
    case noteref

    /// Parses an `epub:type` attribute value (a space-separated token list).
    public static func from(epubType raw: String) -> LinkSemantic {
        let tokens = raw.lowercased()
            .split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" })
            .map(String.init)
        return tokens.contains("noteref") ? .noteref : .plain
    }
}

/// DOM link identity for one style-tree node sitting inside an `<a href>`.
///
/// Recorded for the `<a>` AND for every descendant node, because a link's
/// rendered pieces do not share the anchor's own nodeID: a text run carries the
/// nodeID of the element that owns the text, and an `<img>` carries its own.
/// `anchorNodeID` is what makes "these fragments are the same link" answerable
/// across text runs, lines, images and pages.
public struct LinkAnchorInfo: Equatable {
    public init(anchorNodeID: Int, semantic: LinkSemantic) { self.anchorNodeID = anchorNodeID; self.semantic = semantic }
    public let anchorNodeID: Int
    public let semantic: LinkSemantic
}

// MARK: - Interaction region

/// A tappable piece of a link, in FINAL page-local geometry.
///
/// Regions consume the geometry the layout already produced — they never
/// recompute a position from document coordinates, and creating them can never
/// move anything. One link produces as many regions as it has visible pieces
/// (multiple runs, multiple lines, an image, a page split); every one of them
/// carries the same `href` and the same `linkID`.
public struct LinkInteractionRegion: Equatable {
    /// What kind of fragment produced this region. Not used to decide whether
    /// the region is tappable — only to let the view know that a tap here must
    /// not also open the image previewer.
    public enum Kind: Equatable {
        case text
        case image
    }

    /// Page canvas-local rect, exactly as the fragment was placed.
    public let pageLocalRect: CGRect
    public let href: String
    /// Identity of the LINK (the `<a>`'s nodeID), shared by every region of the
    /// same link — the grouping key for pressed feedback.
    public let linkID: Int
    /// The style-tree node this particular region was rendered from.
    public let nodeID: Int
    public let sourceRange: NSRange
    public let spineIndex: Int
    public let semantic: LinkSemantic
    public let kind: Kind

    public var area: CGFloat { pageLocalRect.width * pageLocalRect.height }
}

/// Every link region of ONE page, plus the hit test over them.
///
/// This is the single hit-testing implementation for the browser engine. The
/// view layer converts a touch into a page-local point and asks here; it never
/// re-reads the DOM or re-measures CoreText.
public struct LinkInteractionRegionSet: Equatable {

    /// Tap tolerance around a region before it counts as "inside". Matches the
    /// legacy hit test (4pt expansion, then nearest within 6pt) so links do not
    /// become harder to hit than they were on the old engine.
    public static let containmentSlop: CGFloat = 4
    public static let nearestSlop: CGFloat = 6

    public let regions: [LinkInteractionRegion]

    public static var empty: LinkInteractionRegionSet { LinkInteractionRegionSet(regions: []) }

    public var isEmpty: Bool { regions.isEmpty }

    /// Builds the regions for one page's display list.
    ///
    /// `anchors` is the DOM-authored link map (nodeID → owning `<a>`); a
    /// fragment with a `linkTarget` but no entry is still a link — it just has
    /// no EPUB semantic and is its own identity.
    public static func build(
        from list: DisplayList,
        spineIndex: Int,
        anchors: [Int: LinkAnchorInfo]
    ) -> LinkInteractionRegionSet {
        var regions: [LinkInteractionRegion] = []
        for item in list.items {
            switch item {
            case .text(let text):
                guard let href = normalizedHref(text.linkTarget) else { continue }
                append(
                    &regions, rect: text.rect.rawValue, href: href, nodeID: text.nodeID,
                    sourceRange: text.sourceRange, spineIndex: spineIndex,
                    anchors: anchors, kind: .text
                )
            case .image(let image):
                // A CSS background is paint, not an element: it has no DOM node
                // and therefore never carries link semantics. The guard is
                // structural, not defensive — `isBackgroundPaint` fragments are
                // built with `linkTarget: nil`, so this only documents intent.
                guard !image.isBackgroundPaint,
                      let href = normalizedHref(image.linkTarget) else { continue }
                append(
                    &regions, rect: image.rect.rawValue, href: href, nodeID: image.nodeID,
                    sourceRange: image.sourceRange, spineIndex: spineIndex,
                    anchors: anchors, kind: .image
                )
            case .fill:
                // A box's background/border paints the link's containing block,
                // not the link itself. Making it tappable would turn a whole
                // bordered paragraph into one giant hit target.
                continue
            }
        }
        return LinkInteractionRegionSet(regions: regions)
    }

    private static func append(
        _ regions: inout [LinkInteractionRegion],
        rect: CGRect,
        href: String,
        nodeID: Int,
        sourceRange: NSRange,
        spineIndex: Int,
        anchors: [Int: LinkAnchorInfo],
        kind: LinkInteractionRegion.Kind
    ) {
        // A zero-area fragment cannot be tapped and cannot be highlighted.
        guard rect.width > 0, rect.height > 0 else { return }
        let info = anchors[nodeID]
        regions.append(LinkInteractionRegion(
            pageLocalRect: rect,
            href: href,
            linkID: info?.anchorNodeID ?? nodeID,
            nodeID: nodeID,
            sourceRange: sourceRange,
            spineIndex: spineIndex,
            semantic: info?.semantic ?? .plain,
            kind: kind
        ))
    }

    private static func normalizedHref(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }

    /// The link at a page-local point, or nil.
    ///
    /// Containment wins over proximity, and the SMALLEST containing region wins
    /// over a larger one — an image inside a link box resolves to the image, not
    /// to whatever else overlaps it.
    public func hitTest(_ point: CGPoint) -> LinkInteractionRegion? {
        var containing: LinkInteractionRegion?
        var nearest: (region: LinkInteractionRegion, distanceSquared: CGFloat)?
        for region in regions {
            let expanded = region.pageLocalRect.insetBy(
                dx: -Self.containmentSlop, dy: -Self.containmentSlop
            )
            if expanded.contains(point) {
                if containing == nil || region.area < containing!.area {
                    containing = region
                }
                continue
            }
            let dx = max(expanded.minX - point.x, 0, point.x - expanded.maxX)
            let dy = max(expanded.minY - point.y, 0, point.y - expanded.maxY)
            let distanceSquared = dx * dx + dy * dy
            guard distanceSquared <= Self.nearestSlop * Self.nearestSlop else { continue }
            if nearest == nil || distanceSquared < nearest!.distanceSquared {
                nearest = (region, distanceSquared)
            }
        }
        return containing ?? nearest?.region
    }

    /// Every region of one link — a link that wraps two lines has two, and
    /// pressing it must highlight both (CSS `:active` applies to the element).
    public func pieces(ofLink linkID: Int) -> [LinkInteractionRegion] {
        regions.filter { $0.linkID == linkID }
    }
}

// MARK: - Resolution

/// Where an href points, once normalized. Resolution is pure: it needs the
/// spine's source hrefs and nothing else, so it is decided without touching
/// reader state, and it is unit-testable without an engine.
