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
    /// The chapter's admission evaluation, when layout starts from its style tree.
    private let evaluation: BrowserChapterEvaluation?

    public init(input: CSSFrontendInput, configuration: BrowserLayoutConfig,
                imageLoader: @escaping (String) -> UIImage? = { _ in nil }) {
        self.input = input
        self.configuration = configuration
        self.imageLoader = imageLoader
        self.evaluation = nil
    }

    /// Lays out from an evaluation's style tree instead of parsing the chapter again.
    /// `configuration` may add geometry, a font resolver or a diagnostic sink, but
    /// must keep the evaluation's cascade inputs: computed values were resolved for
    /// those, and a session must never lay out a stale tree under a changed font size.
    /// Defaults to the evaluation's own configuration.
    public init(evaluation: BrowserChapterEvaluation, configuration: BrowserLayoutConfig? = nil,
                imageLoader: @escaping (String) -> UIImage? = { _ in nil }) throws {
        let configuration = configuration ?? evaluation.configuration
        guard evaluation.accepts(configuration) else {
            assertionFailure("layout configuration differs from the evaluation's cascade inputs")
            throw HTMLLayoutError.layoutFailure("configuration differs from the evaluation's cascade inputs")
        }
        self.input = evaluation.document.input
        self.configuration = configuration
        self.imageLoader = imageLoader
        self.evaluation = evaluation
    }

    private func makePipelineDocument() -> BrowserLayoutDocument {
        BrowserLayoutDocument(input: input, config: configuration, imageLoader: imageLoader,
                              preparedFrontend: evaluation?.preparedFrontend)
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
        evaluation?.capabilities
            ?? BrowserLayoutCapabilityScanner.scan(input: input, writingMode: configuration.writingMode)
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
        if let evaluation {
            return try BrowserLayoutSession(evaluation: evaluation, configuration: configuration,
                                            imageLoader: imageLoader, generation: generation)
        }
        return BrowserLayoutSession(input: input, config: configuration,
                                    imageLoader: imageLoader, generation: generation)
    }

    func makeViewportSessionImpl(validateCapabilities: Bool) throws -> BrowserViewportSession {
        if validateCapabilities { try validate() }
        guard configuration.writingMode == .horizontal else {
            throw HTMLLayoutError.unsupported([.verticalWritingMode])
        }
        if Task.isCancelled { throw HTMLLayoutError.cancelled }
        var metrics = LayoutMetrics()
        let pipeline = try makePipelineDocument()
            .makeLayout(containerSize: CGSize(width: configuration.renderWidth + configuration.contentInsets.left + configuration.contentInsets.right,
                                              height: configuration.renderHeight + configuration.contentInsets.top + configuration.contentInsets.bottom),
                        metrics: &metrics, performLayout: false)
        return BrowserViewportSession(pipeline: pipeline, configuration: configuration, imageLoader: imageLoader)
    }

    /// Continuous preparation permits loading a computed background after parsing, before paint.
    public func prepareContinuous(validateCapabilities: Bool = true) throws -> BrowserContinuousLayout {
        if validateCapabilities { try validate() }
        if Task.isCancelled { throw HTMLLayoutError.cancelled }
        let size = CGSize(width: configuration.renderWidth + configuration.contentInsets.left + configuration.contentInsets.right,
                          height: configuration.renderHeight + configuration.contentInsets.top + configuration.contentInsets.bottom)
        let pipeline = try makePipelineDocument()
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
    public var pageBackground: BrowserPageBackground? {
        BrowserPageBackground(BrowserLayoutDocument.bodyBackground(rootBox: pipeline.rootBox))
    }
    public var footnotes: [String: String] { pipeline.footnotes }
    public var mediaAttachments: [Int: EPUBMediaAttachment] { pipeline.mediaAttachments }
    public var pronunciationHints: [TTSPronunciationHint] { pipeline.pronunciationHints }
    public var paragraphRanges: [NSRange] { BrowserLayoutSemanticContent.paragraphRanges(in: pipeline.rootBox) }

    init(pipeline: BrowserLayoutDocument.BrowserLayoutPipelineResult,
         configuration: BrowserLayoutConfig, imageLoader: @escaping (String) -> UIImage?) {
        self.pipeline = pipeline; self.configuration = configuration; self.imageLoader = imageLoader
    }

    /// `paintsPageBackground: false` leaves the html/body background out of the
    /// display list for a host that draws `pageBackground` itself, across the
    /// whole screen. The chapter still gets at least one screen of height for it.
    public func makeDocument(estimatedContentHeight: CGFloat? = nil,
                             paintsPageBackground: Bool = true) -> BrowserScrollDocument {
        let config = configuration
        let background = BrowserLayoutDocument.bodyBackground(rootBox: pipeline.rootBox)
        let flow = BrowserScrollDocument.make(pipeline: pipeline, contentWidth: config.renderWidth,
                                             contentInsets: config.contentInsets, writingMode: config.writingMode)
        let hasBackdrop = background.color != nil || background.image != nil
        let extent = max(flow.contentHeight, estimatedContentHeight ?? 0)
        let height = hasBackdrop ? max(config.renderHeight, extent) : extent
        let canvas = CGRect(x: 0, y: 0, width: flow.contentWidth, height: height)
        var items: [DisplayItem] = []
        if paintsPageBackground, let color = background.color {
            items.append(.fill(DisplayFillItem(rect: PageLocalRect(rawValue: canvas), color: color,
                cornerRadius: 0, borderTop: .zero, borderBottom: .zero, borderLeft: .zero,
                borderRight: .zero, nodeID: -1, writingMode: config.writingMode, isBackgroundPaint: true)))
        }
        if paintsPageBackground, let backgroundImage = background.image, let image = imageLoader(backgroundImage.source) {
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
                     textPaintPhase: TextPaintPhase = .all,
                     textDecoration: ((CTLine, NSAttributedString, CGContext) -> Void)? = nil) {
        UIGraphicsPushContext(context)
        defer { UIGraphicsPopContext() }
        DisplayListDrawer.draw(self, in: context, skipAuthoredBackgroundPaint: skipAuthoredBackgroundPaint,
                               textPaintPhase: textPaintPhase,
                               textDecoration: textDecoration)
    }
    public func selectionRects(for range: NSRange) -> [CGRect] { BrowserTextGeometry.rects(in: self, range: range) }
    public func sourceRange(at point: CGPoint, sourceText: String) -> NSRange? {
        BrowserTextGeometry.range(at: point, in: self, source: sourceText as NSString)
    }
}
