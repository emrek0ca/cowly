import AppKit
import Observation
import QuickLookThumbnailing
import SwiftUI
import UniformTypeIdentifiers

struct TrayItem: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    /// Copy that Cowly owns, so the tray survives the original being moved.
    var storedPath: String
    /// Where the file came from, when we know.
    var originPath: String?
    var name: String
    var size: Int
    var typeIdentifier: String
    var addedAt: Date
    var isPinned: Bool

    init(
        id: UUID = UUID(),
        storedURL: URL,
        originURL: URL?,
        name: String,
        size: Int,
        typeIdentifier: String,
        addedAt: Date = .now,
        isPinned: Bool = false
    ) {
        self.id = id
        self.storedPath = storedURL.path(percentEncoded: false)
        self.originPath = originURL?.path(percentEncoded: false)
        self.name = name
        self.size = size
        self.typeIdentifier = typeIdentifier
        self.addedAt = addedAt
        self.isPinned = isPinned
    }

    var url: URL { URL(fileURLWithPath: storedPath) }
    var originURL: URL? { originPath.map { URL(fileURLWithPath: $0) } }
    var type: UTType { UTType(typeIdentifier) ?? .data }
    var isImage: Bool { type.conforms(to: .image) }
    var fileExists: Bool { FileManager.default.fileExists(atPath: storedPath) }
    var sizeLabel: String { size.byteLabel }

    var symbol: String {
        if type.conforms(to: .image) { return "photo" }
        if type.conforms(to: .movie) { return "film" }
        if type.conforms(to: .audio) { return "waveform" }
        if type.conforms(to: .pdf) { return "doc.richtext" }
        if type.conforms(to: .archive) { return "doc.zipper" }
        if type.conforms(to: .sourceCode) || type.conforms(to: .script) { return "chevron.left.forwardslash.chevron.right" }
        if type.conforms(to: .folder) { return "folder" }
        if type.conforms(to: .plainText) { return "doc.text" }
        return "doc"
    }
}

/// Owns the shelf's files: importing, thumbnails, exporting and persistence.
@MainActor
@Observable
final class TrayStore {
    static let shared = TrayStore()

    private(set) var items: [TrayItem] = []
    private(set) var thumbnails: [UUID: NSImage] = [:]
    /// Flashes green after a successful import so the drop feels acknowledged.
    private(set) var lastImportCount = 0

    private init() {
        items = Disk.load([TrayItem].self, from: Paths.trayStore) ?? []
        items.removeAll { !$0.fileExists }
        Task { await warmThumbnails() }
    }

