import Foundation

public enum EPUBMediaKind: String, Codable, Equatable, Sendable {
    case audio
    case video
}

public struct EPUBMediaAttachment: Codable, Equatable, Sendable {
    public let kind: EPUBMediaKind
    public let sourceHref: String
    public let mediaType: String?
    public let title: String?
    public let posterHref: String?

    public init(
        kind: EPUBMediaKind,
        sourceHref: String,
        mediaType: String? = nil,
        title: String? = nil,
        posterHref: String? = nil
    ) {
        self.kind = kind
        self.sourceHref = sourceHref
        self.mediaType = mediaType
        self.title = title
        self.posterHref = posterHref
    }
}
