import CoreText
import Foundation
import UIKit

extension CJKTypography {
    static let language = NSAttributedString.Key(kCTLanguageAttributeName as String)

    /// Set on a range whose font `applyFonts` chose; the value is the font the range
    /// had before. The range is still the text its run asked for, so layout compares
    /// this font, not the stand-in, with the run's when it decides whether a Reader
    /// rule gave the range a font of its own.
    public static let replacedFontAttribute = NSAttributedString.Key("YueduCJKReplacedFont")

    /// Tags CJK text with its language and gives it a font made for that language,
    /// in horizontal and vertical text alike.
    ///
    /// Leaving this to CoreText does not work: the system font has no Han, kana or
    /// Hangul, and on iOS its fallback follows the device's languages, not the text's.
    /// Measured on the iOS 27 simulator with a zh-Hant device, `.SFUI-Regular` drew 国
    /// from PingFang TC's interface face whether the text was tagged zh-Hans, ja or ko.
    /// So the font is named here:
    /// - Han and CJK punctuation take the style's language and font: PingFang TC,
    ///   PingFang SC, Hiragino Sans or Apple SD Gothic Neo;
    /// - kana are Japanese and take Hiragino Sans; Hangul is Korean and takes
    ///   Apple SD Gothic Neo;
    /// - dashes, ellipses, quotation marks and middle dots belong to the text around
    ///   them. Next to CJK text, or alone, they take the style's language and font,
    ///   which draw them as CJK text does (PingFang's — and … are a full em, so —— is
    ///   CLREQ's two-em dash; SF's are 0.85 and 0.78 em). Next to Latin text they stay
    ///   as they are. Digits side with neither;
    /// - other symbols the text's fonts lack — ①, ※, ℃ — take the style's font next to
    ///   CJK text, as Han would, rather than whatever the device's fallback picks.
    ///
    /// Only what the text's own fonts leave to the system's fallback is filled in. A
    /// character the font or its cascade (authored CSS fallbacks included) has keeps
    /// them, and a shared mark keeps them when they hold any CJK face. A CJK character
    /// they lack takes the stand-in even when the stand-in lacks it too, as an
    /// extension-B Han does: CoreText then falls back from the stand-in, and a ruby
    /// base or a run of Han stays in one font. A stand-in is the same size, bold when
    /// the font is bold, and slanted when it is italic, as CJK faces have no italics.
    /// Run delegates (images, ruby, notes, spacers) are the engine's own boxes and are
    /// left alone.
    public static func applyFonts(to text: NSMutableAttributedString, style: CJKTypographyStyle, in range: NSRange? = nil) {
        let whole = range ?? NSRange(location: 0, length: text.length)
        guard whole.length > 0 else { return }
        var units = [unichar](repeating: 0, count: whole.length)
        (text.string as NSString).getCharacters(&units, range: whole)
        var kinds = ScriptKind.classify(units)
        guard kinds.contains(.shared) || kinds.contains(where: \.isCJK) else { return }
        text.enumerateAttribute(runDelegate, in: whole) { value, delegated, _ in
            guard value != nil else { return }
            for index in (delegated.location - whole.location)..<(NSMaxRange(delegated) - whole.location) {
                kinds[index] = .box
            }
        }

        // A decision is a code: -1 leaves the unit alone; otherwise `slot * 2` tags it with
        // that style's language, and `slot * 2 + 1` also draws it in that style's stand-in.
        // Integers, not structs, because this runs on every paragraph a layout shapes.
        let styleSlot = RunCoverage.slot(style)
        struct Change { let range: NSRange; let tag: String; let font: UIFont?; let replaced: UIFont? }
        var changes: [Change] = []
        text.enumerateAttribute(.font, in: whole) { value, run, _ in
            let start = run.location - whole.location
            let end = start + run.length
            guard (start..<end).contains(where: { kinds[$0].isCJK || kinds[$0] == .shared || kinds[$0] == .neutral })
            else { return }
            let current = value.flatMap(ctFont)
            let replaced = current.map { $0 as UIFont }
            var coverage = RunCoverage(units: Array(units[start..<end]), font: current)
            var standIns: [UIFont?] = [nil, nil, nil, nil]
            var decided = -1
            var segmentStart = start
            func flush(upTo index: Int) {
                guard decided >= 0, index > segmentStart else { return }
                let slot = decided / 2
                let target = RunCoverage.styles[slot]
                var font: UIFont? = nil
                if decided & 1 == 1 {
                    font = standIns[slot] ?? CJKFontLookup.standIn(for: target, like: current)
                    standIns[slot] = font
                }
                changes.append(Change(
                    range: NSRange(location: whole.location + segmentStart, length: index - segmentStart),
                    tag: target.languageTag, font: font, replaced: font == nil ? nil : replaced))
            }
            let covered = coverage.covered
            kinds.withUnsafeBufferPointer { kinds in
                covered.withUnsafeBufferPointer { covered in
                    for index in start..<end {
                        let code: Int
                        switch kinds[index] {
                        case .continuation:
                            code = decided
                        case .han:
                            code = covered[index - start] ? styleSlot * 2 : styleSlot * 2 + 1
                        case .kana:
                            code = covered[index - start] ? 4 : 5
                        case .hangul:
                            code = covered[index - start] ? 6 : 7
                        case .shared where ScriptKind.joinsCJK(at: index, in: kinds):
                            code = coverage.holdsCJKFace || !coverage.standInHas(styleSlot, at: index - start)
                                ? styleSlot * 2 : styleSlot * 2 + 1
                        case .neutral where !covered[index - start] && ScriptKind.joinsCJK(at: index, in: kinds)
                            && coverage.standInHas(styleSlot, at: index - start):
                            code = styleSlot * 2 + 1
                        default:
                            code = -1
                        }
                        if code != decided {
                            flush(upTo: index)
                            segmentStart = index
                            decided = code
                        }
                    }
                }
            }
            flush(upTo: end)
        }
        // One call per range: each is a lookup in a string that may have many runs.
        for change in changes {
            if let font = change.font, let replaced = change.replaced {
                text.addAttributes([language: change.tag, .font: font, replacedFontAttribute: replaced], range: change.range)
            } else if let font = change.font {
                text.addAttributes([language: change.tag, .font: font], range: change.range)
            } else {
                text.addAttribute(language, value: change.tag, range: change.range)
            }
        }
    }
}

