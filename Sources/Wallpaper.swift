import AppKit
import CoreImage
import Foundation

/// The desktop wallpaper, optionally blurred the way a launcher overlay wants it.
enum Wallpaper {
    private static var cache: [String: NSImage] = [:]

    static func image(for screen: NSScreen?, blurred: Bool) -> NSImage? {
        guard let screen,
              let url = NSWorkspace.shared.desktopImageURL(for: screen) else { return nil }
        let key = url.path + (blurred ? "#blur" : "#plain")
        if let cached = cache[key] { return cached }

        guard let source = CIImage(contentsOf: url) else { return nil }
        let targetWidth: CGFloat = 1600
        let scale = min(1, targetWidth / source.extent.width)
        var image = source
        if scale < 1 {
            image = source.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }
        if blurred {
            image = image.clampedToExtent()
                .applyingGaussianBlur(sigma: 28)
                .cropped(to: image.extent)
        }

        let representation = NSCIImageRep(ciImage: image)
        let result = NSImage(size: representation.size)
        result.addRepresentation(representation)
        cache[key] = result
        return result
    }
}
