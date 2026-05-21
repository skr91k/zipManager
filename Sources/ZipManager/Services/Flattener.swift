import Foundation
import ZIPFoundation

actor Flattener {
    static let shared = Flattener()
    private init() {}

    // MARK: - Flatten inner archives

    /// Extracts all nested archives inside `document` and repacks them flat into a new ZIP.
    func flattenInnerArchives(document: ArchiveDocument) async throws -> URL {
        let outName = document.url.deletingPathExtension().lastPathComponent + "_flattened.zip"
        let outURL = document.url.deletingLastPathComponent().appendingPathComponent(outName)
        if FileManager.default.fileExists(atPath: outURL.path) {
            try FileManager.default.removeItem(at: outURL)
        }

        let outArchive: Archive
        do { outArchive = try Archive(url: outURL, accessMode: .create) }
        catch { throw ArchiveError.cannotOpen }

        let tmpDir = TempManager.shared.newTempDir()
        defer { TempManager.shared.release(tmpDir) }

        try await ArchiveService.shared.extractAll(document: document, to: tmpDir)
        try await addFlatDirectory(tmpDir, into: outArchive, base: tmpDir)

        return outURL
    }

    private func addFlatDirectory(_ dir: URL, into archive: Archive, base: URL) async throws {
        let fm = FileManager.default
        let contents = try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
        for item in contents {
            var isDir: ObjCBool = false
            fm.fileExists(atPath: item.path, isDirectory: &isDir)
            if isDir.boolValue {
                if ArchiveFormat.from(url: item) != nil {
                    let innerTmp = TempManager.shared.newTempDir()
                    defer { TempManager.shared.release(innerTmp) }
                    if item.pathExtension.lowercased() == "zip" {
                        try fm.unzipItem(at: item, to: innerTmp)
                    } else {
                        _ = try await ArchiveService.shared.runProcess(
                            "/usr/bin/tar", args: ["-xf", item.path, "-C", innerTmp.path])
                    }
                    try await addFlatDirectory(innerTmp, into: archive, base: innerTmp)
                } else {
                    try await addFlatDirectory(item, into: archive, base: base)
                }
            } else if ArchiveFormat.from(url: item) != nil {
                if item.pathExtension.lowercased() == "zip" {
                    let innerTmp = TempManager.shared.newTempDir()
                    defer { TempManager.shared.release(innerTmp) }
                    try fm.unzipItem(at: item, to: innerTmp)
                    try await addFlatDirectory(innerTmp, into: archive, base: innerTmp)
                } else {
                    let rel = item.path.replacingOccurrences(of: base.path + "/", with: "")
                    try archive.addEntry(with: rel, fileURL: item)
                }
            } else {
                let rel = item.path.replacingOccurrences(of: base.path + "/", with: "")
                try archive.addEntry(with: rel, fileURL: item)
            }
        }
    }

    // MARK: - Merge archives

    func mergeArchives(urls: [URL], to destination: URL) async throws {
        let outArchive: Archive
        do { outArchive = try Archive(url: destination, accessMode: .create) }
        catch { throw ArchiveError.cannotOpen }

        for url in urls {
            let doc = try await ArchiveService.shared.loadArchive(url: url)
            let tmpDir = TempManager.shared.newTempDir()
            defer { TempManager.shared.release(tmpDir) }
            try await ArchiveService.shared.extractAll(document: doc, to: tmpDir)

            // Use archive name as prefix to avoid collisions
            let prefix = url.deletingPathExtension().lastPathComponent
            try addDirectoryWithPrefix(tmpDir, prefix: prefix, into: outArchive, base: tmpDir)
        }
    }

    private func addDirectoryWithPrefix(_ dir: URL, prefix: String, into archive: Archive, base: URL) throws {
        let fm = FileManager.default
        let contents = try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
        for item in contents {
            var isDir: ObjCBool = false
            fm.fileExists(atPath: item.path, isDirectory: &isDir)
            let rel = prefix + "/" + item.path.replacingOccurrences(of: base.path + "/", with: "")
            if isDir.boolValue {
                try addDirectoryWithPrefix(item, prefix: prefix, into: archive, base: base)
            } else {
                try archive.addEntry(with: rel, fileURL: item)
            }
        }
    }
}
