import Foundation

public enum BrowserLayoutFailure: Error {
    case emptyBody
    case unsupportedFrontendCapabilities
    case unsupportedFloatFragmentation(nodeID: Int)
    case unsupportedRubySubset
    case unsupportedTextIndentSubset
}