/// What a UTF-16 unit is, as far as choosing a CJK font goes.
enum ScriptKind: UInt8 {
    /// Han, bopomofo, CJK punctuation and symbols, full-width forms: the style's.
    case han
    case kana
    case hangul
    /// Latin, Greek, Cyrillic and other letters.
    case letter
    /// Dashes, ellipses, quotation marks and middle dots, which CJK and Latin text share.
    case shared
    /// A line or paragraph break; shared marks look no further.
    case lineBreak
    /// A low surrogate, a variation selector or a combining mark: goes with what it follows.
    case continuation
    /// Everything else, digits included: punctuation and symbols.
    case neutral
    /// Spaces, controls and format characters such as U+200B: never redrawn.
    case space
    /// A run delegate: an image, ruby, a note or a spacer the engine draws itself.
    case box

    var isCJK: Bool { self == .han || self == .kana || self == .hangul }

    static func classify(_ units: [unichar]) -> [ScriptKind] {
        [ScriptKind](unsafeUninitializedCapacity: units.count) { kinds, count in
            units.withUnsafeBufferPointer { units in
                var index = 0
                while index < units.count {
                    let unit = units[index]
                    if UTF16.isLeadSurrogate(unit), index + 1 < units.count, UTF16.isTrailSurrogate(units[index + 1]) {
                        let value = 0x10000 + ((UInt32(unit) - 0xD800) << 10) + (UInt32(units[index + 1]) - 0xDC00)
                        kinds[index] = of(value)
                        kinds[index + 1] = .continuation
                        index += 2
                    } else {
                        kinds[index] = of(UInt32(unit))
                        index += 1
                    }
                }
            }
            count = units.count
        }
    }

