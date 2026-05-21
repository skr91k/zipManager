import SwiftUI
import AppKit

// MARK: - Preview dispatcher

struct PreviewPaneView: View {
    let entry: ArchiveEntry
    let document: ArchiveDocument

    var body: some View {
        if entry.isDirectory {
            DirectoryInfoView(entry: entry)
        } else if entry.isImage {
            ImagePreviewView(entry: entry, document: document)
        } else if entry.isCSV {
            CSVPreviewView(entry: entry, document: document)
        } else if entry.isJSON {
            CodePreviewView(entry: entry, document: document, language: .json)
        } else if entry.isText {
            CodePreviewView(entry: entry, document: document, language: Language.from(ext: entry.ext))
        } else if entry.isMedia {
            MediaPreviewView(entry: entry, document: document)
        } else {
            UnknownPreviewView(entry: entry, document: document)
        }
    }
}

// MARK: - Directory info

struct DirectoryInfoView: View {
    let entry: ArchiveEntry

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "folder.fill")
                .font(.system(size: 64))
                .foregroundStyle(.blue)
            Text(entry.name)
                .font(.title2.bold())
            if let children = entry.children {
                Text("\(children.count) items")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Image preview

struct ImagePreviewView: View {
    let entry: ArchiveEntry
    let document: ArchiveDocument
    @State private var image: NSImage?
    @State private var isLoading = true
    @State private var zoom: Double = 1.0

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else if let img = image {
                ScrollView([.horizontal, .vertical]) {
                    Image(nsImage: img)
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(zoom)
                        .gesture(MagnifyGesture()
                            .onChanged { zoom = max(0.1, min(10, $0.magnification)) }
                        )
                }
                .toolbar {
                    ToolbarItemGroup {
                        Button { zoom = max(0.1, zoom - 0.25) } label: {
                            Image(systemName: "minus.magnifyingglass")
                        }
                        Button { zoom = 1.0 } label: {
                            Image(systemName: "1.magnifyingglass")
                        }
                        Button { zoom = min(10, zoom + 0.25) } label: {
                            Image(systemName: "plus.magnifyingglass")
                        }
                    }
                }
            } else {
                Text("Cannot load image").foregroundStyle(.secondary)
            }
        }
        .task(id: entry.path) {
            isLoading = true
            if let data = try? await ArchiveService.shared.dataForEntry(entry, in: document),
               let img = NSImage(data: data) {
                image = img
            }
            isLoading = false
        }
    }
}

// MARK: - Text / Code view (uses NSTextView for perf)

struct CodePreviewView: View {
    let entry: ArchiveEntry
    let document: ArchiveDocument
    let language: Language
    @State private var attributed: NSAttributedString?
    @State private var isLoading = true
    @State private var rawText: String = ""

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else if let attr = attributed {
                TextEditorView(attributedString: attr)
                    .toolbar {
                        ToolbarItem {
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(rawText, forType: .string)
                            } label: {
                                Label("Copy", systemImage: "doc.on.doc")
                            }
                        }
                    }
            } else {
                Text("Cannot decode file").foregroundStyle(.secondary)
            }
        }
        .task(id: entry.path) {
            isLoading = true
            if let data = try? await ArchiveService.shared.dataForEntry(entry, in: document),
               let str = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) {
                rawText = str
                // Run syntax highlighting off the main thread; wrap result to satisfy Sendable
                let highlighted = SyntaxHighlighter.highlight(str, language: language)
                attributed = highlighted
            }
            isLoading = false
        }
    }
}

// NSTextView wrapper for read-only rich text
struct TextEditorView: NSViewRepresentable {
    let attributedString: NSAttributedString

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView
        textView.isEditable = false
        textView.isSelectable = true
        textView.backgroundColor = NSColor(named: "codeBackground") ?? .textBackgroundColor
        textView.textContainerInset = CGSize(width: 8, height: 8)
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        let textView = nsView.documentView as! NSTextView
        textView.textStorage?.setAttributedString(attributedString)
    }
}

// MARK: - CSV preview

