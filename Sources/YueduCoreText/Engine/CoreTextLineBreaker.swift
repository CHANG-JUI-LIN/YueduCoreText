import CoreFoundation
import CoreText
import Foundation
import UIKit

/// The ONLY place the browser engine touches CoreText for text in Phase 1:
/// shaping + line breaking + typographic metrics. Glyph drawing is explicitly
/// out of scope (DisplayList carries text ranges; a future draw phase renders them).
final class CoreTextLineBreaker {

    struct LineBreak {
        let range: NSRange          // into the input attributed string
        let width: CGFloat          // typographic width (max coordinate)
        let ascent: CGFloat
        let descent: CGFloat
        var presentation: NSAttributedString? = nil
        var generatedHyphen = false
        let line: CTLine            // the shaped line, retained for precise
                                    // string-index → typographic-offset mapping
    }

    func breakLines(attributed: NSAttributedString, maxWidth: CGFloat) -> [LineBreak] {
        let typesetter = CTTypesetterCreateWithAttributedString(Self.shapingText(attributed))
        let nsString = attributed.string as NSString
        var lines: [LineBreak] = []
        var charIndex = 0
        let total = attributed.length
        var index = 0
        while charIndex < total {
            guard let lineBreak = breakNextLine(
                typesetter: typesetter,
                charIndex: &charIndex,
                maxWidth: maxWidth,
                attributed: attributed,
                nsString: nsString,
                total: total
            ) else {
                break
            }
            lines.append(lineBreak)
            index += 1
            if index > 10_000 { break } // defensive: never infinite-loop on glyph-less input
        }
        return lines
    }

    func breakNextLine(
        typesetter: CTTypesetter,
        charIndex: inout Int,
        maxWidth: CGFloat,
        attributed: NSAttributedString,
        nsString: NSString,
        total: Int,
        recordMemory: Bool = true
    ) -> LineBreak? {
        guard charIndex < total else { return nil }
        if recordMemory {
            MemoryTracker.record(.ctLineRun, bytes: 192)  // ~192B per retained CTLine (estimate)
        }
        var count = CTTypesetterSuggestLineBreak(typesetter, charIndex, maxWidth)

        if let hyphenated = hyphenatedLine(attributed: attributed, start: charIndex, suggested: count, maxWidth: maxWidth) {
            charIndex = NSMaxRange(hyphenated.range)
            return hyphenated
        }
        // Normal wrapping must not silently become break-all for a long word.
        // Explicit overflow-wrap/word-break emergency behavior remains opt-in.
        let end = charIndex + count
        if end > charIndex, end < total,
           isWordUnit(nsString.character(at: end - 1)), isWordUnit(nsString.character(at: end)),
           (attributed.attribute(TextBreakingAttributes.emergency, at: charIndex, effectiveRange: nil) as? Bool) != true {
            var wordEnd = end
            while wordEnd < total && isWordUnit(nsString.character(at: wordEnd)) { wordEnd += 1 }
            let line = CTTypesetterCreateLine(typesetter, CFRange(location: charIndex, length: wordEnd - charIndex))
            let (width, ascent, descent) = metrics(for: line)
            // Collapsible trailing whitespace belongs to this source slice even
            // though it paints no ink. Otherwise the next line's leading-space
            // collapse would drop it from fragment/copy geometry entirely.
            var sourceEnd = wordEnd
            while sourceEnd < total && [0x20, 0x09].contains(nsString.character(at: sourceEnd)) { sourceEnd += 1 }
            let result = LineBreak(range: NSRange(location: charIndex, length: sourceEnd - charIndex), width: width, ascent: ascent, descent: descent, line: line)
            charIndex = sourceEnd
            return result
        }

        // CTTypesetter can suggest a break inside a grapheme cluster
        // (emoji ZWJ sequences, combining marks) when the cluster is wider
        // than maxWidth. Snap the suggested count DOWN to the cluster
        // boundary so lines never cut a cluster.
        count = snapToCluster(nsString, count: count, charIndex: charIndex)
        if count <= 0 {
            // Nothing (or no whole cluster) fits: force the first grapheme
            // cluster onto the line — overflow accepted (CSS overflow).
            let cluster = nsString.rangeOfComposedCharacterSequence(at: charIndex)
            count = min(cluster.location + cluster.length, total) - charIndex
            guard count > 0 else { return nil }
            let line = CTTypesetterCreateLine(typesetter, CFRange(location: charIndex, length: count))
            let (width, ascent, descent) = metrics(for: line)
            charIndex += count
            return LineBreak(
                range: NSRange(location: charIndex - count, length: count),
                width: width, ascent: ascent, descent: descent,
                line: line
            )
        }

        var line = CTTypesetterCreateLine(typesetter, CFRange(location: charIndex, length: count))
        var (width, ascent, descent) = metrics(for: line)
        // CTTypesetterSuggestLineBreak fits glyphs up to the last
        // non-whitespace glyph, but the returned count can include a
        // trailing space whose advance pushes CTLineGetTypographicBounds
        // past maxWidth (measured 103.6 at maxWidth 100 for SF 16pt).
        // Trim until the line truly fits: the breaker's contract is that
        // returned lines never exceed maxWidth.
        let originalCount = count
        while width > maxWidth && count > 1 {
            count -= 1
            line = CTTypesetterCreateLine(typesetter, CFRange(location: charIndex, length: count))
            (width, ascent, descent) = metrics(for: line)
        }
        // The trim above can land inside a grapheme cluster — snap down again.
        let snapped = snapToCluster(nsString, count: count, charIndex: charIndex)
        if snapped <= 0 {
            // The trim cut into a cluster wider than the line: force the
            // whole cluster onto the line (overflow accepted).
            let cluster = nsString.rangeOfComposedCharacterSequence(at: charIndex)
            count = min(cluster.location + cluster.length, total) - charIndex
            guard count > 0 else { return nil }
            line = CTTypesetterCreateLine(typesetter, CFRange(location: charIndex, length: count))
            (width, ascent, descent) = metrics(for: line)
        } else if snapped != count {
            count = snapped
            line = CTTypesetterCreateLine(typesetter, CFRange(location: charIndex, length: count))
            (width, ascent, descent) = metrics(for: line)
        }
        // If the trim removed ONLY trailing whitespace, keep it in the
        // RANGE (the space is part of the line's rendered advance and keeps
        // source parity exact) — WITHOUT re-measuring, so the width stays
        // within maxWidth.
        if count < originalCount {
            let removed = nsString.substring(
                with: NSRange(location: charIndex + count, length: originalCount - count)
            )
            if removed.allSatisfy({ $0 == " " || $0 == "\t" }) {
                count = originalCount
            }
        }
        guard count > 0 else { return nil }
        charIndex += count
        return LineBreak(
            range: NSRange(location: charIndex - count, length: count),
            width: width, ascent: ascent, descent: descent,
            line: line
        )
    }

