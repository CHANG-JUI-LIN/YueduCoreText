import Foundation
import os

/// A stable stage in the reader pipeline that can be measured with Points of Interest.
public enum ReaderPerfStage: String, CaseIterable, Sendable {
    case chapterLoad = "chapter.load"
    case htmlParse = "html.parse"
    case cssCollect = "css.collect"
    case cssParse = "css.parse"
    case cssMatch = "css.match"
    case astBuild = "ast.build"
    case irConvert = "ir.convert"
    case attributedRender = "attributed.render"
    case imageLoad = "resource.image.load"
    case imageDecode = "resource.image.decode"
    case layoutFingerprint = "layout.fingerprint"
    case layoutVerticalPrepare = "layout.vertical.prepare"
    case layoutFramesetterCreate = "layout.framesetter.create"
    case layoutPageRanges = "layout.pageRanges"
    case layoutDisplayList = "layout.displayList"
    case layoutFirstPagePublish = "layout.firstPage.publish"
    case renderPage = "render.page"
    case renderChunk = "render.chunk"
    case renderTile = "render.tile"
    case cacheDocument = "cache.document"
    case cacheLayout = "cache.layout"
    case cacheRaster = "cache.raster"

    /// The static interval name written to Points of Interest.
    ///
    /// This value always contains the same text as `rawValue`.
    public var signpostName: StaticString {
        switch self {
        case .chapterLoad: "chapter.load"
        case .htmlParse: "html.parse"
        case .cssCollect: "css.collect"
        case .cssParse: "css.parse"
        case .cssMatch: "css.match"
        case .astBuild: "ast.build"
        case .irConvert: "ir.convert"
        case .attributedRender: "attributed.render"
        case .imageLoad: "resource.image.load"
        case .imageDecode: "resource.image.decode"
        case .layoutFingerprint: "layout.fingerprint"
        case .layoutVerticalPrepare: "layout.vertical.prepare"
        case .layoutFramesetterCreate: "layout.framesetter.create"
        case .layoutPageRanges: "layout.pageRanges"
        case .layoutDisplayList: "layout.displayList"
        case .layoutFirstPagePublish: "layout.firstPage.publish"
        case .renderPage: "render.page"
        case .renderChunk: "render.chunk"
        case .renderTile: "render.tile"
        case .cacheDocument: "cache.document"
        case .cacheLayout: "cache.layout"
        case .cacheRaster: "cache.raster"
        }
    }
}

/// Bounded, content-free metadata attached to a reader performance trace.
///
/// Never place a book title, book or chapter text, a URL, personal data, or
/// other user content in these fields. ``ReaderPerfTrace`` writes this metadata
/// only to the device's local Points of Interest log and does not upload
/// telemetry.
public struct ReaderPerfMetadata: Sendable {
    public var resourceID: String?
    public var spineIndex: Int?
    public var characterCount: Int?
    public var elementCount: Int?
    public var ruleCount: Int?
    public var pageCount: Int?
    public var chunkCount: Int?
    public var writingMode: String?
    public var cacheResult: String?
    public var executor: String?
    public var generation: Int?

    public init(
        resourceID: String? = nil,
        spineIndex: Int? = nil,
        characterCount: Int? = nil,
        elementCount: Int? = nil,
        ruleCount: Int? = nil,
        pageCount: Int? = nil,
        chunkCount: Int? = nil,
        writingMode: String? = nil,
        cacheResult: String? = nil,
        executor: String? = nil,
        generation: Int? = nil
    ) {
        self.resourceID = resourceID
        self.spineIndex = spineIndex
        self.characterCount = characterCount
        self.elementCount = elementCount
        self.ruleCount = ruleCount
        self.pageCount = pageCount
        self.chunkCount = chunkCount
        self.writingMode = writingMode
        self.cacheResult = cacheResult
        self.executor = executor
        self.generation = generation
    }

    /// A deterministic, space-delimited description containing non-nil fields.
    public var logDescription: String {
        var fields: [String] = []
        if let resourceID { fields.append("resource=\(resourceID)") }
        if let spineIndex { fields.append("spine=\(spineIndex)") }
        if let characterCount { fields.append("chars=\(characterCount)") }
        if let elementCount { fields.append("elements=\(elementCount)") }
        if let ruleCount { fields.append("rules=\(ruleCount)") }
        if let pageCount { fields.append("pages=\(pageCount)") }
        if let chunkCount { fields.append("chunks=\(chunkCount)") }
        if let writingMode { fields.append("writing=\(writingMode)") }
        if let cacheResult { fields.append("cache=\(cacheResult)") }
        if let executor { fields.append("executor=\(executor)") }
        if let generation { fields.append("generation=\(generation)") }
        return fields.joined(separator: " ")
    }
}

/// Local Points-of-Interest instrumentation for the reader pipeline.
///
/// This API writes signposts only to the device's local Points of Interest log.
/// It does not collect or upload analytics, network data, or other telemetry.
public enum ReaderPerfTrace {
    private static let signposter = OSSignposter(
        subsystem: Bundle.main.bundleIdentifier ?? "com.zhangruilin.yuedureader",
        category: "ReaderPerformance"
    )

    /// An opaque interval returned by ``begin(_:metadata:)``.
    public struct Interval: Sendable {
        fileprivate let stage: ReaderPerfStage
        fileprivate let state: OSSignpostIntervalState
    }

    /// Starts a Points-of-Interest interval when signposting is enabled.
    public static func begin(
        _ stage: ReaderPerfStage,
        metadata: @autoclosure () -> ReaderPerfMetadata = ReaderPerfMetadata()
    ) -> Interval? {
        guard signposter.isEnabled else { return nil }
        let logDescription = metadata().logDescription
        let state = signposter.beginInterval(
            stage.signpostName,
            id: signposter.makeSignpostID(),
            "\(logDescription, privacy: .public)"
        )
        return Interval(stage: stage, state: state)
    }

    /// Ends a previously started Points-of-Interest interval.
    public static func end(
        _ interval: Interval?,
        metadata: @autoclosure () -> ReaderPerfMetadata? = nil
    ) {
        guard let interval else { return }
        if let metadata = metadata() {
            signposter.endInterval(
                interval.stage.signpostName,
                interval.state,
                "\(metadata.logDescription, privacy: .public)"
            )
        } else {
            signposter.endInterval(interval.stage.signpostName, interval.state)
        }
    }

    /// Measures a synchronous operation and returns its result.
    @discardableResult
    public static func span<T>(
        _ stage: ReaderPerfStage,
        metadata: @autoclosure () -> ReaderPerfMetadata = ReaderPerfMetadata(),
        _ body: () throws -> T
    ) rethrows -> T {
        guard signposter.isEnabled else { return try body() }
        let interval = begin(stage, metadata: metadata())
        defer { end(interval) }
        return try body()
    }

    /// Measures an asynchronous operation and returns its result.
    @discardableResult
    public static func spanAsync<T>(
        _ stage: ReaderPerfStage,
        metadata: @autoclosure () -> ReaderPerfMetadata = ReaderPerfMetadata(),
        isolation: isolated (any Actor)? = #isolation,
        _ body: () async throws -> T
    ) async rethrows -> T {
        guard signposter.isEnabled else { return try await body() }
        let interval = begin(stage, metadata: metadata())
        defer { end(interval) }
        return try await body()
    }
}