    var sorted: [TrayItem] {
        items.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
            return lhs.addedAt > rhs.addedAt
        }
    }

    var totalSize: Int { items.reduce(0) { $0 + $1.size } }
    var isEmpty: Bool { items.isEmpty }

    // MARK: - Importing

    @discardableResult
    func add(urls: [URL]) -> Int {
        var added = 0
        for url in urls {
            guard let item = importFile(at: url) else { continue }
            items.insert(item, at: 0)
            added += 1
            Task { await makeThumbnail(for: item) }
        }
        if added > 0 {
            lastImportCount = added
            Haptics.tap(.generic)
            persist()
            NotchViewModel.shared.present(
                LiveActivity(
                    style: .expanded,
                    leadingSymbol: "tray.and.arrow.down.fill",
                    leadingTint: Theme.Palette.positive,
                    title: added == 1 ? (urls.first?.lastPathComponent ?? "File added") : "\(added) files added",
                    subtitle: "In your tray",
                    duration: 2.0
                )
            )
        }
        return added
    }

    @discardableResult
    func add(text: String) -> Bool {
        let name = "Note \(Self.stampFormatter.string(from: .now)).txt"
        let url = Paths.trayFiles.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let file = url.appendingPathComponent(name)
        guard (try? text.write(to: file, atomically: true, encoding: .utf8)) != nil else { return false }
        let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? text.utf8.count
        let item = TrayItem(
            storedURL: file, originURL: nil, name: name, size: size,
            typeIdentifier: UTType.plainText.identifier
        )
        items.insert(item, at: 0)
        persist()
        Task { await makeThumbnail(for: item) }
        return true
    }

    @discardableResult
    func add(image: NSImage) -> Bool {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return false }
        let name = "Image \(Self.stampFormatter.string(from: .now)).png"
        let dir = Paths.trayFiles.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent(name)
        guard (try? png.write(to: file)) != nil else { return false }
        let item = TrayItem(
            storedURL: file, originURL: nil, name: name, size: png.count,
            typeIdentifier: UTType.png.identifier
        )
        items.insert(item, at: 0)
        persist()
        Task { await makeThumbnail(for: item) }
        return true
    }

    private func importFile(at url: URL) -> TrayItem? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path(percentEncoded: false)) else { return nil }
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentTypeKey, .totalFileSizeKey, .isDirectoryKey])
        let isDirectory = values?.isDirectory ?? false
        let dir = Paths.trayFiles.appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            let destination = dir.appendingPathComponent(url.lastPathComponent)
            try fm.copyItem(at: url, to: destination)
            let size = isDirectory
                ? directorySize(destination)
                : (values?.fileSize ?? values?.totalFileSize ?? 0)
            return TrayItem(
                storedURL: destination,
                originURL: url,
                name: url.lastPathComponent,
                size: size,
                typeIdentifier: (values?.contentType ?? .data).identifier
            )
        } catch {
            log.error("Tray import failed for \(url.lastPathComponent): \(error.localizedDescription)")
            return nil
        }
    }

    private func directorySize(_ url: URL) -> Int {
        guard let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: [.fileSizeKey]
        ) else { return 0 }
        var total = 0
        for case let child as URL in enumerator {
            total += (try? child.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        }
        return total
    }

    // MARK: - Mutating

    func remove(_ item: TrayItem) {
        items.removeAll { $0.id == item.id }
        thumbnails[item.id] = nil
        // Each import lives in its own folder, so removing the folder is enough.
        try? FileManager.default.removeItem(at: item.url.deletingLastPathComponent())
        persist()
    }

    func removeAll() {
        for item in items where !item.isPinned { remove(item) }
    }

    func togglePin(_ item: TrayItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].isPinned.toggle()
        Haptics.tap(.levelChange)
        persist()
    }

    // MARK: - Exporting

    func revealInFinder(_ item: TrayItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.originURL ?? item.url])
    }

    func open(_ item: TrayItem) {
        NSWorkspace.shared.open(item.url)
    }

    func copyToPasteboard(_ items: [TrayItem]) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects(items.map { $0.url as NSURL })
        Haptics.tap(.generic)
    }

    func saveToDownloads(_ item: TrayItem) {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        var destination = downloads.appendingPathComponent(item.name)
        var counter = 1
        while FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) {
            let base = (item.name as NSString).deletingPathExtension
            let ext = (item.name as NSString).pathExtension
            let candidate = ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)"
            destination = downloads.appendingPathComponent(candidate)
            counter += 1
        }
        try? FileManager.default.copyItem(at: item.url, to: destination)
    }

    /// Item providers used when the whole stack is dragged out at once.
    func providers(for items: [TrayItem]) -> [NSItemProvider] {
        items.compactMap { NSItemProvider(contentsOf: $0.url) }
    }

    // MARK: - Thumbnails

    private func warmThumbnails() async {
        for item in items { await makeThumbnail(for: item) }
    }

    private func makeThumbnail(for item: TrayItem) async {
        let request = QLThumbnailGenerator.Request(
            fileAt: item.url,
            size: CGSize(width: 160, height: 160),
            scale: 2,
            representationTypes: .all
        )
        if let rep = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) {
            thumbnails[item.id] = rep.nsImage
        } else {
            thumbnails[item.id] = NSWorkspace.shared.icon(forFile: item.storedPath)
        }
    }

    func thumbnail(for item: TrayItem) -> NSImage? { thumbnails[item.id] }

    // MARK: - Persistence

    private func persist() { Disk.save(items, to: Paths.trayStore) }

    private static let stampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return f
    }()
}