    /// Preserve UTF-16 indices while preventing CoreText from independently
    /// deciding whether soft hyphens are visible. This breaker owns that choice.
    static func shapingText(_ attributed: NSAttributedString) -> NSAttributedString {
        guard attributed.string.contains("\u{00AD}") else { return attributed }
        let result = NSMutableAttributedString(attributedString: attributed)
        result.mutableString.replaceOccurrences(of: "\u{00AD}", with: "\u{2060}", range: NSRange(location: 0, length: result.length))
        return result
    }

    private func isWordUnit(_ unit: unichar) -> Bool {
        guard let scalar = UnicodeScalar(unit) else { return false }
        // CJK has inter-character line opportunities, unlike alphabetic words.
        return unit == 0x00AD || (CharacterSet.letters.contains(scalar) && unit < 0x2E80)
    }

    private func hyphenatedLine(attributed: NSAttributedString, start: Int, suggested: Int, maxWidth: CGFloat) -> LineBreak? {
        let ns = attributed.string as NSString
        let naturalEnd = start + suggested
        guard naturalEnd < ns.length, maxWidth.isFinite else { return nil }
        var wordStart = naturalEnd
        while wordStart < ns.length && isWordUnit(ns.character(at: wordStart)) && wordStart > start && isWordUnit(ns.character(at: wordStart - 1)) { wordStart -= 1 }
        while wordStart < ns.length && !isWordUnit(ns.character(at: wordStart)) {
            if ns.character(at: wordStart) == 10 { return nil }
            wordStart += 1
        }
        var wordEnd = wordStart
        while wordEnd < ns.length && isWordUnit(ns.character(at: wordEnd)) { wordEnd += 1 }
        guard wordEnd > wordStart else { return nil }
        let policy = attributed.attribute(TextBreakingAttributes.hyphens, at: wordStart, effectiveRange: nil) as? String ?? "manual"
        guard policy != "none" else { return nil }
        var candidates: [Int] = []
        for i in wordStart..<wordEnd where ns.character(at: i) == 0x00AD { candidates.append(i + 1) }
        if policy == "auto", candidates.isEmpty,
           let language = attributed.attribute(TextBreakingAttributes.language, at: wordStart, effectiveRange: nil) as? String {
            let locale = CFLocaleCreate(nil, CFLocaleCreateCanonicalLocaleIdentifierFromString(nil, language as CFString))!
            if CFStringIsHyphenationAvailableForLocale(locale) {
                var location = wordEnd
                while location > wordStart {
                    let candidate = CFStringGetHyphenationLocationBeforeIndex(ns as CFString, location, CFRange(location: wordStart, length: wordEnd - wordStart), 0, locale, nil)
                    guard candidate != kCFNotFound, candidate > wordStart else { break }
                    candidates.append(candidate); location = candidate
                }
            }
        }
        for end in candidates.sorted(by: >) where end > start && end < wordEnd {
            // A nested language or hyphens override is a real word boundary for
            // this operation, never an invitation to use the parent's dictionary.
            var allowed = true
            attributed.enumerateAttribute(TextBreakingAttributes.hyphens, in: NSRange(location: wordStart, length: end - wordStart)) { value, _, _ in
                if (value as? String ?? "manual") != policy { allowed = false }
            }
            let language = attributed.attribute(TextBreakingAttributes.language, at:wordStart,effectiveRange:nil) as? String
            attributed.enumerateAttribute(TextBreakingAttributes.language, in:NSRange(location:wordStart,length:end-wordStart)) { value, _, _ in
                if (value as? String) != language { allowed = false }
            }
            guard allowed else { continue }
            let range = NSRange(location: start, length: end - start)
            let display = NSMutableAttributedString(attributedString: Self.shapingText(attributed.attributedSubstring(from: range)))
            let soft = ns.character(at: end - 1) == 0x00AD
            if soft { display.replaceCharacters(in: NSRange(location: display.length - 1, length: 1), with: "-") }
            else { display.append(NSAttributedString(string: "-", attributes: attributed.attributes(at: end - 1, effectiveRange: nil))) }
            display.addAttribute(TextBreakingAttributes.visibleHyphen, value:true, range:NSRange(location:display.length - 1,length:1))
            let line = CTLineCreateWithAttributedString(display)
            let (width, ascent, descent) = metrics(for: line)
            guard width <= maxWidth else { continue }
            return LineBreak(range: range, width: width, ascent: ascent, descent: descent,
                             presentation: display, generatedHyphen: !soft, line: line)
        }
        return nil
    }

