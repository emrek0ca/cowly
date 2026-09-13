import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Turns whatever landed on the shelf into tray items.
enum DropHandling {
    /// Types we advertise on every drop target in the app.
    static let acceptedTypes: [UTType] = [.fileURL, .url, .image, .plainText, .utf8PlainText]

    @MainActor
    @discardableResult
    static func receive(providers: [NSItemProvider]) async -> Int {
        var urls: [URL] = []
        var texts: [String] = []
        var images: [NSImage] = []

        for provider in providers {
            if let url = await provider.loadFileURL() {
                urls.append(url)
                continue
            }
            if let image = await provider.loadImage() {
                images.append(image)
                continue
            }
            if let text = await provider.loadText() {
                texts.append(text)
            }
        }

        var count = TrayStore.shared.add(urls: urls)
        for image in images where TrayStore.shared.add(image: image) { count += 1 }
        for text in texts where TrayStore.shared.add(text: text) { count += 1 }
        return count
    }
}

@MainActor
extension NSItemProvider {
    func loadFileURL() async -> URL? {
        guard hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else { return nil }
        return await withCheckedContinuation { continuation in
            _ = loadObject(ofClass: URL.self) { url, _ in
                continuation.resume(returning: url?.isFileURL == true ? url : nil)
            }
        }
    }

    func loadImage() async -> NSImage? {
        guard canLoadObject(ofClass: NSImage.self) else { return nil }
        return await withCheckedContinuation { continuation in
            _ = loadObject(ofClass: NSImage.self) { image, _ in
                continuation.resume(returning: image as? NSImage)
            }
        }
    }

    func loadText() async -> String? {
        guard canLoadObject(ofClass: NSString.self) else { return nil }
        return await withCheckedContinuation { continuation in
            _ = loadObject(ofClass: NSString.self) { string, _ in
                let value = (string as? NSString) as String?
                continuation.resume(returning: value?.isEmpty == false ? value : nil)
            }
        }
    }
}
