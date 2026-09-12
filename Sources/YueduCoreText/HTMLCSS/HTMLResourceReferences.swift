import Foundation
import SwiftSoup

/// Resource discovery uses the engine's SVG renderability rules, without exposing a DOM/tree.
public enum HTMLResourceReferences {
    public static func imageSources(in html: String) throws -> Set<String> {
        let document = try SwiftSoup.parse(html)
        var sources = Set<String>()
        for image in (try? document.select("img").array()) ?? [] {
            let source = (try? image.attr("src")) ?? ""
            if !source.isEmpty { sources.insert(source) }
        }
        for svg in (try? document.select("svg").array()) ?? [] {
            if let source = BoxTreeBuilder.svgWrappedImageSource(SwiftSoupHTMLSemanticAdapter.snapshot(svg)) {
                sources.insert(source)
            }
        }
        return sources
    }
}
