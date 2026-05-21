import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // Left: File browser
            FileBrowserView()
                .navigationTitle("Files")
                .frame(minWidth: 200)
        } content: {
            // Middle: Archive tree (or placeholder)
            if let doc = appState.currentDocument {
                ArchiveTreeView(document: doc)
                    .frame(minWidth: 200)
            } else {
                noArchiveView
                    .frame(minWidth: 200)
            }
        } detail: {
            // Right: Preview
            if let entry = appState.selectedEntry, let doc = appState.currentDocument {
                PreviewPaneView(entry: entry, document: doc)
                    .id(entry.path)   // force redraw when entry changes
                    .navigationTitle(entry.name)
                    .navigationSubtitle(entry.sizeString)
                    .toolbar { previewToolbar(entry: entry, doc: doc) }
            } else {
                WelcomeView()
            }
        }
        .navigationSplitViewStyle(.balanced)
        // Status / loading overlay
        .overlay(alignment: .bottom) {
            if appState.isLoading || appState.statusMessage != nil {
                statusBar
            }
        }
        // Error alert
        .alert("Error", isPresented: Binding(
            get: { appState.errorMessage != nil },
            set: { if !$0 { appState.clearError() } }
        )) {
            Button("OK") { appState.clearError() }
        } message: {
            Text(appState.errorMessage ?? "")
        }
        // Create archive sheet
        .sheet(isPresented: $appState.showCreateSheet) {
            CreateArchiveSheet(targetURLs: appState.createTargetURLs)
        }
        // Drag & drop onto window
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor in
                        if ArchiveService.isArchive(url: url) {
                            await appState.loadArchive(url: url)
                        } else {
                            appState.compressURLs([url])
                        }
                    }
                }
            }
            return true
        }
    }

    // MARK: - Sub-views

    private var noArchiveView: some View {
        VStack(spacing: 16) {
            Image(systemName: "archivebox")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("No Archive Open")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Open an archive from the file browser or drag one here.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
            Button("Open Archive…") {
                appState.openArchivePicker()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            if appState.isLoading {
                ProgressView()
                    .scaleEffect(0.7)
                    .progressViewStyle(.circular)
            }
            if let msg = appState.statusMessage {
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
    }

    @ToolbarContentBuilder
    private func previewToolbar(entry: ArchiveEntry, doc: ArchiveDocument) -> some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                appState.extractEntry(entry)
            } label: {
                Label("Save As…", systemImage: "arrow.down.to.line")
            }
            .help("Extract and save this file")

            Button {
                openWithSystem(entry: entry, doc: doc)
            } label: {
                Label("Open with System App", systemImage: "arrow.up.forward.app")
            }
            .help("Open with system default app")
        }
    }

    private func openWithSystem(entry: ArchiveEntry, doc: ArchiveDocument) {
        Task {
            if let data = try? await ArchiveService.shared.dataForEntry(entry, in: doc) {
                let url = TempManager.shared.tempURL(name: entry.name)
                try? data.write(to: url)
                NSWorkspace.shared.open(url)
            }
        }
    }
}

// MARK: - Create Archive sheet

struct CreateArchiveSheet: View {
    let targetURLs: [URL]
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var archiveName: String = ""
    @State private var format: ArchiveFormat = .zip
    @State private var includeHidden = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Create Archive")
                .font(.title2.bold())

            VStack(alignment: .leading, spacing: 4) {
                Text("Archive Name").font(.caption).foregroundStyle(.secondary)
                TextField("Archive.zip", text: $archiveName)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Format").font(.caption).foregroundStyle(.secondary)
                Picker("Format", selection: $format) {
                    Text("ZIP").tag(ArchiveFormat.zip)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Items to compress").font(.caption).foregroundStyle(.secondary)
                ForEach(targetURLs, id: \.path) { url in
                    Label(url.lastPathComponent, systemImage: "doc")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Create") {
                    let name = archiveName.isEmpty
                        ? (targetURLs.first?.deletingPathExtension().lastPathComponent ?? "Archive") + ".zip"
                        : (archiveName.hasSuffix(".zip") ? archiveName : archiveName + ".zip")
                    let dest = (targetURLs.first?.deletingLastPathComponent() ?? URL(fileURLWithPath: NSHomeDirectory()))
                        .appendingPathComponent(name)
                    appState.createZip(from: targetURLs, to: dest)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 360, height: 300)
        .onAppear {
            if let first = targetURLs.first {
                archiveName = first.deletingPathExtension().lastPathComponent + ".zip"
            }
        }
    }
}
