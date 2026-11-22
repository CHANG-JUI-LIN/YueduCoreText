import Foundation

public enum BrowserLayoutFailure: Error {
    case emptyBody
    case unsupportedFrontendCapabilities
    case unsupportedRubySubset
    case unsupportedTextIndentSubset
}