    /// Snaps a (suggested or trimmed) line length down to a grapheme-cluster
    /// boundary. Returns <= 0 when the last kept character sits inside a
    /// cluster that starts at or before `charIndex` (nothing kept whole).
    private func snapToCluster(_ ns: NSString, count: Int, charIndex: Int) -> Int {
        guard count >= 1 else { return count }
        let lineEnd = charIndex + count
        let cluster = ns.rangeOfComposedCharacterSequence(at: lineEnd - 1)
        if cluster.location + cluster.length > lineEnd {
            return cluster.location - charIndex
        }
        return count
    }

    private func metrics(for line: CTLine) -> (CGFloat, CGFloat, CGFloat) {
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        let width = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
        // CoreText can return the same shaped line with sub-nanopoint advance
        // drift between consecutive CTLine instances (observed delta:
        // 6.984919309616e-10pt). `LineBreak.width` is authoritative horizontal
        // used geometry, so retaining that process noise makes fragments and
        // hit geometry nondeterministic even though line/source ranges are
        // equal. Normalize only the affected advance at the CoreText -> layout
        // boundary; ascent/descent remain untouched. Clearing 16 low mantissa
        // bits absorbs the measured 49,152-ULP drift while retaining roughly
        // 36 bits of relative precision, far below visible geometry.
        return (stableLayoutAdvance(width), ascent, descent)
    }

    private func stableLayoutAdvance(_ value: CGFloat) -> CGFloat {
        guard value.isFinite, value >= 0 else { return value }
        let canonicalBits = Double(value).bitPattern & ~UInt64(0xFFFF)
        return CGFloat(Double(bitPattern: canonicalBits))
    }
}
