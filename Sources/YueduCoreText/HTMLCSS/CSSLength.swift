import CoreGraphics
import Foundation

/// One CSS length *value*. Percentages are kept symbolic (0…1) so the layout
/// stage can resolve them against the real containing-block width; `em`/`rem`
/// are resolved against font sizes at computed-value time.
public enum CSSLength: Equatable, Sendable {
    case px(CGFloat)
    case pt(CGFloat)
    case em(CGFloat)
    case rem(CGFloat)
    case percent(CGFloat)   // 0.0…1.0 of the containing block
    case vh(CGFloat)        // 0.0…1.0 of the viewport height
    case vw(CGFloat)        // 0.0…1.0 of the viewport width
    case auto
    /// `calc()` of lengths and percentages added and subtracted. Out of line: a style holds
    /// dozens of lengths and is copied by value throughout layout, so the common cases stay
    /// one word and a tag.
    indirect case calc(CSSCalc)
}

/// A sum of lengths: what `calc(100% - 110px)` computes to. `pt` is folded into `px`.
public struct CSSCalc: Equatable, Sendable {
    public var px: CGFloat = 0
    public var em: CGFloat = 0
    public var rem: CGFloat = 0
    /// 0.0…1.0 of the containing block.
    public var percent: CGFloat = 0
    public var vh: CGFloat = 0
    public var vw: CGFloat = 0

    public init() {}

    mutating func add(_ length: CSSLength, sign: CGFloat) -> Bool {
        switch length {
        case .px(let v): px += sign * v
        case .pt(let v): px += sign * v * 96.0 / 72.0
        case .em(let v): em += sign * v
        case .rem(let v): rem += sign * v
        case .percent(let v): percent += sign * v
        case .vh(let v): vh += sign * v
        case .vw(let v): vw += sign * v
        case .auto, .calc: return false
        }
        return true
    }
}

public enum CSSLengthResolver {
    /// Parses a single CSS length token. Unsupported modern syntax
    /// (`calc()`, `min()`, `max()`, `clamp()`) returns nil → callers treat as
    /// the property's initial value. That is the intended Phase-1 behavior:
    /// authored `calc()` is *ignored*, never guessed.
    public static func parse(_ raw: String) -> CSSLength? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !s.isEmpty else { return nil }
        if s == "auto" { return .auto }
        switch s {
        case "0", "0.0": return .px(0)
        default: break
        }
        if s.hasSuffix("%") {
            guard let v = Double(s.dropLast()) else { return nil }
            return .percent(CGFloat(v) / 100)
        }
        if s.hasSuffix("vh") {
            guard let v = Double(s.dropLast(2)) else { return nil }
            return .vh(CGFloat(v) / 100)
        }
        if s.hasSuffix("vw") {
            guard let v = Double(s.dropLast(2)) else { return nil }
            return .vw(CGFloat(v) / 100)
        }
        if s.hasSuffix("px") {
            guard let v = Double(s.dropLast(2)) else { return nil }
            return .px(CGFloat(v))
        }
        if s.hasSuffix("pt") {
            guard let v = Double(s.dropLast(2)) else { return nil }
            return .pt(CGFloat(v))
        }
        if s.hasSuffix("rem") {
            guard let v = Double(s.dropLast(3)) else { return nil }
            return .rem(CGFloat(v))
        }
        if s.hasSuffix("em") {
            guard let v = Double(s.dropLast(2)) else { return nil }
            return .em(CGFloat(v))
        }
        if let v = Double(s) { return .px(CGFloat(v)) } // unitless → px
        return nil
    }

    /// `calc()` whose terms are lengths and percentages joined by ` + ` and ` - ` (CSS requires
    /// the spaces). Anything else — products, quotients, nested functions, `min()`, `max()`,
    /// `clamp()` — is nil, and the capability scanner reports the declaration. Kept apart
    /// from `parse`: only the properties whose percentage base layout knows ask for it.
    public static func parseCalc(_ raw: String) -> CSSLength? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard s.hasPrefix("calc("), s.hasSuffix(")") else { return nil }
        let inner = s.dropFirst(5).dropLast()
        guard !inner.contains("("), !inner.contains(")") else { return nil }
        let tokens = inner.split(whereSeparator: \.isWhitespace).map(String.init)
        guard tokens.count % 2 == 1 else { return nil }
        var sum = CSSCalc()
        var sign: CGFloat = 1
        for (index, token) in tokens.enumerated() {
            if index % 2 == 1 {
                switch token {
                case "+": sign = 1
                case "-": sign = -1
                default: return nil
                }
            } else {
                guard let term = parse(token), sum.add(term, sign: sign) else { return nil }
            }
        }
        return .calc(sum)
    }

    /// Resolves a length to points against the given bases. Returns nil for `.auto`.
    /// `percentBase` is the containing-block width for margins/padding/width.
    /// `vh`/`vw` resolve only where the caller knows the viewport size; elsewhere
    /// they fall back to nil (the property's initial value), like `calc()`.
    public static func resolve(
        _ length: CSSLength,
        emBase: CGFloat,
        remBase: CGFloat,
        percentBase: CGFloat,
        viewportHeight: CGFloat? = nil,
        viewportWidth: CGFloat? = nil
    ) -> CGFloat? {
        switch length {
        case .px(let v): return v
        case .pt(let v): return v * 96.0 / 72.0
        case .em(let v): return v * emBase
        case .rem(let v): return v * remBase
        case .percent(let v): return v * percentBase
        case .vh(let v): return viewportHeight.map { v * $0 }
        case .vw(let v): return viewportWidth.map { v * $0 }
        case .auto: return nil
        case .calc(let sum):
            var total = sum.px + sum.em * emBase + sum.rem * remBase + sum.percent * percentBase
            if sum.vh != 0 {
                guard let viewportHeight else { return nil }
                total += sum.vh * viewportHeight
            }
            if sum.vw != 0 {
                guard let viewportWidth else { return nil }
                total += sum.vw * viewportWidth
            }
            return total
        }
    }
}