    static func of(_ value: UInt32) -> ScriptKind {
        switch value {
        case 0x00...0x20, 0x7F...0xA0:
            return value == 0x0A || value == 0x0D ? .lineBreak : .space
        case 0x30...0x39:
            return .neutral
        case 0x41...0x5A, 0x61...0x7A:
            return .letter
        case 0x0A, 0x0D, 0x2028, 0x2029:
            return .lineBreak
        case 0x0300...0x036F, 0x200C, 0x200D, 0x20D0...0x20FF, 0x3099, 0x309A, 0xFE00...0xFE0F, 0xE0100...0xE01EF:
            return .continuation
        case 0x00B7, 0x2014, 0x2015, 0x2018, 0x2019, 0x201C, 0x201D, 0x2025, 0x2026, 0x2027, 0x2E3A, 0x2E3B:
            return .shared
        // Jamo, compatibility jamo, jamo extensions, syllables, half-width jamo.
        case 0x1100...0x11FF, 0x3131...0x318E, 0xA960...0xA97C, 0xAC00...0xD7A3, 0xD7B0...0xD7FB, 0xFFA0...0xFFDC:
            return .hangul
        // Hiragana and katakana with their extensions and half-width forms. The middle
        // dot ・ and the long vowel mark ー are Chinese text's too, and stay the style's.
        case 0x3041...0x3096, 0x309B...0x309F, 0x30A1...0x30FA, 0x30FD...0x30FF, 0x31F0...0x31FF,
             0xFF66...0xFF9F, 0x1AFF0...0x1B16F:
            return .kana
        // Radicals, ideographic description, CJK symbols and punctuation, bopomofo,
        // kanbun, strokes, enclosed and compatibility CJK, Han and its extensions,
        // vertical and compatibility forms, full-width and half-width forms.
        case 0x2E80...0x2FFF, 0x3000...0x3040, 0x3097, 0x3098, 0x30A0, 0x30FB, 0x30FC, 0x3100...0x3130,
             0x3190...0x31EF, 0x3200...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0xFE10...0xFE1F,
             0xFE30...0xFE4F, 0xFF01...0xFF65, 0xFFE0...0xFFEE, 0x20000...0x3FFFD:
            return .han
        default:
            guard value >= 0x80, let scalar = Unicode.Scalar(value) else { return .neutral }
            if scalar.properties.isAlphabetic { return .letter }
            switch scalar.properties.generalCategory {
            case .spaceSeparator, .format, .control, .lineSeparator, .paragraphSeparator: return .space
            default: return .neutral
            }
        }
    }

    /// Whether the shared mark or symbol at `index` belongs to CJK text: the nearest
    /// letter or CJK character on either side, within its line, is CJK, or there is none.
    /// Looked up only for the units that need it, which sit next to their text.
    static func joinsCJK(at index: Int, in kinds: UnsafeBufferPointer<ScriptKind>) -> Bool {
        func nearest(_ indices: some Sequence<Int>) -> ScriptKind? {
            for neighbour in indices {
                switch kinds[neighbour] {
                case .letter, .han, .kana, .hangul: return kinds[neighbour]
                case .lineBreak: return nil
                default: continue
                }
            }
            return nil
        }
        let before = nearest(stride(from: index - 1, through: 0, by: -1))
        if before?.isCJK == true { return true }
        let after = nearest(index + 1 ..< kinds.count)
        if after?.isCJK == true { return true }
        return before == nil && after == nil
    }
}

/// One font run's glyph coverage in its own fonts — the font and its cascade — and in
/// the stand-ins it may need, each looked up once for the whole run.
private struct RunCoverage {
    let units: [unichar]
    let font: CTFont?
    private let stack: CJKFontLookup.Stack
    /// Whether the run's own fonts have each character.
    let covered: [Bool]
    private var standIns: [UIFont?] = [nil, nil, nil, nil]
    private var standInGlyphs: [[CGGlyph]] = [[], [], [], []]

    static let styles: [CJKTypographyStyle] = [.traditional, .simplified, .japanese, .korean]

    static func slot(_ style: CJKTypographyStyle) -> Int {
        switch style {
        case .traditional: return 0
        case .simplified: return 1
        case .japanese: return 2
        case .korean: return 3
        }
    }

    init(units: [unichar], font: CTFont?) {
        self.units = units
        self.font = font
        stack = font.map(CJKFontLookup.stack) ?? CJKFontLookup.Stack(fonts: [], drawsHan: false)
        var covered = [Bool](repeating: false, count: units.count)
        for member in stack.fonts {
            let glyphs = CJKFontLookup.glyphs(in: member, for: units)
            for index in units.indices where glyphs[index] != 0 { covered[index] = true }
        }
        self.covered = covered
    }

    /// Whether the run's own fonts hold a face that draws Han, so its dashes and
    /// quotation marks are the author's or reader's choice for CJK text.
    var holdsCJKFace: Bool { stack.drawsHan }

    /// Whether the stand-in for the style in `slot` has the character at `index`.
    mutating func standInHas(_ slot: Int, at index: Int) -> Bool {
        if standIns[slot] == nil {
            let standIn = CJKFontLookup.standIn(for: Self.styles[slot], like: font)
            standIns[slot] = standIn
            standInGlyphs[slot] = CJKFontLookup.glyphs(in: standIn as CTFont, for: units)
        }
        return standInGlyphs[slot][index] != 0
    }
}

