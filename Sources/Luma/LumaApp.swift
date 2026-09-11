import SwiftUI
import AppKit

@main
struct LumaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var library: Library

    init() {
        let args = ProcessInfo.processInfo.arguments
        // An isolated library for repeatable development / UI verification.
        if let index = args.firstIndex(of: "--library"), args.count > index + 1 {
            _library = StateObject(wrappedValue: Library(storageURL: URL(fileURLWithPath: args[index + 1])))
        } else { _library = StateObject(wrappedValue: Library()) }
    }

    var body: some Scene {
        Window("光隙 · Luma", id: "gallery") {
            GalleryView(library: library)
                .frame(minWidth: 860, minHeight: 600)
                .preferredColorScheme(.dark)
                .onAppear {
                    delegate.onOpenPhotos = { library.add($0) }
                    delegate.flushPendingPhotos()
                }
        }
        .defaultSize(width: 1280, height: 850)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("导入照片…") { library.importPanel() }.keyboardShortcut("o")
                Button("打开文件夹…") { library.importPanel(foldersOnly: true) }.keyboardShortcut("o", modifiers: [.command, .shift])
            }
            CommandMenu("照片") {
                Button("上一张") { library.step(-1) }.keyboardShortcut(.leftArrow, modifiers: [])
                    .disabled(!library.canStepBack)
                Button("下一张") { library.step(1) }.keyboardShortcut(.rightArrow, modifiers: [])
                    .disabled(!library.canStepForward)
                Divider()
                Button(library.folderMode ? "切换为全部照片" : "切换为文件夹模式") { library.setFolderMode(!library.folderMode) }
                Button("重新读取文件夹") { Task { await library.refreshFolders(reportErrors: true) } }
                    .keyboardShortcut("r").disabled(library.folderRoots.isEmpty || library.refreshingFolders)
                Button("显示拍摄参数") { library.showInfo.toggle() }.keyboardShortcut("i", modifiers: [])
                Button("显示缩略图") { library.showFilmstrip.toggle() }.keyboardShortcut("t", modifiers: [])
                Button("适应窗口") { library.zoom = 1 }.keyboardShortcut("0")
                Button("放大") { library.zoom = min(6, library.zoom + 0.5) }.keyboardShortcut("+")
                Button("缩小") { library.zoom = max(1, library.zoom - 0.5) }.keyboardShortcut("-")
                Divider()
                Button("在 Finder 中显示") { library.reveal() }.disabled(library.selected == nil)
                Button("重新定位原文件…") { library.relink() }.disabled(library.selected == nil)
                Button("从列表移除") { library.removeSelected() }.keyboardShortcut(.delete, modifiers: [])
                    .disabled(library.selected == nil)
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var onOpenPhotos: (([URL]) -> Void)?
    private var pendingPhotos: [URL] = []
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func application(_ application: NSApplication, open urls: [URL]) {
        pendingPhotos.append(contentsOf: urls)
        flushPendingPhotos()
    }
    func flushPendingPhotos() {
        guard let onOpenPhotos, !pendingPhotos.isEmpty else { return }
        let photos = pendingPhotos
        pendingPhotos = []
        onOpenPhotos(photos)
    }
}