struct CSVPreviewView: View {
    let entry: ArchiveEntry
    let document: ArchiveDocument
    @State private var headers: [String] = []
    @State private var rows: [[String]] = []
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else if headers.isEmpty {
                Text("Empty or invalid CSV").foregroundStyle(.secondary)
            } else {
                CSVTableView(headers: headers, rows: rows)
            }
        }
        .task(id: entry.path) {
            isLoading = true
            if let data = try? await ArchiveService.shared.dataForEntry(entry, in: document),
               let str = String(data: data, encoding: .utf8) {
                let parsed = parseCSV(str, separator: entry.ext == "tsv" ? "\t" : ",")
                if !parsed.isEmpty {
                    headers = parsed[0]
                    rows = Array(parsed.dropFirst())
                }
            }
            isLoading = false
        }
    }

    private func parseCSV(_ text: String, separator: String) -> [[String]] {
        text.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { line in
                // Simple CSV parse (handles quoted fields)
                var fields: [String] = []
                var current = ""
                var inQuotes = false
                for (_, char) in line.enumerated() {
                    if char == "\"" {
                        inQuotes.toggle()
                    } else if String(char) == separator && !inQuotes {
                        fields.append(current)
                        current = ""
                    } else {
                        current.append(char)
                    }
                }
                fields.append(current)
                return fields
            }
    }
}

struct CSVTableView: View {
    let headers: [String]
    let rows: [[String]]
    @State private var sortColumn: Int?
    @State private var sortAscending = true

    var sortedRows: [[String]] {
        guard let col = sortColumn else { return rows }
        return rows.sorted { a, b in
            let av = col < a.count ? a[col] : ""
            let bv = col < b.count ? b[col] : ""
            return sortAscending
                ? av.localizedStandardCompare(bv) == .orderedAscending
                : av.localizedStandardCompare(bv) == .orderedDescending
        }
    }

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 0) {
                // Header row
                HStack(spacing: 0) {
                    ForEach(Array(headers.enumerated()), id: \.0) { col, header in
                        Button {
                            if sortColumn == col { sortAscending.toggle() }
                            else { sortColumn = col; sortAscending = true }
                        } label: {
                            HStack {
                                Text(header).fontWeight(.semibold)
                                if sortColumn == col {
                                    Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                                        .font(.caption)
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .frame(minWidth: 120, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        Divider()
                    }
                }
                .background(.quaternary)
                Divider()
                // Data rows
                ForEach(Array(sortedRows.enumerated()), id: \.0) { rowIdx, row in
                    HStack(spacing: 0) {
                        ForEach(Array(headers.enumerated()), id: \.0) { col, _ in
                            Text(col < row.count ? row[col] : "")
                                .font(.system(.body, design: .monospaced))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .frame(minWidth: 120, alignment: .leading)
                            Divider()
                        }
                    }
                    .background(rowIdx % 2 == 0 ? Color.clear : Color.primary.opacity(0.04))
                    Divider()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Unknown / binary

struct UnknownPreviewView: View {
    let entry: ArchiveEntry
    let document: ArchiveDocument

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: entry.sfSymbol)
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text(entry.name)
                .font(.title3.bold())
            Text(entry.sizeString)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button("Open with System App") {
                    openWithSystem()
                }
                .buttonStyle(.borderedProminent)

                Button("Extract & Save…") {
                    AppState.shared.extractEntry(entry)
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func openWithSystem() {
        Task {
            if let data = try? await ArchiveService.shared.dataForEntry(entry, in: document) {
                let url = TempManager.shared.tempURL(name: entry.name)
                try? data.write(to: url)
                NSWorkspace.shared.open(url)
            }
        }
    }
}

// MARK: - Welcome / empty state

struct WelcomeView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "archivebox")
                .font(.system(size: 72))
                .foregroundStyle(.secondary)
            Text("ZipManager")
                .font(.largeTitle.bold())
            Text("Browse, preview, create and extract ZIP · RAR · 7Z · TAR archives without leaving the app.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 320)
            VStack(alignment: .leading, spacing: 8) {
                Label("Open an archive from the file browser", systemImage: "folder")
                Label("Drag & drop archive files onto the window", systemImage: "arrow.down.doc")
                Label("Right-click files to compress them", systemImage: "archivebox.fill")
            }
            .foregroundStyle(.secondary)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
