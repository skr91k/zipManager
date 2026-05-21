import SwiftUI
import AppKit

@main
struct ZipManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 900, minHeight: 580)
        }
        .defaultSize(width: 1280, height: 760)
        .commands {
            // Replace default New with our actions
            CommandGroup(replacing: .newItem) {
                Button("Open Archive…") {
                    AppState.shared.openArchivePicker()
                }
                .keyboardShortcut("o", modifiers: .command)

                Button("Open Folder…") {
                    AppState.shared.openFolderPicker()
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])

                Divider()

                Button("New ZIP Archive…") {
                    let panel = NSSavePanel()
                    panel.nameFieldStringValue = "Archive.zip"
                    panel.allowedContentTypes = [.zip]
                    if panel.runModal() == .OK, let url = panel.url {
                        Task {
                            try? await ArchiveService.shared.createEmptyZip(at: url)
                            await AppState.shared.loadArchive(url: url)
                        }
                    }
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            }

            CommandMenu("Archive") {
                Button("Extract All…") {
                    AppState.shared.extractCurrentArchive()
                }
                .keyboardShortcut("e", modifiers: .command)

                Divider()

                Button("Flatten Inner Archives") {
                    AppState.shared.flattenCurrentArchive()
                }

                Button("Merge Archives…") {
                    AppState.shared.mergeArchives()
                }

                Divider()

                Button("Close Archive") {
                    AppState.shared.closeDocument()
                }
                .keyboardShortcut("w", modifiers: [.command, .shift])
            }
        }
    }
}

// MARK: - AppDelegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillTerminate(_ notification: Notification) {
        TempManager.shared.cleanupAll()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    // Called when the OS opens files with this app ("Open With")
    func application(_ application: NSApplication, open urls: [URL]) {
        Task { @MainActor in
            for url in urls {
                AppState.shared.openURL(url)
            }
        }
    }
}
