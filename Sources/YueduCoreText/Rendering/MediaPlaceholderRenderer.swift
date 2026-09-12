import UIKit

public enum MediaPlaceholderRenderer {
    public static func videoImage(maxWidth: CGFloat, intrinsicSize: CGSize?) -> UIImage {
        let aspect: CGFloat = {
            if let size = intrinsicSize, size.width > 0, size.height > 0 {
                // Clamp to a sane range so a malformed size can't make a sliver or a tower.
                return min(max(size.height / size.width, 0.4), 1.4)
            }
            return 9.0 / 16.0
        }()
        let cap = min(maxWidth, 640)
        let width = max(200, min(cap, intrinsicSize?.width ?? cap))
        let height = max(120, width * aspect)

        let format = UIGraphicsImageRendererFormat()
        format.opaque = false

        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { _ in
            let bounds = CGRect(x: 0, y: 0, width: width, height: height)
            UIColor(red: 0.11, green: 0.12, blue: 0.14, alpha: 1).setFill()
            UIBezierPath(roundedRect: bounds, cornerRadius: 10).fill()

            // Play button: a light disc with a dark triangle, optically nudged right.
            let diameter = min(width, height) * 0.30
            let disc = CGRect(
                x: (width - diameter) / 2,
                y: (height - diameter) / 2,
                width: diameter,
                height: diameter
            )
            UIColor.white.withAlphaComponent(0.92).setFill()
            UIBezierPath(ovalIn: disc).fill()

            let t = diameter * 0.42
            let cx = disc.midX + t * 0.12
            let cy = disc.midY
            let triangle = UIBezierPath()
            triangle.move(to: CGPoint(x: cx - t * 0.5, y: cy - t * 0.6))
            triangle.addLine(to: CGPoint(x: cx - t * 0.5, y: cy + t * 0.6))
            triangle.addLine(to: CGPoint(x: cx + t * 0.64, y: cy))
            triangle.close()
            UIColor(white: 0.1, alpha: 1).setFill()
            triangle.fill()
        }
    }
}
