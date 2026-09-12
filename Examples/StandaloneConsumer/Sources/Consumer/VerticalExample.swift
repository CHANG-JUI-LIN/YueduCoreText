import UIKit
import YueduCoreText

/// A vertical-rl consumer owns the document/session just like a horizontal one.
/// Returned page coordinates are physical, top-left/y-down. Text advances down
/// each column and columns advance right-to-left. Ruby maps to its base UTF-16.
@MainActor
public func makeVerticalExample() async throws -> (pages: [PageFragments], text: String, flow: BrowserScrollDocument) {
    let configuration = BrowserLayoutConfig(renderWidth: 200, renderHeight: 320,
        rootFontSize: 24, fontFamilies: ["HiraginoSans-W3"],
        contentInsets: UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12),
        writingMode: .verticalRTL)
    let document = HTMLLayoutDocument(
        html: "<p id='start'><a href='#start'><ruby><rb>山<span>路</span></rb><rt>やまみち</rt></ruby></a>を登りながら考えた。かなカナ ABC 123 か\u{3099}𠮷🌕</p>",
        css: ["html{writing-mode:vertical-rl} p{margin:0;line-height:1.75} rt{font-size:50%;color:#b02030}"],
        configuration: configuration)
    let session = try document.makePageSession()
    try await session.finish()
    return (session.completedPages, session.sourceText, try document.prepareContinuous().makeDocument())
}
