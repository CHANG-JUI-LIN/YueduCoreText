import CoreText
import UIKit

public enum FontTraits {
    private static let syntheticBoldStrokeWidth = -2.5 as NSNumber
    public static func syntheticBoldAttributes(
        for font: UIFont,
        isBoldRequested: Bool
    ) -> [NSAttributedString.Key: Any] {
        guard isBoldRequested,
              !font.fontDescriptor.symbolicTraits.contains(.traitBold),
              !supportsVariableWeight(font)
        else { return [:] }
        return [.strokeWidth: syntheticBoldStrokeWidth]
    }

    public static func boldVersion(of font: UIFont, size: CGFloat) -> UIFont {
        if font.fontDescriptor.symbolicTraits.contains(.traitBold) {
            return font
        }
        if let descriptor = font.fontDescriptor.withSymbolicTraits(.traitBold) {
            return preservingFamily(font, resolved: UIFont(descriptor: descriptor, size: size))
        }
        // Synthetic bold for fonts without native bold face
        let attrs: [UIFontDescriptor.AttributeName: Any] = [
            .traits: [UIFontDescriptor.TraitKey.weight: UIFont.Weight.bold]
        ]
        return preservingFamily(
            font,
            resolved: UIFont(descriptor: font.fontDescriptor.addingAttributes(attrs), size: size)
        )
    }

    private static func preservingFamily(_ requested: UIFont, resolved: UIFont) -> UIFont {
        resolved.familyName == requested.familyName ? resolved : requested
    }

    private static func supportsVariableWeight(_ font: UIFont) -> Bool {
        guard let axes = CTFontCopyVariationAxes(font as CTFont) as? [[CFString: Any]] else {
            return false
        }
        return axes.contains { axis in
            guard let identifier = axis[kCTFontVariationAxisIdentifierKey] as? NSNumber else {
                return false
            }
            // OpenType `wght` is encoded as the four-character tag 0x77676874.
            return identifier.uint32Value == 0x7767_6874
        }
    }

    public static func synthesizedObliqueFont(from font: UIFont, slant: CGFloat = 0.2) -> UIFont {
        var matrix = CGAffineTransform(a: 1, b: 0, c: slant, d: 1, tx: 0, ty: 0)
        let ctFont = CTFontCreateWithFontDescriptor(
            font.fontDescriptor as CTFontDescriptor, font.pointSize, &matrix
        )
        return ctFont as UIFont
    }
}
