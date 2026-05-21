import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()
    private init() {
        fsCurrentURL = FileManager.default.homeDirectoryForCurrentUser
    }

    // MARK: - Published state

    @Published var currentDocument: ArchiveDocument?
    @Published var selectedEntry: ArchiveEntry?
    @Published var fsCurrentURL: URL
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var statusMessage: String?
    @Published var progress: Double?
    @Published var searchQuery = ""
    @Published var showCreateSheet = false
    @Published var createTargetURLs: [URL] = []

    // MARK: - Open archive

    func openURL(_ url: URL) {
        guard ArchiveFormat.from(url: url) != nil else { return }
        Task { await loadArchive(url: url) }
    }

    func openArchivePicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = ArchiveService.supportedUTTypes
        panel.title = "Open Archive"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await loadArchive(url: url) }
    }

    func openFolderPicker() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.title = "Open Folder"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        fsCurrentURL = url
        currentDocument = nil
        selectedEntry = nil
    }

    func loadArchive(url: URL) async {
        isLoading = true
        statusMessage = "Loading \(url.lastPathComponent)…"
        selectedEntry = nil
        do {
            let doc = try await ArchiveService.shared.loadArchive(url: url)
            currentDocument = doc
            statusMessage = "\(doc.rootEntries.count) top-level items"
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = nil
        }
        isLoading = false
    }

    // MARK: - Extract

    func extractCurrentArchive() {
        guard let doc = currentDocument else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.title = "Extract to…"
        guard panel.runModal() == .OK, let dest = panel.url else { return }
        Task {
            isLoading = true
            statusMessage = "Extracting…"
            do {
                try await ArchiveService.shared.extractAll(document: doc, to: dest)
                statusMessage = "Extracted to \(dest.lastPathComponent)"
                NSWorkspace.shared.open(dest)
            } catch {
                errorMessage = error.localizedDescription
                statusMessage = nil
            }
            isLoading = false
        }
    }

    func extractEntry(_ entry: ArchiveEntry) {
        guard let doc = currentDocument else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = entry.name
        panel.title = "Extract \(entry.name)"
        guard panel.runModal() == .OK, let dest = panel.url else { return }
        Task {
            isLoading = true
            do {
                let data = try await ArchiveService.shared.dataForEntry(entry, in: doc)
                try data.write(to: dest)
                statusMessage = "Saved \(entry.name)"
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    // MARK: - Create archive

    func compressURLs(_ urls: [URL]) {
        createTargetURLs = urls
        showCreateSheet = true
    }

    func createZip(from urls: [URL], to destination: URL) {
        Task {
            isLoading = true
            statusMessage = "Creating archive…"
            do {
                try await ArchiveService.shared.createZip(from: urls, to: destination)
                statusMessage = "Created \(destination.lastPathComponent)"
                await loadArchive(url: destination)
            } catch {
                errorMessage = error.localizedDescription
                statusMessage = nil
                isLoading = false
            }
        }
    }

    // MARK: - Flatten / Merge

    func flattenCurrentArchive() {
        guard let doc = currentDocument else { return }
        Task {
            isLoading = true
            statusMessage = "Flattening inner archives…"
            do {
                let outURL = try await Flattener.shared.flattenInnerArchives(document: doc)
                statusMessage = "Flattened — opening result"
                await loadArchive(url: outURL)
            } catch {
                errorMessage = error.localizedDescription
                statusMessage = nil
                isLoading = false
            }
        }
    }

    func mergeArchives() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = ArchiveService.supportedUTTypes
        panel.title = "Select archives to merge…"
        guard panel.runModal() == .OK, panel.urls.count >= 2 else { return }
        let urls = panel.urls
        let save = NSSavePanel()
        save.nameFieldStringValue = "Merged.zip"
        save.allowedContentTypes = [.zip]
        guard save.runModal() == .OK, let dest = save.url else { return }
        Task {
            isLoading = true
            statusMessage = "Merging archives…"
            do {
                try await Flattener.shared.mergeArchives(urls: urls, to: dest)
                statusMessage = "Merged into \(dest.lastPathComponent)"
                await loadArchive(url: dest)
            } catch {
                errorMessage = error.localizedDescription
                statusMessage = nil
                isLoading = false
            }
        }
    }

    // MARK: - Helpers

    func closeDocument() {
        currentDocument = nil
        selectedEntry = nil
        statusMessage = nil
    }

    func clearError() { errorMessage = nil }
}
