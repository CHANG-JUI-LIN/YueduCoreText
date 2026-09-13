# YueduCoreText

[English](README.md) · [繁體中文](README.zh-Hant.md) · [简体中文](README.zh-Hans.md)

**以 Core Text 为核心的 iOS 原生 HTML/CSS 排版与绘制引擎。**

将 HTML/XHTML、CSS 与准备好的资源转换成分页结果或连续文档，绘制到 `CGContext`，并查询文字、链接和选区的几何信息。集成时不需要 Yuedu Reader 源代码，也不需要 WebView。

适合需要自行控制绘制和交互的原生文档或阅读界面。你的 App 提供资源、承载界面；包负责解析、计算样式、排版、分页与绘制。

[0.4.0 版本](https://github.com/CHANG-JUI-LIN/YueduCoreText/releases/tag/0.4.0) · [可运行示例](Examples/StandaloneConsumer) · [进阶集成指南（英文）](docs/EngineIntegration.md) · [更新记录](CHANGELOG.md)

## 环境要求与安装

- iOS 17+、Swift tools 6.0+、Xcode 16+。需要 UIKit、Core Text 与 Core Graphics；这是 iOS 包。
- HTML/CSS 引擎从 **0.3.0** 开始提供。0.2.1 及更早版本只有原有工具 API。
- 主产品依赖 `YueduCoreTextTypography` 与 **SwiftSoup 2.13.7**。

在 Xcode 中选择 **File → Add Package Dependencies**，输入 `https://github.com/CHANG-JUI-LIN/YueduCoreText`，将 **YueduCoreText** 产品添加到你的 target。使用 0.4.x 时，选择 **Up to Next Minor Version**，起始版本填 **0.4.0**。

如果使用 Swift Package，将以下内容加入 `Package.dependencies`：

```swift
.package(
    url: "https://github.com/CHANG-JUI-LIN/YueduCoreText",
    .upToNextMinor(from: "0.4.0")
)
```

再加入 target 的 `dependencies`：

```swift
.product(name: "YueduCoreText", package: "YueduCoreText")
```

0.x 的 minor 版本可能调整 public API；上述约束会保持在 0.4.x。只需要文字排印工具时，可改选 `YueduCoreTextTypography` 产品。

## 绘制第一页

以下完整函数参与 [Example.swift](Examples/StandaloneConsumer/Sources/Consumer/Example.swift) 的编译。在 main actor 中调用 `try await renderExample()`，即可取得 320 × 480 位图、源文本和链接区域；使用 `UIImage(cgImage:)` 可将图片交给 UIKit 显示。

```swift
import CoreGraphics
import UIKit
import YueduCoreText

@MainActor
public func renderExample() async throws -> (
    image: CGImage, text: String, links: [LinkInteractionRegion]
) {
    let size = CGSize(width: 320, height: 480)
    let document = HTMLLayoutDocument(
        html: "<p id='intro'>Hello <a href='#intro'>世界 🌕</a></p>",
        css: ["body { margin: 0; } p { margin: 0; padding: 8px; border: 2px solid blue; }"],
        configuration: BrowserLayoutConfig(
            renderWidth: size.width, renderHeight: size.height, rootFontSize: 17
        )
    )
    let session = try document.makePageSession()
    guard let page = try await session.layoutNextPage() else {
        throw HTMLLayoutError.layoutFailure("No first page")
    }
    let list = DisplayListBuilder.build(for: page, sourceText: session.sourceText)
    guard let context = CGContext(
        data: nil, width: Int(size.width), height: Int(size.height),
        bitsPerComponent: 8, bytesPerRow: Int(size.width) * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw HTMLLayoutError.layoutFailure("Bitmap allocation")
    }
    // A raw bitmap context needs top-left, y-down coordinates.
    // UIKit drawing contexts already use that orientation; do not flip them again.
    context.translateBy(x: 0, y: size.height)
    context.scaleBy(x: 1, y: -1)
    context.setFillColor(UIColor.white.cgColor)
    context.fill(CGRect(origin: .zero, size: size))
    list.draw(in: context)
    guard let image = context.makeImage() else {
        throw HTMLLayoutError.layoutFailure("Bitmap snapshot")
    }
    let links = LinkInteractionRegionSet.build(
        from: list, spineIndex: 0, anchors: session.pipelineLinkAnchors
    )
    return (image, session.sourceText, links.regions)
}
```

`layoutNextPage()` 每次返回一页，文档结束时返回 `nil`。保留 session 即可继续取页；`finish()` 会排完剩余页面。Display list 保留已生成的绘制结果，重绘时不会重新解析或排版。

示例采用一个 logical point 对应一个 pixel，正式界面可自行设置绘图倍率。`renderWidth`／`renderHeight` 是内容区大小；非零 `contentInsets` 会在外围增加留白，宿主的页面画布也要包含这些留白。

## 图片与连续滚动

将准备好的 `UIImage` 传给下面的示例。这些函数同样在 Example.swift 中编译，使用上方的 imports：

```swift
@MainActor
public func makeContinuousExample(image: UIImage) throws -> BrowserScrollDocument {
    let document = HTMLLayoutDocument(
        html: "<p id='start'>Hello 世界</p><img src='illustration.png' alt='Illustration'/>",
        css: ["body { margin: 0; } img { width: 120px; height: auto; }"],
        configuration: BrowserLayoutConfig(renderWidth: 320, renderHeight: 480),
        images: ["illustration.png": image]
    )
    return try document.prepareContinuous().makeDocument()
}

@MainActor
public func drawFirstViewport(of document: BrowserScrollDocument, in context: CGContext) {
    let viewport = CGRect(x: 0, y: 0, width: document.contentSize.width, height: 480)
    context.saveGState()
    defer { context.restoreGState() }
    context.clip(to: CGRect(origin: .zero, size: viewport.size))
    // The caller supplies a top-left, y-down context, as in renderExample().
    document.items(in: viewport).draw(in: context)
}
```

使用 `contentSize` 设置滚动容器。要绘制其他可见区域时，将它在**文档坐标**中的矩形传给 `items(in:)`；返回的 display list 已平移到该区域的局部原点，绘制时需要裁剪到 viewport。连续文档使用真正的连续排版，而不是拼接分页图片。

请在排版前准备资源：

- 便捷 initializer 接受有序的外部 CSS 字符串与图片字典；HTML 中的 inline style 与 `<style>` 由包解析。它不会替你下载 `<link>` 样式表或展开远程 `@import`。
- 图片先按原始 `src` 查找。如果提供 `baseURL`，也会使用解析后的绝对 URL 查找字典。这个便捷参数只用于图片 key，不是通用的样式表或链接重写服务。
- 需要样式表来源、顺序与加载失败信息时，使用 `CSSFrontendInput`、`AuthorStylesheet`，并通过 `imageLoader` 提供明确的资源查找。导入样式表及相对于 CSS 的资源 URL 应先由宿主处理。
- 自定义或内嵌字体由宿主注册；CSS family 需要映射时，提供 `BrowserLayoutConfig.fontResolver`。引擎不会自动下载或注册字体文件。

## 文字、链接与选区

| 需求 | API／约定 |
|---|---|
| 源文本 | `session.sourceText` 或 `continuous.sourceText` |
| 选区矩形 | `displayList.selectionRects(for: NSRange)` |
| 点击位置对应的文字 | `displayList.sourceRange(at:sourceText:)` |
| 链接区域 | `LinkInteractionRegionSet.build(from:spineIndex:anchors:)` |
| 锚点偏移 | `session.anchorOffsets` 或 `continuous.anchorOffsets` |
| 每页文字范围 | `BrowserPageGeometry.buildPageRanges(_:sourceText:)` |

所有文字偏移都指向经过空白折叠的 **sourceText，单位为 UTF-16**，不是 HTML 源代码偏移，也不是 Swift `String.count`。请使用 `NSString`／`NSRange` 处理。单文档示例的 `spineIndex: 0` 只是宿主提供的文档编号，不要求建立 EPUB 容器。

分页 display list 使用左上原点、y 轴向下的**页面坐标**；连续 display list 使用**文档坐标**；tile 查询结果使用 **tile 局部坐标**。宿主负责 view/window 坐标转换，命中测试与绘制必须使用相同坐标空间。Ruby 注音的几何信息映射到所属的正文范围。

## 支持范围

0.4.0 之后、尚未发布的英文出版 CSS 修复记录于 [English publishing CSS](docs/EnglishTypography.md)。0.4.0 tag 不包含这些变更。

| 项目 | 0.4.0 |
|---|---|
| 排版 | 横排与基础 vertical-rl block／inline flow、已支持的 px／em／% 尺寸、margin／padding、white-space 与 text-indent |
| 分页 | 增量分页 session、分页图片适配与连续文档排版 |
| 富内容 | 已支持的左右 float／clear、横排／vertical-rl 共用 ruby 子集、位图及包装位图的 SVG |
| 绘制 | 文字、图片、背景、边框与已支持的行内装饰 |
| 交互与语义 | 来源范围、锚点、链接／noteref、选区几何、已支持的脚注内容、媒体占位画面与作者标记的发音描述 |

以上是已实现的子集，不代表完整 CSS 兼容性。**目前不支持 table、flex/grid、定位排版、高级竖排 HTML 文档、通用矢量 SVG、MathML 与脚本。** Float／ruby 可接受的结构也有限制。高层文档 API 会检查能力并报告不支持的输入，不会暗中切换到 Reader 的其他后端。

EPUB ZIP／OPF／spine 管理、网络加载、阅读控件、手势、笔记存储与媒体／TTS 播放由你的 App 负责。**0.4.0** 加入基础 `vertical-rl` 文字排版与共用 ruby。请参考[参与编译的竖排示例](Examples/StandaloneConsumer/Sources/Consumer/VerticalExample.swift)与[支持范围及坐标契约](docs/VerticalLayout.md)。这个包不宣称完整 EPUB／CSS 兼容或与 DTCoreText 功能对等。

## 配置、错误与生命周期

`BrowserLayoutConfig` 提供内容尺寸／留白、基本字号／字体、颜色、间距、默认对齐及可选的字体 resolver。Viewport、资源或配置改变后，请建立新的 document／session；结果不会自动观察 App 设置。

- `makePageSession()` 与增量 session 受 **MainActor** 限制。异步取页 API 不代表会在后台执行。
- 连续排版在调用方的 serial executor 同步执行。Document、Core Text 对象与绘制应留在其所属 executor；结果有意不声明为 `Sendable`。
- 图片／字体 resolver 必须返回准备好的资源，不得阻塞等待异步 I/O。包没有自动网络加载器或全局文档引擎。
- `cancel()` 会阻止后续取页并释放尚未完成的 session 状态；已生成页面仍由使用方持有。宿主 generation 改变后，要丢弃过时结果。
- `HTMLLayoutError` 区分 `unsupported`、`resourceFailure`、`layoutFailure` 与 `cancelled`。底层 pipeline 也可能抛出 `BrowserLayoutFailure`，请一并处理其他错误。必需的 `<img>` 资源缺失或传入的样式表加载失败会报告错误；仅用于绘制的背景图缺失则可能被略过，请自行确认资源齐全。

进阶输入、所有权和 adapter 边界请见[集成指南（英文）](docs/EngineIntegration.md)。

## 其他产品与 API

- **YueduCoreTextTypography：** CJK 标点压缩、智能标点、竖排规范化／字形工具、拉丁文断字语言标记与 framesetter 创建。
- **YueduCoreText：** 另外提供 `ReaderContentMetrics`／`ReaderContentUnitMap`、`TextSelectionManager` 与 `ReaderPerfTrace`。名称含“Reader”不代表依赖 Yuedu Reader App。

`TextSelectionManager` 是可变状态，请限制在同一 actor 或 serial queue。性能跟踪只写入本机 Points of Interest signpost，不会上传；跟踪 metadata 不得包含文档文字、标题、URL 或个人数据。

## 示例、测试与已知限制

Clone 本 repo，使用 `xcrun simctl list devices available` 找到已安装的模拟器，将其 UUID 填入下方。不需要 Reader checkout。

```sh
export YUEDU_TEST_DESTINATION='platform=iOS Simulator,id=<simulator-uuid>'
xcodebuild -scheme YueduCoreText-Package \
  -destination "$YUEDU_TEST_DESTINATION" -parallel-testing-enabled NO test
cd Examples/StandaloneConsumer
xcodebuild -scheme YueduCoreTextConsumer \
  -destination "$YUEDU_TEST_DESTINATION" -parallel-testing-enabled NO test
```

示例是一个附带测试的小型 library，不是现成阅读器 App。它使用 repo 内的本地包；相同 public API 也可通过已发布的 0.4.0 获取。

CI 在 iOS Simulator 运行包与只使用 public API 的独立 consumer 测试，并保留 `.xcresult` 产物；已验证的版本、工具链与结果请见 [CI 运行记录](https://github.com/CHANG-JUI-LIN/YueduCoreText/actions)。本文档不宣称真机性能。

报告问题时，请[创建 issue](https://github.com/CHANG-JUI-LIN/YueduCoreText/issues)，提供最小 HTML／CSS、配置、包／Xcode／iOS 版本、预期结果与截图。只附上你有权分享的资源。

## 许可

[MPL-2.0](LICENSE)。源代码来源与依赖声明见 [ENGINE-NOTICE.md](ENGINE-NOTICE.md)。源代码许可不包含 Yuedu 名称及品牌使用权。