/// Stand-in fonts and coverage facts, cached across runs and calls.
enum CJKFontLookup {
    private struct StandInKey: Hashable {
        let style: CJKTypographyStyle
        let size: CGFloat
        let bold: Bool
        let a: CGFloat, b: CGFloat, c: CGFloat, d: CGFloat
    }
    nonisolated(unsafe) private static var standIns: [StandInKey: UIFont] = [:]
    nonisolated(unsafe) private static var stacks: [String: Stack] = [:]
    private static let lock = NSLock()

    /// A font and the fonts its explicit cascade list names, in order. The system's
    /// own fallback is not part of it: that is what `applyFonts` replaces.
    struct Stack {
        let fonts: [CTFont]
        let drawsHan: Bool
    }

    static func stack(of font: CTFont) -> Stack {
        let descriptor = CTFontCopyFontDescriptor(font)
        let cascade = CTFontDescriptorCopyAttribute(descriptor, kCTFontCascadeListAttribute) as? [CTFontDescriptor] ?? []
        let size = CTFontGetSize(font)
        // Names alone could collide for descriptors made by family and traits.
        let members = cascade.map { "\((CTFontDescriptorCopyAttribute($0, kCTFontNameAttribute) as? String) ?? "?")#\(CFHash($0))" }
        let key = ([CTFontCopyPostScriptName(font) as String, "\(size)"] + members).joined(separator: "|")
        if let known = lock.withLock({ stacks[key] }) { return known }
        let fonts = [font] + cascade.map { CTFontCreateWithFontDescriptor($0, size, nil) }
        let stack = Stack(fonts: fonts, drawsHan: fonts.contains(where: drawsHan))
        lock.withLock { stacks[key] = stack }
        return stack
    }

    /// Glyphs for `units` in `font` alone, without its cascade; 0 where it has none.
    /// A surrogate pair's glyph is at its first unit.
    static func glyphs(in font: CTFont, for units: [unichar]) -> [CGGlyph] {
        var glyphs = [CGGlyph](repeating: 0, count: units.count)
        guard !units.isEmpty else { return glyphs }
        _ = CTFontGetGlyphsForCharacters(font, units, &glyphs, units.count)
        return glyphs
    }

    private static func drawsHan(_ font: CTFont) -> Bool {
        var unit: unichar = 0x4E00
        var glyph: CGGlyph = 0
        return CTFontGetGlyphsForCharacters(font, &unit, &glyph, 1) && glyph != 0
    }

    /// The style's font at `font`'s size, bold when it is bold, slanted as it is
    /// slanted. An italic face without a slant of its own gets the 0.2 shear the
    /// engines synthesize for faces without italics (`FontTraits.synthesizedObliqueFont`).
    static func standIn(for style: CJKTypographyStyle, like font: CTFont?) -> UIFont {
        let size = font.map(CTFontGetSize) ?? 17
        let traits = font.map(CTFontGetSymbolicTraits) ?? []
        var matrix = font.map(CTFontGetMatrix) ?? .identity
        if matrix.isIdentity && traits.contains(.traitItalic) {
            matrix = CGAffineTransform(a: 1, b: 0, c: 0.2, d: 1, tx: 0, ty: 0)
        }
        let key = StandInKey(style: style, size: size, bold: traits.contains(.traitBold),
                             a: matrix.a, b: matrix.b, c: matrix.c, d: matrix.d)
        if let cached = lock.withLock({ standIns[key] }) { return cached }
        var descriptor = CTFontDescriptorCreateWithNameAndSize(style.referenceFontName as CFString, size)
        if key.bold {
            // By family: a named descriptor keeps its name and ignores the trait.
            let family = CTFontCopyFamilyName(CTFontCreateWithFontDescriptor(descriptor, size, nil))
            let byFamily = CTFontDescriptorCreateWithAttributes([kCTFontFamilyNameAttribute: family] as CFDictionary)
            descriptor = CTFontDescriptorCreateCopyWithSymbolicTraits(byFamily, .traitBold, .traitBold) ?? descriptor
        }
        let standIn: CTFont = matrix.isIdentity
            ? CTFontCreateWithFontDescriptor(descriptor, size, nil)
            : CTFontCreateWithFontDescriptor(descriptor, size, &matrix)
        let font = standIn as UIFont
        lock.withLock { standIns[key] = font }
        return font
    }
}
