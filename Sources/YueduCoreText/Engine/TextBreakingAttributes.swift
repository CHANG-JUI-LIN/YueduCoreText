import Foundation

/// Shaping metadata, scoped to each attributed run; never inferred from script.
enum TextBreakingAttributes {
    static let hyphens = NSAttributedString.Key("YueduCSSHyphens")
    static let language = NSAttributedString.Key("YueduContentLanguage")
    static let emergency = NSAttributedString.Key("YueduEmergencyWrap")
    static let visibleHyphen = NSAttributedString.Key("YueduVisibleHyphen")
}
