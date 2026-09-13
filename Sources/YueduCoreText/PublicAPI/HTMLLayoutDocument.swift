import UIKit
import CoreText

public enum HTMLLayoutError: Error {
    case unsupported([UnsupportedFeature])
    case resourceFailure(String)
    case layoutFailure(String)
    case cancelled
}

/// A document-owned HTML/CSS pipeline. Resources are prepared by the consumer.
/// Use on one serial executor; results retain CTLine artifacts and are not Sendable.
/// Paged incremental sessions retain their existing MainActor confinement.
public final class HTMLLayoutDocument {
    private let input: CSSFrontendInput
    private let configuration: BrowserLayoutConfig
    private let imageLoader: (String) -> UIImage?

    public init(input: CSSFrontendInput, configuration: BrowserLayoutConfig,
                imageLoader: @escaping (String) -> UIImage? = { _ in nil }) {
        self.input = input
        self.configuration = configuration
        self.imageLoader = imageLoader
    }

    public convenience init(html: String, css: [String] = [], baseURL: URL? = nil,
                            configuration: BrowserLayoutConfig = .init(),
                            images: [String: UIImage] = [:]) {
        self.init(input: .currentCompatibility(html: html, cssTexts: css), configuration: configuration) { source in
            images[source] ?? baseURL.flatMap { base in
                URL(string: source, relativeTo: base).flatMap { images[$0.absoluteURL.absoluteString] }
            }
        }
    }

    /// Same capability parser/cascade as production; reports facts without choosing a fallback.
    public func capabilities() -> BrowserLayoutCapabilityResult {
        BrowserLayoutCapabilityScanner.scan(input: input, writingMode: configuration.writingMode)
    }

    private func validate() throws {
        if Task.isCancelled { throw HTMLLayoutError.cancelled }
        if let failure = input.stylesheets.first(where: \.loadFailed) {
            throw HTMLLayoutError.resourceFailure(failure.identity.label)
        }
        for source in try HTMLResourceReferences.imageSources(in: input.html) {
            guard imageLoader(source) != nil else { throw HTMLLayoutError.resourceFailure(source) }
        }
        let result = capabilities()
        guard result.supported else { throw HTMLLayoutError.unsupported(result.unsupportedFeatures) }
    }

    @MainActor
    public func makePageSession(generation: Int = 0) throws -> BrowserLayoutSession {
        try validate()
        return BrowserLayoutSession(input: input, config: configuration,
                                    imageLoader: imageLoader, generation: generation)
    }

    /// Continuous preparation permits loading a computed background after parsing, before paint.
    public func prepareContinuous(validateCapabilities: Bool = true) throws -> BrowserContinuousLayout {
        if validateCapabilities { try validate() }
        if Task.isCancelled { throw HTMLLayoutError.cancelled }
        let size = CGSize(width: configuration.renderWidth + configuration.contentInsets.left + configuration.contentInsets.right,
                          height: configuration.renderHeight + configuration.contentInsets.top + configuration.contentInsets.bottom)
        let pipeline = try BrowserLayoutDocument(input: input, config: configuration, imageLoader: imageLoader)
            .makeLayout(containerSize: size)
        return BrowserContinuousLayout(pipeline: pipeline, configuration: configuration, imageLoader: imageLoader)
    }
}

/// Prepared continuous geometry; does not expose the mutable internal box tree.
public final class BrowserContinuousLayout {
    private let pipeline: BrowserLayoutDocument.BrowserLayoutPipelineResult
    private let configuration: BrowserLayoutConfig
    private let imageLoader: (String) -> UIImage?
    public var backgroundImageSource: String? { BrowserLayoutDocument.bodyBackground(rootBox: pipeline.rootBox).image?.source }
    public var footnotes: [String: String] { pipeline.footnotes }
    public var mediaAttachments: [Int: EPUBMediaAttachment] { pipeline.mediaAttachments }
    public var pronunciationHints: [TTSPronunciationHint] { pipeline.pronunciationHints }
    public var paragraphRanges: [NSRange] { BrowserLayoutSemanticContent.paragraphRanges(in: pipeline.rootBox) }

    init(pipeline: BrowserLayoutDocument.BrowserLayoutPipelineResult,
         configuration: BrowserLayoutConfig, imageLoader: @escaping (String) -> UIImage?) {
        self.pipeline = pipeline; self.configuration = configuration; self.imageLoader = imageLoader
    }

    public func makeDocument() -> BrowserScrollDocument {
        let config = configuration
        let background = BrowserLayoutDocument.bodyBackground(rootBox: pipeline.rootBox)
        let flow = BrowserScrollDocument.make(pipeline: pipeline, contentWidth: config.renderWidth,
                                             contentInsets: config.contentInsets, writingMode: config.writingMode)
        let hasBackdrop = background.color != nil || background.image != nil
        let height = hasBackdrop ? max(config.renderHeight, flow.contentHeight) : flow.contentHeight
        let canvas = CGRect(x: 0, y: 0, width: flow.contentWidth, height: height)
        var items: [DisplayItem] = []
        if let color = background.color {
            items.append(.fill(DisplayFillItem(rect: PageLocalRect(rawValue: canvas), color: color,
                cornerRadius: 0, borderTop: .zero, borderBottom: .zero, borderLeft: .zero,
                borderRight: .zero, nodeID: -1, writingMode: config.writingMode, isBackgroundPaint: true)))
        }
        if let backgroundImage = background.image, let image = imageLoader(backgroundImage.source) {
            items.append(.image(DisplayImageItem(source: backgroundImage.source, image: image,
                sourceRange: NSRange(location: 0, length: 0), nodeID: -1, linkTarget: nil,
                writingMode: config.writingMode, rect: PageLocalRect(rawValue: BrowserLayoutDocument.coverRect(
                    for: image.size, container: canvas.size, positionX: backgroundImage.positionX,
                    positionY: backgroundImage.positionY)), alt: nil, isBackgroundPaint: true)))
        }
        items.append(contentsOf: flow.displayList.items)
        return BrowserScrollDocument(displayList: DisplayList(items: items),
            contentHeight: height, sourceText: flow.sourceText,
            anchorOffsets: flow.anchorOffsets, linkAnchors: flow.linkAnchors, contentWidth: canvas.width)
    }
}

extension DisplayList {
    /// CGContext uses top-left, y-down coordinates. The caller establishes scale/translation.
    /// No layout or parsing occurs here. A scroll tile uses items(in:) then this method.
    public func draw(in context: CGContext, skipAuthoredBackgroundPaint: Bool = false,
                     textDecoration: ((CTLine, NSAttributedString, CGContext) -> Void)? = nil) {
        UIGraphicsPushContext(context)
        defer { UIGraphicsPopContext() }
        DisplayListDrawer.draw(self, in: context, skipAuthoredBackgroundPaint: skipAuthoredBackgroundPaint,
                               textDecoration: textDecoration)
    }
    public func selectionRects(for range: NSRange) -> [CGRect] { BrowserTextGeometry.rects(in: self, range: range) }
    public func sourceRange(at point: CGPoint, sourceText: String) -> NSRange? {
        BrowserTextGeometry.range(at: point, in: self, source: sourceText as NSString)
    }
}
