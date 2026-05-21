import SwiftUI

// MARK: - Archive tree (middle column)

struct ArchiveTreeView: View {
    let document: ArchiveDocument
    @EnvironmentObject private var appState: AppState
    @State private var searchText = ""
    @State private var sortMode: SortMode = .name

    enum SortMode: String, CaseIterable {
        case name = "Name", size = "Size", type_ = "Type"
    }

    var filteredEntries: [ArchiveEntry] {
        guard !searchText.isEmpty else { return document.rootEntries }
        return flatSearch(document.rootEntries, query: searchText.lowercased())
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search + sort toolbar
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search in archive", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial)

            Divider()

            if filteredEntries.isEmpty {
                ContentUnavailableView(
                    "No Results",
                    systemImage: "magnifyingglass",
                    description: Text("Nothing matches \"\(searchText)\"")
                )
            } else if searchText.isEmpty {
                // Tree view
                List(document.rootEntries, children: \.optionalChildren, selection: Binding(
                    get: { appState.selectedEntry },
                    set: { appState.selectedEntry = $0 }
                )) { entry in
                    ArchiveEntryRow(entry: entry)
                        .onTapGesture { appState.selectedEntry = entry }
                        .contextMenu { entryContextMenu(entry) }
                }
                .listStyle(.sidebar)
            } else {
                // Flat search results
                List(filteredEntries, id: \.path, selection: Binding(
                    get: { appState.selectedEntry },
                    set: { appState.selectedEntry = $0 }
                )) { entry in
                    ArchiveEntryRow(entry: entry)
                        .onTapGesture { appState.selectedEntry = entry }
                        .contextMenu { entryContextMenu(entry) }
                }
                .listStyle(.sidebar)
            }
        }
        .navigationTitle(document.name)
        .navigationSubtitle(document.format.rawValue)
        .toolbar {
            ToolbarItemGroup {
                Picker("Sort", selection: $sortMode) {
                    ForEach(SortMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 160)

                Button {
                    appState.extractCurrentArchive()
                } label: {
                    Label("Extract All", systemImage: "arrow.down.to.line")
                }

                Menu {
                    Button("Flatten Inner Archives") {
                        appState.flattenCurrentArchive()
                    }
                    Button("Merge Archives…") {
                        appState.mergeArchives()
                    }
                    Divider()
                    Button("Close Archive") {
                        appState.closeDocument()
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }

    @ViewBuilder
    private func entryContextMenu(_ entry: ArchiveEntry) -> some View {
        Button("Preview") {
            appState.selectedEntry = entry
        }
        Divider()
        Button("Extract \(entry.isDirectory ? "Folder" : "File")…") {
            if entry.isDirectory {
                appState.extractCurrentArchive()
            } else {
                appState.extractEntry(entry)
            }
        }
        if !entry.isDirectory {
            Button("Open with System App") {
                openWithSystem(entry)
            }
        }
        Divider()
        Button("Copy Path") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(entry.path, forType: .string)
        }
    }

    private func openWithSystem(_ entry: ArchiveEntry) {
        guard let doc = appState.currentDocument else { return }
        Task {
            if let data = try? await ArchiveService.shared.dataForEntry(entry, in: doc) {
                let url = TempManager.shared.tempURL(name: entry.name)
                try? data.write(to: url)
                NSWorkspace.shared.open(url)
            }
        }
    }

    private func flatSearch(_ entries: [ArchiveEntry], query: String) -> [ArchiveEntry] {
        var results: [ArchiveEntry] = []
        for entry in entries {
            if entry.name.lowercased().contains(query) {
                results.append(entry)
            }
            if let children = entry.children {
                results += flatSearch(children, query: query)
            }
        }
        return results
    }
}

// MARK: - Entry row

struct ArchiveEntryRow: View {
    let entry: ArchiveEntry

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: entry.sfSymbol)
                .foregroundStyle(iconColor)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .lineLimit(1)
                if !entry.isDirectory {
                    Text(entry.sizeString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 1)
    }

    var iconColor: Color {
        if entry.isDirectory { return .blue }
        if entry.isImage { return .green }
        if entry.isMedia { return .purple }
        if entry.isArchive { return .orange }
        if entry.isJSON || entry.isCSV { return .cyan }
        return .secondary
    }
}

// MARK: - ArchiveEntry children helper

extension ArchiveEntry {
    var optionalChildren: [ArchiveEntry]? {
        guard isDirectory, let ch = children else { return nil }
        return ch.isEmpty ? nil : ch
    }
}
