import Foundation

final class FSItem: Identifiable, ObservableObject {
    let url: URL
    var id: URL { url }
    var name: String { url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent }
    let isDirectory: Bool
    let isArchive: Bool
    let isPackage: Bool

    @Published var children: [FSItem]?
    @Published var isLoading = false

    init(url: URL) {
        self.url = url
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        self.isDirectory = isDir.boolValue
        self.isArchive = ArchiveFormat.from(url: url) != nil
        // .app, .bundle etc treated as packages (non-expandable)
        self.isPackage = !isDir.boolValue ? false : {
            let rsrc = try? url.resourceValues(forKeys: [.isPackageKey])
            return rsrc?.isPackage ?? false
        }()
        if isDirectory && !isPackage {
            children = nil  // will load on demand
        }
    }

    func loadChildren() {
        guard isDirectory, !isPackage, !isLoading else { return }
        isLoading = true
        let url = self.url
        Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            let urls = (try? fm.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            )) ?? []
            let sorted = urls.sorted { a, b in
                let aD = (try? a.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                let bD = (try? b.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                if aD != bD { return aD }
                return a.lastPathComponent.localizedStandardCompare(b.lastPathComponent) == .orderedAscending
            }
            let items = sorted.map { FSItem(url: $0) }
            await MainActor.run {
                self.children = items
                self.isLoading = false
            }
        }
    }

    var fileSize: String {
        guard !isDirectory else { return "" }
        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    var ext: String { url.pathExtension.lowercased() }

    var sfSymbol: String {
        if isDirectory && isPackage { return "app.fill" }
        if isDirectory { return "folder.fill" }
        if isArchive { return "archivebox.fill" }
        switch ext {
        case "png","jpg","jpeg","gif","webp","heic","tiff","bmp": return "photo.fill"
        case "mp4","mov","avi","mkv","m4v": return "video.fill"
        case "mp3","m4a","aac","wav","flac": return "waveform"
        case "pdf": return "doc.richtext.fill"
        case "swift","py","js","ts","rs","go","c","cpp","java","kt","rb","php":
            return "chevron.left.forwardslash.chevron.right"
        case "json","xml","yaml","yml": return "doc.text.fill"
        case "csv","tsv": return "tablecells.fill"
        default: return "doc.fill"
        }
    }
}
