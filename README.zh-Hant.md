# YueduCoreText

[English](README.md) · [繁體中文](README.zh-Hant.md) · [简体中文](README.zh-Hans.md)

**以 Core Text 為核心的 iOS 原生 HTML/CSS 排版與繪製引擎。**

將 HTML/XHTML、CSS 與準備好的資源轉成分頁結果或連續文件，畫進 `CGContext`，並查詢文字、連結與選取範圍的幾何資訊。整合時不需要 Yuedu Reader 原始碼，也不需要 WebView。

適合需要自行掌握繪製與互動的原生文件或閱讀介面。你的 App 提供資源、承載畫面；套件負責解析、計算樣式、排版、分頁與繪製。

[0.3.0 版本](https://github.com/CHANG-JUI-LIN/YueduCoreText/releases/tag/0.3.0) · [可執行範例](Examples/StandaloneConsumer) · [進階整合指南（英文）](docs/EngineIntegration.md) · [更新紀錄](CHANGELOG.md)

## 環境要求與安裝

- iOS 17+、Swift tools 6.0+、Xcode 16+。需要 UIKit、Core Text 與 Core Graphics；這是 iOS 套件。
- HTML/CSS 引擎從 **0.3.0** 開始提供。0.2.1 及更早版本只有原有工具 API。
- 主產品依賴 `YueduCoreTextTypography` 與 **SwiftSoup 2.13.7**。

在 Xcode 選擇 **File → Add Package Dependencies**，輸入 `https://github.com/CHANG-JUI-LIN/YueduCoreText`，將 **YueduCoreText** 產品加入你的 target。使用 0.3.x 時，選擇 **Up to Next Minor Version**，起始版本填 **0.3.0**。

若使用 Swift Package，將以下內容加入 `Package.dependencies`：

```swift
.package(
    url: "https://github.com/CHANG-JUI-LIN/YueduCoreText",
    .upToNextMinor(from: "0.3.0")
)
```

再加入 target 的 `dependencies`：

```swift
.product(name: "YueduCoreText", package: "YueduCoreText")
```

0.x 的 minor 版本可能調整 public API；上述限制會維持在 0.3.x。只需要文字排印工具時，可改選 `YueduCoreTextTypography` 產品。

## 畫出第一頁

以下完整函式參與 [Example.swift](Examples/StandaloneConsumer/Sources/Consumer/Example.swift) 的編譯。在 main actor 中呼叫 `try await renderExample()`，即可取得 320 × 480 bitmap、來源文字與連結區域；使用 `UIImage(cgImage:)` 可將圖片交給 UIKit 顯示。

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

`layoutNextPage()` 每次回傳一頁，文件結束時回傳 `nil`。保留 session 即可繼續取頁；`finish()` 會排完剩餘頁面。Display list 保留已產生的繪製結果，重畫時不會重新解析或排版。

範例採用一個 logical point 對應一個 pixel，正式介面可自行設定繪圖倍率。`renderWidth`／`renderHeight` 是內容區大小；非零 `contentInsets` 會在外圍增加留白，宿主的頁面畫布也要包含這些留白。

## 圖片與連續捲動

將準備好的 `UIImage` 傳給下列範例。這些函式同樣在 Example.swift 中編譯，使用上方的 imports：

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

使用 `contentSize` 設定捲動容器。要畫其他可見區域時，將它在**文件座標**中的矩形傳給 `items(in:)`；回傳的 display list 已平移到該區域的局部原點，繪製時需裁切到 viewport。連續文件使用真正的連續排版，並非拼接分頁圖片。

請在排版前準備資源：

- 便利 initializer 接受有順序的外部 CSS 字串與圖片字典；HTML 中的 inline style 與 `<style>` 由套件解析。它不會代你下載 `<link>` 樣式表或展開遠端 `@import`。
- 圖片先以原始 `src` 查找。若提供 `baseURL`，也會用解析後的絕對 URL 查找字典。這個便利參數只用於圖片 key，不是通用的樣式表或連結改寫服務。
- 需要樣式表來源、順序與載入失敗資訊時，使用 `CSSFrontendInput`、`AuthorStylesheet`，並透過 `imageLoader` 提供明確的資源查找。匯入樣式表與相對於 CSS 的資源 URL 應先由宿主處理。
- 自訂或內嵌字型由宿主註冊；CSS family 需要映射時，提供 `BrowserLayoutConfig.fontResolver`。引擎不會自動下載或註冊字型檔。

## 文字、連結與選取

| 需求 | API／契約 |
|---|---|
| 來源文字 | `session.sourceText` 或 `continuous.sourceText` |
| 選取矩形 | `displayList.selectionRects(for: NSRange)` |
| 點擊位置對應的文字 | `displayList.sourceRange(at:sourceText:)` |
| 連結區域 | `LinkInteractionRegionSet.build(from:spineIndex:anchors:)` |
| Anchor 位移 | `session.anchorOffsets` 或 `continuous.anchorOffsets` |
| 每頁文字範圍 | `BrowserPageGeometry.buildPageRanges(_:sourceText:)` |

所有文字位移都指向經過空白折疊的 **sourceText，單位為 UTF-16**，不是 HTML 原始碼位移，也不是 Swift `String.count`。請使用 `NSString`／`NSRange` 處理。單文件範例的 `spineIndex: 0` 只是宿主提供的文件編號，不要求建立 EPUB 容器。

分頁 display list 使用左上原點、y 軸向下的**頁面座標**；連續 display list 使用**文件座標**；tile 查詢結果使用 **tile 局部座標**。宿主負責 view/window 座標轉換，命中測試與繪製必須使用相同座標空間。Ruby 註音的幾何資訊映射到所屬的正文範圍。

## 支援範圍

| 項目 | 0.3.x 已提供 |
|---|---|
| 排版 | 橫排 block／inline flow、已支援的 px／em／% 尺寸、margin／padding、white-space 與 text-indent |
| 分頁 | 增量分頁 session、分頁圖片適配與連續文件排版 |
| 豐富內容 | 已支援的左右 float／clear、橫排 ruby 子集、點陣圖片及包裝點陣圖片的 SVG |
| 繪製 | 文字、圖片、背景、邊框與已支援的行內裝飾 |
| 互動與語意 | 來源範圍、anchor、連結／noteref、選取幾何、已支援的註腳內容、媒體預留畫面與作者標記的發音描述 |

以上是實作子集，不代表完整 CSS 相容性。**目前不支援 table、flex/grid、定位排版、直排 HTML 文件、通用向量 SVG、MathML 與腳本。** Float／ruby 可接受的結構也有限制。高階文件 API 會檢查能力並回報不支援的輸入，不會暗中切換到 Reader 的其他後端。

EPUB ZIP／OPF／spine 管理、網路載入、閱讀控制項、手勢、筆記儲存與媒體／TTS 播放由你的 App 負責。Typography 的直排文字工具**不表示**引擎支援直排 HTML。此套件不宣稱完整 EPUB／CSS 相容或與 DTCoreText 功能對等。

## 設定、錯誤與生命週期

`BrowserLayoutConfig` 提供內容尺寸／留白、基本字級／字型、顏色、間距、預設對齊及可選的字型 resolver。Viewport、資源或設定改變後，請建立新的 document／session；結果不會自動觀察 App 設定。

- `makePageSession()` 與增量 session 受 **MainActor** 限制。非同步取頁 API 不代表會在背景執行。
- 連續排版在呼叫端的 serial executor 同步執行。Document、Core Text 物件與繪製應留在其所屬 executor；結果刻意不宣告為 `Sendable`。
- 圖片／字型 resolver 必須回傳已準備好的資源，不得阻塞等待非同步 I/O。套件沒有自動網路載入器或全域文件引擎。
- `cancel()` 會阻止後續取頁並釋放尚未完成的 session 狀態；已產生頁面仍由使用端持有。宿主 generation 改變後，要丟棄過時結果。
- `HTMLLayoutError` 區分 `unsupported`、`resourceFailure`、`layoutFailure` 與 `cancelled`。底層 pipeline 也可能拋出 `BrowserLayoutFailure`，請一併處理其餘錯誤。必需的 `<img>` 資源缺失或傳入的樣式表載入失敗會回報錯誤；僅用於繪製的背景圖缺失則可能被略過，請自行確認資源齊全。

進階輸入、所有權與 adapter 邊界請見[整合指南（英文）](docs/EngineIntegration.md)。

## 其他產品與 API

- **YueduCoreTextTypography：** CJK 標點壓縮、智慧標點、直排正規化／字形工具、拉丁文斷字語言標記與 framesetter 建立。
- **YueduCoreText：** 另外提供 `ReaderContentMetrics`／`ReaderContentUnitMap`、`TextSelectionManager` 與 `ReaderPerfTrace`。名稱含「Reader」不代表依賴 Yuedu Reader App。

`TextSelectionManager` 為可變狀態，請限制在同一 actor 或 serial queue。效能追蹤只寫入本機 Points of Interest signpost，不會上傳；追蹤 metadata 不得包含文件文字、標題、URL 或個人資料。

## 範例、測試與已知限制

Clone 本 repo，使用 `xcrun simctl list devices available` 找到已安裝的模擬器，將其 UUID 填入下方。不需要 Reader checkout。

```sh
export YUEDU_TEST_DESTINATION='platform=iOS Simulator,id=<simulator-uuid>'
xcodebuild -scheme YueduCoreText-Package \
  -destination "$YUEDU_TEST_DESTINATION" -parallel-testing-enabled NO test
cd Examples/StandaloneConsumer
xcodebuild -scheme YueduCoreTextConsumer \
  -destination "$YUEDU_TEST_DESTINATION" -parallel-testing-enabled NO test
```

範例是一個附測試的小型 library，不是現成閱讀器 App。它使用 repo 內的本機套件；相同 public API 也可透過已發布的 0.3.0 取得。

發布驗證在 Xcode 27 beta／iOS Simulator 27 通過 128 項套件測試與 5 項獨立 consumer 測試。**Xcode 16.4 CI 尚未全綠：**既有 Typography 測試 `punctuationStillCompressesWhenSafe` 得到 `kern == -20`，但 assertion 預期 `> -20`。0.2.1 也有相同失敗，詳見 [0.3.0 CI](https://github.com/CHANG-JUI-LIN/YueduCoreText/actions/runs/34691996249) 與[基線](https://github.com/CHANG-JUI-LIN/YueduCoreText/actions/runs/30687257480)。本文件不宣稱真機效能。

回報問題時，請[建立 issue](https://github.com/CHANG-JUI-LIN/YueduCoreText/issues)，提供最小 HTML／CSS、設定、套件／Xcode／iOS 版本、預期結果與截圖。只附上你有權分享的資源。

## 授權

[MPL-2.0](LICENSE)。原始碼來源與依賴聲明見 [ENGINE-NOTICE.md](ENGINE-NOTICE.md)。原始碼授權不包含 Yuedu 名稱及品牌使用權。
