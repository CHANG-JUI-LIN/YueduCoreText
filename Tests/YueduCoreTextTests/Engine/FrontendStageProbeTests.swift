import Foundation
import SwiftSoup
import Testing
import UIKit
@testable import YueduCoreText

/// Opt-in stage timing of the capability scan and the Current frontend on
/// chapters dumped by the app (`YUEDU_FRONTEND_INPUT_DIR`). Diagnostic only.
struct FrontendStageProbeTests {
    static func load(_ url: URL) throws -> (id: String, input: CSSFrontendInput) {
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        let sheets = (object["stylesheets"] as! [[String: Any]]).map { sheet -> AuthorStylesheet in
            let source = sheet["source"] as! [String: Any]
            let kind: AuthorStylesheet.Source = source["inline"].map { .inline(nodeOrdinal: $0 as! Int) }
                ?? .linked(href: source["linked"] as! String)
            return AuthorStylesheet(
                source: kind, text: sheet["text"] as! String, sourceOrder: sheet["sourceOrder"] as! Int,
                currentCompatibilityOrder: sheet["currentCompatibilityOrder"] as? Int,
                currentCompatibilityOnly: sheet["currentCompatibilityOnly"] as! Bool,
                media: sheet["media"] as? String, isAlternate: sheet["isAlternate"] as! Bool,
                loadFailed: sheet["loadFailed"] as! Bool)
        }
        return (object["id"] as! String, CSSFrontendInput(html: object["html"] as! String, stylesheets: sheets))
    }

    private static func ms(_ body: () throws -> Void) rethrows -> Double {
        let start = CACurrentMediaTime(); try body(); return (CACurrentMediaTime() - start) * 1000
    }

    @Test func stageTimings() throws {
        guard let dir = ProcessInfo.processInfo.environment["YUEDU_FRONTEND_INPUT_DIR"] else { return }
        let files = try FileManager.default.contentsOfDirectory(atPath: dir).filter { $0.hasSuffix(".json") }.sorted()
        let scanConfig = BrowserLayoutConfig(fontFamilies: ["PingFangSC-Regular"], isBold: false)
        var layoutConfig = BrowserLayoutConfig(renderWidth: 366, renderHeight: 776, rootFontSize: 17,
                                               fontFamilies: ["PingFangSC-Regular"], textColor: .black, backgroundColor: .white)
        layoutConfig.lineHeight = 1.5
        for file in files {
            let (id, input) = try Self.load(URL(fileURLWithPath: dir).appendingPathComponent(file))
            // Warm once, then time 7 rounds and report the median.
            _ = BrowserLayoutCapabilityScanner.scan(input: input, writingMode: .horizontal, configuration: scanConfig)
            var rows: [[String: Double]] = []
            for _ in 0..<7 {
                var row: [String: Double] = [:]
                row["scan.total"] = Self.ms { _ = BrowserLayoutCapabilityScanner.scan(input: input, writingMode: .horizontal, configuration: scanConfig) }
                let cssTexts = input.productionStylesheetTexts
                var doc: Document!
                row["s1.htmlParse"] = try Self.ms { doc = try SwiftSoup.parse(input.html) }
                let includeInline = !input.hasAuthoredStylesheetOrder
                var fullCSS: [String] = []
                row["s2.domSelects"] = try Self.ms {
                    fullCSS = cssTexts + (includeInline ? CurrentCSSFrontendSupport.inlineStyles(in: doc) : [])
                    _ = try doc.select("script, iframe, object, embed, canvas, audio").isEmpty()
                    _ = try doc.select("math").isEmpty()
                    _ = try doc.select("table, thead, tbody, tr, td, th, colgroup").isEmpty()
                    _ = try doc.select("svg").array()
                    _ = try doc.select("ruby, rp, rt, rb, rtc").isEmpty()
                    _ = try doc.select("[style]").array()
                }
                var elements: [Element] = []
                row["s3.allElements"] = try Self.ms { elements = try doc.getAllElements().array() }
                var matchedRules = 0; var totalRules = 0
                row["s4.declMatching"] = Self.ms {
                    for css in fullCSS {
                        for rule in CSSParser.parse(css: css, orderOffset: 0) {
                            totalRules += 1
                            let matched = elements.filter { rule.selector.matches(element: $0, parent: $0.parent()) }
                            if !matched.isEmpty { matchedRules += 1 }
                        }
                    }
                }
                var parsed: (regular: [CSSRule], firstLetter: [CSSRule]) = ([], [])
                row["s5.parseStylesheets"] = Self.ms { parsed = CurrentCSSFrontendSupport.parseStylesheets(in: fullCSS) }
                var tree: ComputedStyleNode!
                row["s6.styleTree"] = Self.ms {
                    tree = ComputedStyleTreeBuilder(rules: parsed.regular, config: scanConfig, firstLetterRules: parsed.firstLetter).buildTree(body: doc.body()!)
                }
                row["s7.validations"] = Self.ms {
                    _ = HorizontalRubySupport.validate(tree, writingMode: .horizontal)
                    _ = HorizontalTextIndentSupport.usage(in: tree)
                }
                var metrics = LayoutMetrics()
                row["fe.total"] = try Self.ms { _ = try CurrentCSSFrontend().buildStyleTree(input: input, config: layoutConfig, metrics: &metrics) }
                for (k, v) in metrics.stages { row["fe." + k] = v * 1000 }
                // The shared path: one parse, one cascade, admission facts, and the
                // layout pipeline up to the box tree without a second frontend run.
                var shared: BrowserChapterEvaluation!
                row["new.document"] = try Self.ms { shared = try BrowserChapterDocument(input: input).evaluate(configuration: layoutConfig) }
                var old = LayoutMetrics(); var reused = LayoutMetrics()
                row["old.toBoxTree"] = try Self.ms {
                    _ = try BrowserLayoutDocument(input: input, config: layoutConfig).makeLayout(
                        containerSize: CGSize(width: 390, height: 800), metrics: &old, performLayout: false)
                }
                row["new.toBoxTree"] = try Self.ms {
                    _ = try BrowserLayoutDocument(input: input, config: layoutConfig, preparedFrontend: shared.preparedFrontend).makeLayout(
                        containerSize: CGSize(width: 390, height: 800), metrics: &reused, performLayout: false)
                }
                row["n.elements"] = Double(elements.count); row["n.rules"] = Double(totalRules); row["n.matchedRules"] = Double(matchedRules)
                rows.append(row)
            }
            let keys = Set(rows.flatMap { $0.keys }).sorted()
            var line = "STAGE-PROBE \(id) htmlBytes=\(input.html.utf8.count)"
            for key in keys {
                let values = rows.compactMap { $0[key] }.sorted()
                line += " \(key)=\(String(format: "%.1f", values[values.count / 2]))"
            }
            print(line)
        }
    }
}
