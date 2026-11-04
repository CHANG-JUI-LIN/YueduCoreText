import Foundation
import UIKit

/// Adds speech/media semantics to the existing resolved tree. DOM parsing and
/// source-text construction still have exactly one owner each.
enum BrowserLayoutSemanticContent {
    /// Inline formatting contexts retain paragraph boundaries independently of
    /// the collapsed source text. Never insert separators into persisted offsets
    /// just to let NSString discover paragraphs for selection.
    static func paragraphRanges(in root: BlockBox) -> [NSRange] {
        var ranges: [NSRange] = []
        func walk(_ box: BlockBox) {
            // A paragraph is the text selection reaches; a picture's character is not text.
            let content = box.inlineRuns.filter { $0.atomic == nil }.map(\.sourceRange).filter { $0.length > 0 }
            if let start = content.map(\.location).min(), let end = content.map(NSMaxRange).max() {
                ranges.append(NSRange(location: start, length: end - start))
            }
            for child in box.children { walk(child) }
        }
        walk(root)
        return ranges.sorted { $0.location < $1.location }
    }

    struct MediaTree {
        let root: ComputedStyleNode
        let attachments: [Int: EPUBMediaAttachment]
        let images: [String: UIImage]
    }

    static func prepareMedia(in root: ComputedStyleNode, renderWidth: CGFloat) -> MediaTree {
        var attachments: [Int: EPUBMediaAttachment] = [:]
        var images: [String: UIImage] = [:]
        func transform(_ node: ComputedStyleNode) -> ComputedStyleNode {
            guard !node.style.isHidden, node.style.display != .none else { return node }
            if node.tag == "video", let element = node.semanticElement {
                let sources = node.children.compactMap { child -> HTMLDOMElementSnapshot? in
                    guard case .element(let source) = child, source.tag == "source" else { return nil }
                    return source.semanticElement
                }
                let direct = element.attribute("src")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let source = direct.isEmpty
                    ? sources.first { !($0.attribute("src") ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                    : element
                if let source, let href = source.attribute("src"), !href.isEmpty {
                    let media = EPUBMediaAttachment(
                        kind: .video, sourceHref: href,
                        mediaType: source.attribute("type"), title: element.attribute("title"),
                        posterHref: element.attribute("poster")
                    )
                    attachments[node.nodeID] = media
                    // Synthetic image identity only: the real href stays in the
                    // media registry and is resolved by the publication adapter.
                    let key = "browser-video-placeholder:\(node.nodeID)"
                    let width = element.attribute("width").flatMap(Double.init)
                    let height = element.attribute("height").flatMap(Double.init)
                    let intrinsic: CGSize? = width.flatMap { w in
                        height.map { h in CGSize(width: w, height: h) }
                    }
                    images[key] = MediaPlaceholderRenderer.videoImage(maxWidth: renderWidth, intrinsicSize: intrinsic)
                    var attributes = element.attributes
                    attributes["src"] = key
                    return ComputedStyleNode(
                        tag: "img",
                        semanticElement: HTMLDOMElementSnapshot(
                            semanticPath: element.semanticPath, tagName: "img", namespace: element.namespace,
                            attributes: attributes, svgRenderability: nil
                        ),
                        style: node.style, children: [], nodeID: node.nodeID,
                        linkTarget: node.linkTarget, anchorID: node.anchorID,
                        listItemOrdinal: node.listItemOrdinal
                    )
                }
            }
            var changed = false
            let children = node.children.map { child -> StyleTreeChild in
                guard case .element(let element) = child else { return child }
                let transformed = transform(element)
                changed = changed || transformed !== element
                return .element(transformed)
            }
            guard changed else { return node }
            return ComputedStyleNode(
                tag: node.tag, semanticElement: node.semanticElement, style: node.style,
                children: children, nodeID: node.nodeID,
                linkTarget: node.linkTarget, anchorID: node.anchorID,
                listItemOrdinal: node.listItemOrdinal
            )
        }
        let transformed = transform(root)
        return MediaTree(root: transformed, attachments: attachments, images: images)
    }

    static func pronunciationHints(root: ComputedStyleNode, box: BlockBox, sourceText: String) -> [TTSPronunciationHint] {
        var ipaByNode: [Int: String] = [:]
        func visit(_ node: ComputedStyleNode, inheritedIPA: String?) {
            let alphabet = node.semanticElement?.attribute("ssml:alphabet")?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let authored = node.semanticElement?.attribute("ssml:ph")?.trimmingCharacters(in: .whitespacesAndNewlines)
            let ipa = (alphabet == nil || alphabet == "ipa") && authored?.isEmpty == false ? authored : inheritedIPA
            ipaByNode[node.nodeID] = ipa
            for child in node.children {
                if case .element(let element) = child { visit(element, inheritedIPA: ipa) }
            }
        }
        visit(root, inheritedIPA: nil)
        let attributed = ipaByNode.isEmpty ? nil : NSMutableAttributedString(string: sourceText)
        var rubyHints: [TTSPronunciationHint] = []
        func record(_ range: NSRange, nodeID: Int) {
            guard let attributed, range.length > 0, NSMaxRange(range) <= attributed.length,
                  let ipa = ipaByNode[nodeID] else { return }
            attributed.addAttribute(BrowserTextAttributes.ipaPronunciation, value: ipa, range: range)
        }
        func walk(_ box: BlockBox) {
            for run in box.inlineRuns {
                if let unit = run.inlineBlock {
                    walk(unit)
                } else if let ruby = run.ruby {
                    for piece in ruby.base { record(piece.sourceRange, nodeID: piece.nodeID) }
                    let reading = ruby.annotation.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !reading.isEmpty {
                        rubyHints.append(TTSPronunciationHint(range: ruby.sourceRange, reading: reading))
                    }
                } else { record(run.sourceRange, nodeID: run.nodeID) }
            }
            for child in box.children { walk(child) }
        }
        walk(box)
        let ipaHints = attributed.map {
            AuthoredPronunciation.hints(in: $0)
        } ?? []
        return (ipaHints + rubyHints.filter { ruby in
            !ipaHints.contains { NSIntersectionRange($0.range, ruby.range).length > 0 }
        }).sorted { $0.range.location < $1.range.location }
    }
}

extension DisplayTextItem {
    /// A list item's counter (`listMarkerStep`): the only text the engine draws
    /// that owns no source characters, placed at a zero-length range where its
    /// item's first line starts. A bullet is a fill, not text. Ruby annotations
    /// carry their base's range, so they never match; generated content
    /// (`::before`), once drawn, would, and needs its own test then.
    var isListMarker: Bool {
        sourceRange.length == 0 && renderedTextOverride != nil
    }
}

extension DisplayList {
    /// What VoiceOver reads for a page or scroll tile that draws this list.
    /// `pageText` is the source text at `pageRange`, and `paragraphRanges` the
    /// chapter's (`BrowserContinuousLayout.paragraphRanges`), as the host
    /// already holds both for selection.
    ///
    /// - The source has nothing between two blocks ("序幕" and "那天" run
    ///   together), so each paragraph that starts on the page starts a line.
    /// - A counter drawn here is read where its item starts, as "1." or "一、"
    ///   (list-marker design §14, decision 1): on a line of its own start,
    ///   without the suffix's trailing space, a space before the text. Bullets
    ///   are shapes and say nothing.
    /// - What starts at the end of `pageRange` belongs to the next page. A
    ///   scroll tile also draws the edge lines of its neighbours, so counting
    ///   the end would read the next tile's first number twice. An item with no
    ///   text at the very end of a page therefore goes unread; it has nothing
    ///   to say.
    /// - A picture's U+FFFC says nothing.
    ///
    /// For speech only. Offsets, search and listening (TTS) use the source
    /// text, which this leaves alone.
    public func spokenText(pageText: String, pageRange: NSRange, paragraphRanges: [NSRange]) -> String {
        let page = pageText as NSString
        func offset(_ location: Int) -> Int? {
            let offset = location - pageRange.location
            return offset >= 0 && offset < page.length ? offset : nil
        }
        // What the source does not say, by where it is said: a line break, and
        // the numbers of the items starting there. Two can start at one place
        // (`<li><ol><li>`, or an empty item and the next); markers are drawn in
        // document order, and each place keeps it.
        var breaks: [Int: [Substring]] = [:]
        for paragraph in paragraphRanges {
            if let offset = offset(paragraph.location), breaks[offset] == nil { breaks[offset] = [] }
        }
        for case .text(let text) in items where text.isListMarker {
            guard let drawn = text.renderedTextOverride, let offset = offset(text.sourceRange.location) else { continue }
            var number = Substring(drawn)
            while number.last?.isWhitespace == true { number.removeLast() }
            breaks[offset, default: []].append(number)
        }
        var spoken = ""
        var cursor = 0
        for (offset, numbers) in breaks.sorted(by: { $0.key < $1.key }) {
            spoken += page.substring(with: NSRange(location: cursor, length: offset - cursor))
            spoken += "\n" + numbers.map { "\($0) " }.joined(separator: "\n")
            cursor = offset
        }
        spoken += page.substring(from: cursor)
        return spoken.replacingOccurrences(of: "\u{FFFC}", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
