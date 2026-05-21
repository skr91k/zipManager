import Foundation
import ZIPFoundation
import UniformTypeIdentifiers

// MARK: - ArchiveService

actor ArchiveService {
    static let shared = ArchiveService()
    private init() {}

    static let supportedUTTypes: [UTType] = [
        .zip, .gzip,
        UTType("public.tar-archive") ?? .data,
        UTType("com.rarlab.rar-archive") ?? .data,
        UTType("org.7-zip.7-zip-archive") ?? .data,
        UTType("org.gnu.gnu-zip-archive") ?? .data,
    ]

    static func isArchive(url: URL) -> Bool {
        ArchiveFormat.from(url: url) != nil
    }

    // MARK: - Load

    func loadArchive(url: URL) async throws -> ArchiveDocument {
        guard let format = ArchiveFormat.from(url: url) else {
            throw ArchiveError.unsupportedFormat
        }
        let flat: [ArchiveEntry]
        switch format {
        case .zip:
            flat = try loadZip(url: url)
        case .rar:
            flat = try await loadViaProcess(url: url, format: .rar)
        case .sevenZip:
            flat = try await loadViaProcess(url: url, format: .sevenZip)
        case .tar, .tarGzip, .tarBzip2, .tarXz, .gzip:
            flat = try await loadViaProcess(url: url, format: format)
        }
        let tree = buildEntryTree(from: flat)
        return ArchiveDocument(url: url, format: format, rootEntries: tree)
    }

    // MARK: - ZIP via ZIPFoundation

    private func loadZip(url: URL) throws -> [ArchiveEntry] {
        let archive: Archive
        do { archive = try Archive(url: url, accessMode: .read) }
        catch { throw ArchiveError.cannotOpen }
        return archive.compactMap { entry -> ArchiveEntry? in
            let path = entry.path
            let name = (path.hasSuffix("/") ? String(path.dropLast()) : path)
                .split(separator: "/").last.map(String.init) ?? path
            let isDir = entry.type == .directory
            let modDate = entry.fileAttributes[.modificationDate] as? Date
            return ArchiveEntry(
                path: path,
                name: name,
                isDirectory: isDir,
                size: isDir ? 0 : UInt64(entry.uncompressedSize),
                compressedSize: isDir ? 0 : UInt64(entry.compressedSize),
                modifiedDate: modDate
            )
        }
    }

    // MARK: - RAR / 7z / tar via process

    private func loadViaProcess(url: URL, format: ArchiveFormat) async throws -> [ArchiveEntry] {
        switch format {
        case .rar:
            return try await loadRAR(url: url)
        case .sevenZip:
            return try await load7z(url: url)
        default:
            return try await loadTar(url: url, format: format)
        }
    }

    private func loadRAR(url: URL) async throws -> [ArchiveEntry] {
        guard let unrar = findTool("unrar") else {
            throw ArchiveError.toolNotFound("unrar")
        }
        let output = try runProcess(unrar, args: ["l", "-c-", url.path])
        return parseRARListing(output)
    }

    private func load7z(url: URL) async throws -> [ArchiveEntry] {
        guard let tool = findTool("7zz") ?? findTool("7z") else {
            throw ArchiveError.toolNotFound("sevenzip")
        }
        let output = try runProcess(tool, args: ["l", "-slt", url.path])
        return parse7zListing(output)
    }

    private func loadTar(url: URL, format: ArchiveFormat) async throws -> [ArchiveEntry] {
        let tar = "/usr/bin/tar"
        var args = ["-t"]
        if let flag = format.tarFlag, !flag.isEmpty {
            args = ["-t\(flag)"]
        }
        args += ["-f", url.path]
        let output = try runProcess(tar, args: args)
        return parseTarListing(output)
    }

    // MARK: - Extract entry to Data

    func dataForEntry(_ entry: ArchiveEntry, in doc: ArchiveDocument) async throws -> Data {
        switch doc.format {
        case .zip:
            return try extractZipEntry(entry, from: doc.url)
        case .rar:
            return try await extractProcessEntry(
                entry, from: doc.url,
                tool: findTool("unrar") ?? { throw ArchiveError.toolNotFound("unrar") }(),
                args: ["p", "-inul"]
            )
        case .sevenZip:
            guard let tool = findTool("7zz") ?? findTool("7z") else {
                throw ArchiveError.toolNotFound("sevenzip")
            }
            return try await extract7zEntry(entry, from: doc.url, tool: tool)
        default:
            return try await extractTarEntry(entry, from: doc.url, format: doc.format)
        }
    }

    private func extractZipEntry(_ entry: ArchiveEntry, from url: URL) throws -> Data {
        let archive: Archive
        do { archive = try Archive(url: url, accessMode: .read) }
        catch { throw ArchiveError.cannotOpen }
        guard let archEntry = archive[entry.path] else {
            throw ArchiveError.entryNotFound(entry.path)
        }
        var data = Data()
        _ = try archive.extract(archEntry) { chunk in data.append(chunk) }
        return data
    }

    private func extractProcessEntry(_ entry: ArchiveEntry, from url: URL, tool: String, args: [String]) async throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = args + [url.path, entry.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 || !data.isEmpty else {
            throw ArchiveError.entryNotFound(entry.path)
        }
        return data
    }

    private func extract7zEntry(_ entry: ArchiveEntry, from url: URL, tool: String) async throws -> Data {
        let tmp = TempManager.shared.newTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let cleanPath = entry.path.hasSuffix("/") ? String(entry.path.dropLast()) : entry.path
        _ = try runProcess(tool, args: ["e", url.path, "-o\(tmp.path)", cleanPath, "-y"])
        let destURL = tmp.appendingPathComponent(entry.name)
        return try Data(contentsOf: destURL)
    }

    private func extractTarEntry(_ entry: ArchiveEntry, from url: URL, format: ArchiveFormat) async throws -> Data {
        let tar = "/usr/bin/tar"
        var flag = ""
        if let f = format.tarFlag { flag = f }
        var args = ["-x\(flag)Of", url.path, entry.path]
        if flag.isEmpty { args = ["-xOf", url.path, entry.path] }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tar)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard !data.isEmpty else { throw ArchiveError.entryNotFound(entry.path) }
        return data
    }

    // MARK: - Extract all

    func extractAll(document doc: ArchiveDocument, to destination: URL) async throws {
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        switch doc.format {
        case .zip:
            try FileManager.default.unzipItem(at: doc.url, to: destination)
        case .rar:
            guard let tool = findTool("unrar") else { throw ArchiveError.toolNotFound("unrar") }
            let result = try runProcess(tool, args: ["x", "-y", doc.url.path, destination.path + "/"])
            if result.contains("ERROR") { throw ArchiveError.extractionFailed(result) }
        case .sevenZip:
            guard let tool = findTool("7zz") ?? findTool("7z") else { throw ArchiveError.toolNotFound("sevenzip") }
            _ = try runProcess(tool, args: ["x", doc.url.path, "-o\(destination.path)", "-y"])
        default:
            let flag = doc.format.tarFlag ?? ""
            var args = ["-x\(flag)f", doc.url.path, "-C", destination.path]
            if flag.isEmpty { args = ["-xf", doc.url.path, "-C", destination.path] }
            _ = try runProcess("/usr/bin/tar", args: args)
        }
    }

    // MARK: - Create ZIP

    func createZip(from urls: [URL], to destination: URL) async throws {
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        let archive: Archive
        do { archive = try Archive(url: destination, accessMode: .create) }
        catch { throw ArchiveError.cannotOpen }
        for url in urls {
            try addToZip(archive: archive, url: url, base: url.deletingLastPathComponent())
        }
    }

    private func addToZip(archive: Archive, url: URL, base: URL) throws {
        let rel = url.path.replacingOccurrences(of: base.path + "/", with: "")
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        if isDir.boolValue {
            let contents = (try? FileManager.default.contentsOfDirectory(
                at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
            )) ?? []
            for child in contents {
                try addToZip(archive: archive, url: child, base: base)
            }
        } else {
            try archive.addEntry(with: rel, fileURL: url)
        }
    }

    // MARK: - Empty ZIP

    func createEmptyZip(at url: URL) throws {
        do { _ = try Archive(url: url, accessMode: .create) }
        catch { throw ArchiveError.cannotOpen }
    }

    // MARK: - Parsers

    private func parseRARListing(_ output: String) -> [ArchiveEntry] {
        var entries: [ArchiveEntry] = []
        var inListing = false
        let lines = output.components(separatedBy: "\n")
        var i = 0
        while i < lines.count {
            let line = lines[i]
            if line.contains("----") { inListing = !inListing; i += 1; continue }
            guard inListing else { i += 1; continue }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { i += 1; continue }

            // Format: "Attr  Size  Date Time  Name"
            // Try to parse: attributes size date time name
            let parts = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            guard parts.count >= 5 else { i += 1; continue }

            let attr = parts[0]
            let sizeStr = parts[1]
            let name = parts.dropFirst(4).joined(separator: " ")
            let isDir = attr.contains("d") || name.hasSuffix("/")
            let size = UInt64(sizeStr) ?? 0

            entries.append(ArchiveEntry(
                path: name,
                name: (name.hasSuffix("/") ? String(name.dropLast()) : name)
                    .split(separator: "/").last.map(String.init) ?? name,
                isDirectory: isDir,
                size: size,
                compressedSize: 0,
                modifiedDate: nil
            ))
            i += 1
        }
        return entries
    }

    private func parse7zListing(_ output: String) -> [ArchiveEntry] {
        var entries: [ArchiveEntry] = []
        var current: [String: String] = [:]
        let lines = output.components(separatedBy: "\n")
        var pastHeader = false

        for line in lines {
            if line.hasPrefix("----------") { pastHeader = true; continue }
            guard pastHeader else { continue }

            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                if let path = current["Path"], !path.isEmpty {
                    let isDir = current["Folder"] == "+" || current["Attributes"]?.contains("D") == true
                    let size = UInt64(current["Size"] ?? "0") ?? 0
                    let packed = UInt64(current["Packed Size"] ?? "0") ?? 0
                    let name = (isDir ? path : path)
                        .split(separator: "/").last.map(String.init) ?? path
                    entries.append(ArchiveEntry(
                        path: isDir ? path + "/" : path,
                        name: name,
                        isDirectory: isDir,
                        size: size,
                        compressedSize: packed,
                        modifiedDate: nil
                    ))
                }
                current = [:]
            } else if let colonIdx = line.firstIndex(of: ":") {
                let key = line[..<colonIdx].trimmingCharacters(in: .whitespaces)
                let value = line[line.index(after: colonIdx)...].trimmingCharacters(in: .whitespaces)
                current[key] = value
            }
        }
        // last entry
        if let path = current["Path"], !path.isEmpty {
            let isDir = current["Folder"] == "+" || current["Attributes"]?.contains("D") == true
            let size = UInt64(current["Size"] ?? "0") ?? 0
            let name = path.split(separator: "/").last.map(String.init) ?? path
            entries.append(ArchiveEntry(
                path: isDir ? path + "/" : path,
                name: name,
                isDirectory: isDir,
                size: size,
                compressedSize: 0,
                modifiedDate: nil
            ))
        }
        return entries
    }

    private func parseTarListing(_ output: String) -> [ArchiveEntry] {
        output.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0 != "./" }
            .map { path in
                let clean = path.hasPrefix("./") ? String(path.dropFirst(2)) : path
                let isDir = clean.hasSuffix("/")
                let cleanPath = isDir ? String(clean.dropLast()) : clean
                let name = cleanPath.split(separator: "/").last.map(String.init) ?? cleanPath
                return ArchiveEntry(
                    path: path,
                    name: name,
                    isDirectory: isDir,
                    size: 0,
                    compressedSize: 0,
                    modifiedDate: nil
                )
            }
    }

    // MARK: - Utilities

    @discardableResult
    func runProcess(_ executable: String, args: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    func findTool(_ name: String) -> String? {
        let paths = [
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "/usr/bin/\(name)",
            "/bin/\(name)"
        ]
        return paths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}
