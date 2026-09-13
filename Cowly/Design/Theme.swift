import AppKit
import CoreImage
import SwiftUI

enum Theme {
    enum Metrics {
        /// Height of the closed shelf when there is no notch to hide behind.
        static let closedIslandHeight: CGFloat = 32
        static let closedIslandWidth: CGFloat = 168
        /// How far the shelf grows when opened.
        static let openWidth: CGFloat = 548
        static let openHeight: CGFloat = 262
        /// Extra invisible margin so the hover target is forgiving.
        static let hoverPadding: CGFloat = 6
    }

    enum Palette {
        static let accent = Color(red: 0.38, green: 0.53, blue: 1.0)
        static let positive = Color(red: 0.32, green: 0.83, blue: 0.53)
        static let warning = Color(red: 1.0, green: 0.72, blue: 0.23)
        static let danger = Color(red: 1.0, green: 0.36, blue: 0.36)
        static let primaryText = Color.white
        static let secondaryText = Color.white.opacity(0.62)
        static let tertiaryText = Color.white.opacity(0.38)
        static let separator = Color.white.opacity(0.10)
        /// Cowly's signature pink, borrowed from the muzzle on the app icon.
        static let muzzle = Color(red: 0.96, green: 0.72, blue: 0.76)
        /// Pasture green, used for "all good" states.
        static let pasture = Color(red: 0.38, green: 0.72, blue: 0.55)
    }

    enum Typo {
        static let title = Font.system(size: 15, weight: .semibold, design: .rounded)
        static let subtitle = Font.system(size: 11.5, weight: .medium, design: .rounded)
        static let caption = Font.system(size: 10, weight: .medium, design: .rounded)
        static let mono = Font.system(size: 11, weight: .medium, design: .monospaced)
    }
}

extension Color {
    /// Average colour of an image, used to tint the glass to the album art.
    static func dominant(from image: NSImage?) -> Color? {
        guard let image,
              let tiff = image.tiffRepresentation,
              let source = CIImage(data: tiff) else { return nil }
        let extent = source.extent
        guard extent.width > 0, extent.height > 0 else { return nil }
        let filter = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: source,
            kCIInputExtentKey: CIVector(cgRect: extent)
        ])
        guard let output = filter?.outputImage else { return nil }
        var bitmap = [UInt8](repeating: 0, count: 4)
        CIContext(options: [.workingColorSpace: NSNull()]).render(
            output,
            toBitmap: &bitmap,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        return Color(
            .sRGB,
            red: Double(bitmap[0]) / 255,
            green: Double(bitmap[1]) / 255,
            blue: Double(bitmap[2]) / 255,
            opacity: 1
        )
    }
}
