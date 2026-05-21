import SwiftUI

// MARK: - File browser sidebar

struct FileBrowserView: View {
    @EnvironmentObject private var appState: AppState
    @State private var currentURL: URL = FileManager.default.homeDirectoryForCurrentUser
    @State private var items: [FSItem] = []
    @State private var selectedItem: FSItem?
    @State private var isLoading = false
    @State private var history: [URL] = []
    @State private var historyIndex: Int = -1
    @State private var sortAscending = true
    @State private var showHidden = false

    var body: some View {
        VStack(spacing: 0) {
            navBar
            Divider()
            fileList
            Divider()
            statusBar
        }
        .onAppear { navigate(to: currentURL, addToHistory: true) }
        .onChange(of: appState.fsCurrentURL) { _, url in
            navigate(to: url, addToHistory: true)
        }
    }

    // MARK: - Nav bar

    private var navBar: some View {
        HStack(spacing: 4) {
            Button {
                guard historyIndex > 0 else { return }
                historyIndex -= 1
                navigate(to: history[historyIndex], addToHistory: false)
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.plain)
            .disabled(historyIndex <= 0)

            Button {
                guard historyIndex < history.count - 1 else { return }
                historyIndex += 1
                navigate(to: history[historyIndex], addToHistory: false)
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.plain)
            .disabled(historyIndex >= history.count - 1)

            Button {
                let parent = currentURL.deletingLastPathComponent()
                if parent != currentURL {
                    navigate(to: parent, addToHistory: true)
                }
            } label: {
                Image(systemName: "arrow.up")
            }
            .buttonStyle(.plain)

            Text(currentURL.lastPathComponent.isEmpty ? "/" : currentURL.lastPathComponent)
                .font(.headline)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(currentURL.path)

            Button {
                showOpenPanel()
            } label: {
                Image(systemName: "folder.badge.plus")
            }
            .buttonStyle(.plain)
            .help("Open folder")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    // MARK: - File list

    private var fileList: some View {
        List(items, id: \.url, selection: Binding(
            get: { selectedItem?.url },
            set: { url in
                selectedItem = items.first { $0.url == url }
            }
        )) { item in
            FSItemRow(item: item)
                .onTapGesture { handleDoubleClick(item) }
                .contextMenu { contextMenu(for: item) }
        }
        .listStyle(.sidebar)
        .overlay {
            if isLoading {
                ProgressView()
            } else if items.isEmpty {
                ContentUnavailableView("Empty Folder", systemImage: "folder")
            }
        }
    }

    // MARK: - Status bar

    private var statusBar: some View {
        HStack {
            Text("\(items.count) items")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Toggle(isOn: $showHidden) {
                Text("Hidden").font(.caption)
            }
            .toggleStyle(.checkbox)
            .onChange(of: showHidden) { _, _ in navigate(to: currentURL, addToHistory: false) }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }

    // MARK: - Navigation

    private func navigate(to url: URL, addToHistory: Bool) {
        currentURL = url
        if addToHistory {
            history = Array(history.prefix(historyIndex + 1)) + [url]
            historyIndex = history.count - 1
        }
        loadItems()
    }

    private func loadItems() {
        isLoading = true
        let url = currentURL
        let showHidden = showHidden
        Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            let options: FileManager.DirectoryEnumerationOptions = showHidden ? [] : [.skipsHiddenFiles]
            let urls = (try? fm.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey, .fileSizeKey],
                options: options
            )) ?? []
            let sorted = urls.sorted { a, b in
                let aD = (try? a.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                let bD = (try? b.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                if aD != bD { return aD }
                return a.lastPathComponent.localizedStandardCompare(b.lastPathComponent) == .orderedAscending
            }
            let newItems = sorted.map { FSItem(url: $0) }
            await MainActor.run {
                self.items = newItems
                self.isLoading = false
            }
        }
    }

    // MARK: - Actions

    private func handleDoubleClick(_ item: FSItem) {
        if item.isArchive {
            Task { await appState.loadArchive(url: item.url) }
        } else if item.isDirectory && !item.isPackage {
            navigate(to: item.url, addToHistory: true)
        } else {
            NSWorkspace.shared.open(item.url)
        }
    }

    @ViewBuilder
    private func contextMenu(for item: FSItem) -> some View {
        if item.isArchive {
            Button("Open Archive") {
                Task { await appState.loadArchive(url: item.url) }
            }
        }
        if item.isDirectory {
            Button("Browse Folder") {
                navigate(to: item.url, addToHistory: true)
            }
        }
        Divider()
        Button("Compress to ZIP") {
            compressItems([item.url])
        }
        if !item.isDirectory && !item.isArchive {
            Button("Open with System App") {
                NSWorkspace.shared.open(item.url)
            }
        }
        Divider()
        Button("Show in Finder") {
            NSWorkspace.shared.selectFile(item.url.path, inFileViewerRootedAtPath: item.url.deletingLastPathComponent().path)
        }
        Button("Copy Path") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(item.url.path, forType: .string)
        }
    }

    private func compressItems(_ urls: [URL]) {
        let panel = NSSavePanel()
        let defaultName = urls.count == 1
            ? urls[0].deletingPathExtension().lastPathComponent + ".zip"
            : "Archive.zip"
        panel.nameFieldStringValue = defaultName
        panel.directoryURL = urls[0].deletingLastPathComponent()
        panel.allowedContentTypes = [.zip]
        guard panel.runModal() == .OK, let dest = panel.url else { return }
        appState.createZip(from: urls, to: dest)
    }

    private func showOpenPanel() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.title = "Open Folder"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        navigate(to: url, addToHistory: true)
    }
}

// MARK: - FSItem row

struct FSItemRow: View {
    @ObservedObject var item: FSItem

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: item.sfSymbol)
                .foregroundStyle(iconColor)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name)
                    .lineLimit(1)
                if !item.fileSize.isEmpty {
                    Text(item.fileSize)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 1)
    }

    var iconColor: Color {
        if item.isDirectory { return .blue }
        if item.isArchive { return .orange }
        switch item.ext {
        case "png","jpg","jpeg","gif","webp": return .green
        case "mp4","mov","avi","mkv": return .purple
        case "mp3","m4a","aac","wav": return .pink
        case "pdf": return .red
        case "swift","py","js","ts","rs","go": return .cyan
        default: return .secondary
        }
    }
}

// MARK: - Drop support for opening archives

struct ArchiveDropDelegate: DropDelegate {
    @EnvironmentObject var appState: AppState

    func performDrop(info: DropInfo) -> Bool {
        let providers = info.itemProviders(for: [.fileURL])
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in
                    if ArchiveService.isArchive(url: url) {
                        await appState.loadArchive(url: url)
                    }
                }
            }
        }
        return true
    }

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.fileURL])
    }
}
