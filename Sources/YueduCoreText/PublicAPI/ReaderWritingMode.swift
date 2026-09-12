import Foundation

public enum ReaderWritingMode: String, CaseIterable, Codable, Sendable {
    case horizontal
    case verticalRTL
    public var isVertical: Bool { self == .verticalRTL }
}
