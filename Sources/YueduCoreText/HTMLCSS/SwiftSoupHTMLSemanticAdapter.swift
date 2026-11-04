import SwiftSoup

/// Current DOM adapter for frontend-neutral HTML semantics. A future Lexbor
/// frontend supplies its own adapter and reuses `HTMLPresentationalHintExtractor`.
public enum SwiftSoupHTMLSemanticAdapter {
    public static func adapt(_ element: Element) -> HTMLSemanticElement {
        snapshot(element).htmlSemanticElement
    }

    /// Copies every authored attribute and the small amount of semantic DOM
    /// identity required after the frontend returns. The returned value owns no
    /// SwiftSoup node or pointer.
    static func snapshot(_ element: Element) -> HTMLDOMElementSnapshot {
        snapshot(element, semanticPath: semanticPath(of: element))
    }

    /// `snapshot(_:)` for an element a walk down the tree has reached: its path is its
    /// parent's and its index among its parent's elements, which the walk knows. Working
    /// the path out from the element lists every ancestor's element siblings, quadratic in
    /// a block of thousands of rubies.
    static func snapshot(_ element: Element, parentPath: String, siblingIndex: Int) -> HTMLDOMElementSnapshot {
        snapshot(element, semanticPath: parentPath + "/" + segment(of: element, siblingIndex: siblingIndex))
    }

    private static func snapshot(_ element: Element, semanticPath: String) -> HTMLDOMElementSnapshot {
        let attributes = authoredAttributes(of: element)
        return HTMLDOMElementSnapshot(
            semanticPath: semanticPath,
            tagName: element.tagName(),
            namespace: namespaceURI(of: element),
            attributes: attributes,
            svgRenderability: svgRenderability(of: element)
        )
    }

    private static func authoredAttributes(of element: Element) -> [String: String] {
        guard let source = element.getAttributes() else { return [:] }
        var attributes: [String: String] = [:]
        for attribute in source {
            attributes[attribute.getKey()] = attribute.getValue()
        }
        return attributes
    }

    private static func namespaceURI(of element: Element) -> String? {
        var current: Element? = element
        while let candidate = current {
            if candidate.hasAttr("xmlns"),
               let namespace = try? candidate.attr("xmlns"),
               !namespace.isEmpty {
                return namespace
            }
            current = candidate.parent()
        }

        // XHTML parsed as HTML commonly omits an explicit namespace. Keep that
        // absence observable instead of manufacturing frontend-specific state.
        return nil
    }

    private static func semanticPath(of element: Element) -> String {
        var segments: [String] = []
        var current: Element? = element
        while let candidate = current {
            segments.append(segment(of: candidate, siblingIndex: (try? candidate.elementSiblingIndex()) ?? 0))
            current = candidate.parent()
        }
        return segments.reversed().joined(separator: "/")
    }

    private static func segment(of element: Element, siblingIndex: Int) -> String {
        let id = ((try? element.attr("id")) ?? "")
        let suffix = id.isEmpty ? "" : "#\(id)"
        return "\(element.tagName().lowercased())[\(siblingIndex)]\(suffix)"
    }

    private static func svgRenderability(of element: Element) -> SVGRenderability? {
        guard element.tagName().lowercased() == "svg" else { return nil }
        guard let images = try? element.select("image").array(), images.count == 1,
              let image = images.first else {
            return .unsupportedVector
        }
        let drawable = (try? element.select(
            "path, rect, circle, ellipse, line, polyline, polygon, text, textPath, use, g, symbol, marker, pattern, mask, foreignObject"
        ).array()) ?? []
        guard drawable.isEmpty else { return .unsupportedVector }
        for attribute in ["xlink:href", "href"] {
            if let href = try? image.attr(attribute), !href.isEmpty {
                return .rasterWrapper(source: href)
            }
        }
        return .unsupportedVector
    }
}
