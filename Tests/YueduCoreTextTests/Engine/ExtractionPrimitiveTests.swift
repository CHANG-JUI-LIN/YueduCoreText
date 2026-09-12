import Testing
import UIKit
@testable import YueduCoreText

struct ExtractionPrimitiveTests {
    @Test func parserRetainsCascadeAndNamespaceSelectors() {
        let rules = CSSParser.parse(css: "/* publisher */ @charset \"UTF-8\"; body { width:80%; color:red !important; } a[epub|type~='noteref'] { margin: 1em; }")
        #expect(rules.count == 2)
        #expect(rules[0].declarations["width"] == "80%")
        #expect(rules[0].importantDeclarations["color"] == "red")
        #expect(rules[1].selector.components.last?.attributes.first?.name == "epub:type")
        #expect(CSSLengthResolver.resolve(.percent(0.8), emBase: 17, remBase: 17, percentBase: 300) == 240)
    }
    @Test func fontTraitsPreserveSizeAndCascade() {
        let base = UIFont(name: "Georgia", size: 23)!
        let prepared = ReaderFontCascade.preservingPrimary(base, size: 23, isBoldRequested: true)
        #expect(prepared.pointSize == 23)
        let descriptors = prepared.fontDescriptor.object(forKey: .cascadeList) as? [UIFontDescriptor]
        #expect(descriptors?.isEmpty == false)
        #expect(descriptors?.allSatisfy { $0.pointSize == 23 } == true)
        #expect(FontTraits.synthesizedObliqueFont(from: prepared).pointSize == 23)
    }
}
