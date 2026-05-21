import Foundation

// MARK: - ArchiveFormat

enum ArchiveFormat: String, CaseIterable {
    case zip = "ZIP"
    case rar = "RAR"
    case sevenZip = "7Z"
    case tar = "TAR"
    case tarGzip = "TGZ"
    case tarBzip2 = "TBZ2"
    case tarXz = "TXZ"
    case gzip = "GZ"

    static func from(url: URL) -> ArchiveFormat? {
        switch url.pathExtension.lowercased() {
        case "zip": return .zip
        case "rar": return .rar
        case "7z": return .sevenZip
        case "tar": return .tar
        case "tgz": return .tarGzip
        case "tbz2", "tbz": return .tarBzip2
        case "txz": return .tarXz
        case "gz":
            if url.deletingPathExtension().pathExtension.lowercased() == "tar" {
                return .tarGzip
            }
            return .gzip
        case "bz2":
            if url.deletingPathExtension().pathExtension.lowercased() == "tar" {
                return .tarBzip2
            }
            return nil
        case "xz":
            if url.deletingPathExtension().pathExtension.lowercased() == "tar" {
                return .tarXz
            }
            return nil
        default: return nil
        }
    }

    var canCreate: Bool { self == .zip }

    var tarFlag: String? {
        switch self {
        case .tarGzip: return "z"
        case .tarBzip2: return "j"
        case .tarXz: return "J"
        case .tar: return ""
        default: return nil
        }
    }
}

// MARK: - ArchiveEntry

struct ArchiveEntry: Identifiable, Hashable, Sendable {
    var id: String { path }
    let path: String
    let name: String
    let isDirectory: Bool
    let size: UInt64
    let compressedSize: UInt64
    let modifiedDate: Date?
    var children: [ArchiveEntry]?

    // MARK: Type helpers

    var ext: String { (name as NSString).pathExtension.lowercased() }

    var isArchive: Bool {
        ["zip","rar","7z","tar","gz","bz2","xz","tgz","tbz2","txz"].contains(ext)
    }
    var isImage: Bool {
        ["png","jpg","jpeg","gif","webp","heic","tiff","bmp","svg","ico"].contains(ext)
    }
    var isText: Bool {
        let exts = ["txt","md","markdown","rst","log","ini","cfg","conf","env",
                    "swift","py","js","ts","jsx","tsx","html","htm","css","scss",
                    "json","xml","yaml","yml","toml","sh","bash","zsh","fish",
                    "c","cpp","h","hpp","java","kt","rs","go","rb","php","sql",
                    "r","m","mm","ps1","bat","properties","gradle","cmake",
                    "dockerfile","makefile","gitignore","gitattributes"]
        return exts.contains(ext) || (!isImage && !isMedia && !isArchive && ext.isEmpty)
    }
    var isCSV: Bool { ["csv","tsv"].contains(ext) }
    var isJSON: Bool { ext == "json" }
    var isMedia: Bool {
        let exts = ["mp4","mov","avi","mkv","m4v","wmv","webm","flv",
                    "mp3","m4a","aac","wav","ogg","flac","aiff",
                    "pdf","doc","docx","xls","xlsx","ppt","pptx"]
        return exts.contains(ext)
    }
    var isPDF: Bool { ext == "pdf" }

    var sfSymbol: String {
        if isDirectory { return "folder.fill" }
        if isImage { return "photo.fill" }
        if isJSON { return "doc.text.fill" }
        if isCSV { return "tablecells.fill" }
        if isMedia && isPDF { return "doc.richtext.fill" }
        if isMedia { return "play.circle.fill" }
        if isArchive { return "archivebox.fill" }
        if isText { return "doc.text" }
        return "doc.fill"
    }

    var sizeString: String {
        ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }

    static func == (lhs: ArchiveEntry, rhs: ArchiveEntry) -> Bool { lhs.path == rhs.path }
    func hash(into hasher: inout Hasher) { hasher.combine(path) }
}

// MARK: - ArchiveDocument

struct ArchiveDocument: Identifiable, Sendable {
    let id: UUID
    let url: URL
    let format: ArchiveFormat
    var rootEntries: [ArchiveEntry]
    var name: String { url.lastPathComponent }

    init(url: URL, format: ArchiveFormat, rootEntries: [ArchiveEntry]) {
        self.id = UUID()
        self.url = url
        self.format = format
        self.rootEntries = rootEntries
    }
}

// MARK: - Tree builder

func buildEntryTree(from flat: [ArchiveEntry]) -> [ArchiveEntry] {
    var byParent: [String: [ArchiveEntry]] = [:]

    for entry in flat {
        let cleanPath = entry.path.hasSuffix("/") ? String(entry.path.dropLast()) : entry.path
        let parent: String
        if let idx = cleanPath.lastIndex(of: "/") {
            parent = String(cleanPath[..<idx])
        } else {
            parent = ""
        }
        byParent[parent, default: []].append(entry)
    }

    func children(of parent: String) -> [ArchiveEntry] {
        (byParent[parent] ?? [])
            .sorted { a, b in
                if a.isDirectory != b.isDirectory { return a.isDirectory }
                return a.name.localizedStandardCompare(b.name) == .orderedAscending
            }
            .map { entry in
                guard entry.isDirectory else { return entry }
                let cleanPath = entry.path.hasSuffix("/") ? String(entry.path.dropLast()) : entry.path
                var copy = entry
                copy.children = children(of: cleanPath)
                return copy
            }
    }

    return children(of: "")
}

// MARK: - Errors

enum ArchiveError: LocalizedError {
    case cannotOpen
    case entryNotFound(String)
    case toolNotFound(String)
    case extractionFailed(String)
    case unsupportedFormat

    var errorDescription: String? {
        switch self {
        case .cannotOpen: return "Cannot open archive"
        case .entryNotFound(let p): return "Entry not found: \(p)"
        case .toolNotFound(let t): return "\(t) not found — install via: brew install \(t == "unrar" ? "unrar" : "sevenzip")"
        case .extractionFailed(let m): return "Extraction failed: \(m)"
        case .unsupportedFormat: return "Unsupported archive format"
        }
    }
}
