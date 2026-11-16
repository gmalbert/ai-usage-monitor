import AppKit

/// Renders the menu-bar gauge as a colored NSImage.
///
/// SwiftUI shape strokes render monochrome inside `MenuBarExtra` labels on
/// recent macOS versions, but non-template NSImages keep their colors. The
/// drawing mirrors the Windows `ui/icons.py` gauge: a dark disc, a gray
/// track arc, and a state-colored progress arc starting at 12 o'clock.
enum GaugeIconRenderer {
    private static let pixelSize: CGFloat = 32
    private static let pointSize: CGFloat = 16
    private static let lineWidth: CGFloat = 7 * (pixelSize / 64)

    static func image(state: String, remaining: Double?) -> NSImage {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(pixelSize),
            pixelsHigh: Int(pixelSize),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return NSImage()
        }
        rep.size = NSSize(width: pointSize, height: pointSize)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        if let context = NSGraphicsContext.current?.cgContext {
            draw(context: context, state: state, remaining: remaining)
        }
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: NSSize(width: pointSize, height: pointSize))
        image.addRepresentation(rep)
        image.isTemplate = false
        return image
    }

    private static func draw(context: CGContext, state: String, remaining: Double?) {
        let center = CGPoint(x: pixelSize / 2, y: pixelSize / 2)
        let radius = pixelSize / 2 - lineWidth / 2 - 1
        let inset = pixelSize / 2 - 3

        // Dark disc background.
        context.setFillColor(CGColor(red: 0x1F / 255, green: 0x23 / 255, blue: 0x29 / 255, alpha: 1))
        context.fillEllipse(in: CGRect(x: inset, y: inset, width: pixelSize - 2 * inset, height: pixelSize - 2 * inset))

        // Gray track arc.
        context.setStrokeColor(CGColor(red: 0x4B / 255, green: 0x55 / 255, blue: 0x63 / 255, alpha: 1))
        context.setLineWidth(lineWidth)
        context.setLineCap(.round)
        context.addArc(center: center, radius: radius, startAngle: 0, endAngle: 2 * .pi, clockwise: false)
        context.strokePath()

        // State-colored progress arc from 12 o'clock, clockwise.
        if let remaining {
            let fraction = max(0.0, min(100.0, remaining)) / 100
            let color = GaugePalette.cgColor(for: state)
            context.setStrokeColor(color)
            context.addArc(
                center: center,
                radius: radius,
                startAngle: .pi / 2,
                endAngle: .pi / 2 - 2 * .pi * fraction,
                clockwise: true
            )
            context.strokePath()
        }
    }
}
