import Foundation

/// Shaping metadata, scoped to each attributed run; never inferred from script.
enum TextBreakingAttributes {
    static let hyphens = NSAttributedString.Key("YueduCSSHyphens")
    static let language = NSAttributedString.Key("YueduContentLanguage")
    static let emergency = NSAttributedString.Key("YueduEmergencyWrap")
    static let visibleHyphen = NSAttributedString.Key("YueduVisibleHyphen")
    /// `white-space: nowrap` text: no soft wrap opportunity between two of
    /// its characters. Its edges stay opportunities, as the boundary's nearest
    /// common ancestor decides (CSS Text 3 §5.1).
    static let noWrap = NSAttributedString.Key("YueduNoWrap")
}
