import Foundation

final class TempManager {
    static let shared = TempManager()
    private let root: URL
    private var trackedURLs: Set<URL> = []
    private let lock = NSLock()

    private init() {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZipManager", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    // MARK: - API

    func newTempDir() -> URL {
        let dir = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        track(dir)
        return dir
    }

    func tempURL(name: String) -> URL {
        let url = root.appendingPathComponent("\(UUID().uuidString)-\(name)")
        track(url)
        return url
    }

    func release(_ url: URL) {
        lock.withLock { _ = trackedURLs.remove(url) }
        try? FileManager.default.removeItem(at: url)
    }

    func cleanupAll() {
        lock.withLock {
            for url in trackedURLs {
                try? FileManager.default.removeItem(at: url)
            }
            trackedURLs.removeAll()
        }
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: - Private

    private func track(_ url: URL) {
        lock.withLock { trackedURLs.insert(url) }
    }
}
