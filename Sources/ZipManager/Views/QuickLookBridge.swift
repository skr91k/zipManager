import SwiftUI
import QuickLookUI

// MARK: - QLPreviewView wrapper

struct QuickLookPreview: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .normal) ?? QLPreviewView()
        view.previewItem = url as QLPreviewItem
        view.autostarts = true
        return view
    }

    func updateNSView(_ nsView: QLPreviewView, context: Context) {
        if nsView.previewItem as? URL != url {
            nsView.previewItem = url as QLPreviewItem
        }
    }

    static func dismantleNSView(_ nsView: QLPreviewView, coordinator: ()) {
        nsView.previewItem = nil
    }
}

// MARK: - QL panel trigger (for media that needs system app)

struct QLPanelButton: View {
    let url: URL

    var body: some View {
        Button("Open with Quick Look") {
            let panel = QLPreviewPanel.shared()
            panel?.makeKeyAndOrderFront(nil)
        }
    }
}

// MARK: - Temp media viewer

/// Extracts a media entry to a temp file, shows QL preview, deletes on disappear.
struct MediaPreviewView: View {
    let entry: ArchiveEntry
    let document: ArchiveDocument
    @State private var tempURL: URL?
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading \(entry.name)…")
            } else if let err = error {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text(err).foregroundStyle(.secondary)
                }
            } else if let url = tempURL {
                QuickLookPreview(url: url)
            }
        }
        .task {
            await loadMedia()
        }
        .onDisappear {
            if let url = tempURL {
                TempManager.shared.release(url)
                tempURL = nil
            }
        }
    }

    private func loadMedia() async {
        isLoading = true
        do {
            let data = try await ArchiveService.shared.dataForEntry(entry, in: document)
            let url = TempManager.shared.tempURL(name: entry.name)
            try data.write(to: url)
            await MainActor.run {
                tempURL = url
                isLoading = false
            }
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
                isLoading = false
            }
        }
    }
}
