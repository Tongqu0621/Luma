import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class Library: ObservableObject {
    @Published var photos: [PhotoReference] = []
    @Published var selectedID: UUID?
    @Published var loaded: LoadedPhoto?
    @Published var loading = false
    @Published var loadError: String?
    @Published var notice: String?
    @Published var showInfo = true
    @Published var showFilmstrip = true
    @Published var minimal = false
    @Published var zoom: CGFloat = 1
    @Published private(set) var folderMode = false
    @Published private(set) var folderRoots: [FolderReference] = []
    @Published private(set) var folderPaths: [String] = []
    @Published private(set) var expandedFolderPath: String?
    @Published private(set) var refreshingFolders = false
    private var excludedPaths: Set<String> = []
    private var folderRevision = 0
    private var task: Task<Void, Never>?
    private var activeOpenPanel: NSOpenPanel?
    private let storageURL: URL

    struct Archive: Codable {
        let photos: [PhotoReference]
        let selectedID: UUID?
        var folderRoots: [FolderReference]?
        var folderPaths: [String]?
        var folderMode: Bool?
        var expandedFolderPath: String?
        var excludedPaths: [String]?
    }

    init(storageURL: URL? = nil, restore: Bool = true) {
        self.storageURL = storageURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Luma/library.json")
        if restore {
            do {
                if FileManager.default.fileExists(atPath: self.storageURL.path) {
                    let archive = try JSONDecoder().decode(Archive.self, from: Data(contentsOf: self.storageURL))
                    folderRoots = archive.folderRoots ?? []
                    folderPaths = archive.folderPaths ?? []
                    folderMode = archive.folderMode ?? false
                    excludedPaths = Set(archive.excludedPaths ?? [])
                    photos = archive.photos.map { old in
                        let url = old.resolve()
                        guard FileManager.default.fileExists(atPath: url.path) else { return old }
                        var refreshed = PhotoReference(url: url); refreshed.id = old.id
                        return refreshed
                    }
                    select(photos.contains(where: { $0.id == archive.selectedID }) ? archive.selectedID : photos.first?.id)
                    expandedFolderPath = archive.expandedFolderPath
                    save()
                }
            } catch { notice = "无法恢复上次的照片列表：\(error.localizedDescription)" }
        }
    }

    var selected: PhotoReference? { photos.first { $0.id == selectedID } }
    var selectedIndex: Int { photos.firstIndex { $0.id == selectedID } ?? 0 }

    var folders: [PhotoFolder] {
        let grouped = Dictionary(grouping: photos) { URL(fileURLWithPath: $0.path).deletingLastPathComponent().path }
        let paths = Set(folderPaths).union(grouped.keys)
        return paths.sorted { $0.localizedStandardCompare($1) == .orderedAscending }.map { path in
            // Show relative hierarchy when a parent folder is present, keeping equal names distinguishable.
            let ancestor = paths.filter { FolderReference.contains(path, in: $0) }.min { $0.count < $1.count } ?? path
            let parent = URL(fileURLWithPath: ancestor).deletingLastPathComponent().path
            let title = path.hasPrefix(parent + "/") ? String(path.dropFirst(parent.count + 1)).replacingOccurrences(of: "/", with: " / ") : path
            return PhotoFolder(path: path, title: title, photos: grouped[path] ?? [])
        }
    }

    var expandedFolder: PhotoFolder? { folders.first { $0.path == expandedFolderPath } }
    var browsingPhotos: [PhotoReference] { folderMode ? (expandedFolder?.photos ?? []) : photos }
    var browsingIndex: Int { browsingPhotos.firstIndex { $0.id == selectedID } ?? 0 }
    var canStepBack: Bool { !browsingPhotos.isEmpty && browsingIndex > 0 }
    var canStepForward: Bool { !browsingPhotos.isEmpty && browsingIndex < browsingPhotos.count - 1 }

    func setFolderMode(_ enabled: Bool) {
        folderMode = enabled
        showFilmstrip = true
        if enabled && expandedFolderPath == nil {
            expandedFolderPath = selected.map { URL(fileURLWithPath: $0.path).deletingLastPathComponent().path } ?? folders.first?.path
        }
        save()
    }

    func toggleFolder(_ folder: PhotoFolder) {
        if expandedFolderPath == folder.path { expandedFolderPath = nil; save(); return }
        expandedFolderPath = folder.path
        if !folder.photos.contains(where: { $0.id == selectedID }) { select(folder.photos.first?.id) }
        save()
    }

    func refreshFolders(reportErrors: Bool = false) async {
        guard !folderRoots.isEmpty, !refreshingFolders else { return }
        refreshingFolders = true
        defer { refreshingFolders = false }
        let roots = folderRoots
        let revision = folderRevision
        let scans = await Task.detached(priority: .utility) { roots.map(FolderReader.scan) }.value
        guard revision == folderRevision else { return }
        let successful = scans.filter(\.complete)
        let originalIDs = Dictionary(photos.map { ($0.resolve().resolvingSymlinksInPath().path, $0.id) }, uniquingKeysWith: { first, _ in first })
        let previousSelection = selectedID
        let previousIndex = selectedIndex
        let oldExpanded = expandedFolderPath
        photos.removeAll { photo in successful.contains { FolderReference.contains(photo.path, in: $0.original.path) || FolderReference.contains(photo.path, in: $0.current.path) } }
        folderPaths.removeAll { path in successful.contains { FolderReference.contains(path, in: $0.original.path) || FolderReference.contains(path, in: $0.current.path) } }
        var known = Set(photos.map { $0.resolve().resolvingSymlinksInPath().path })
        for scan in successful {
            if let index = folderRoots.firstIndex(of: scan.original) { folderRoots[index] = scan.current }
            folderPaths.append(contentsOf: scan.directories)
            for var photo in scan.photos {
                let canonical = photo.resolve().resolvingSymlinksInPath().path
                guard !excludedPaths.contains(canonical), known.insert(canonical).inserted else { continue }
                if let id = originalIDs[canonical] { photo.id = id }
                photos.append(photo)
            }
        }
        folderPaths = Array(Set(folderPaths))
        if !photos.contains(where: { $0.id == previousSelection }) {
            let next: PhotoReference?
            if folderMode, let openFolder = expandedFolder {
                next = openFolder.photos.first
            } else {
                next = photos.isEmpty ? nil : photos[min(previousIndex, photos.count - 1)]
            }
            select(next?.id)
        } else if reportErrors {
            select(previousSelection)
        }
        if let oldExpanded, folders.contains(where: { $0.path == oldExpanded }) { expandedFolderPath = oldExpanded }
        else if oldExpanded != nil { expandedFolderPath = selected.map { URL(fileURLWithPath: $0.path).deletingLastPathComponent().path } }
        else { expandedFolderPath = nil }
        if reportErrors && successful.count < scans.count { notice = "部分文件夹暂时无法读取，已保留原有列表。请连接硬盘或检查文件夹访问权限。" }
        save()
    }

    func importPanel(foldersOnly: Bool = false) {
        if let activeOpenPanel { activeOpenPanel.makeKeyAndOrderFront(nil); return }
        let panel = NSOpenPanel()
        activeOpenPanel = panel
        panel.title = foldersOnly ? "打开照片文件夹" : "把照片带进光隙"
        panel.message = foldersOnly ? "直接读取原目录，在底部按文件夹展开照片。包含子文件夹，原片保留在原处。"
            : "可选择多张照片或整个文件夹（包含子文件夹）。原片会保留在原位置。"
        panel.prompt = foldersOnly ? "打开文件夹" : "导入照片"
        panel.canChooseDirectories = true
        panel.canChooseFiles = !foldersOnly
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.image, .rawImage] + PhotoReader.rawExtensions.compactMap { UTType(filenameExtension: $0) }
        panel.begin { [weak self] response in
            Task { @MainActor in
                self?.activeOpenPanel = nil
                if response == .OK { self?.add(panel.urls) }
            }
        }
    }

    func add(_ urls: [URL]) {
        folderRevision += 1
        // Keep directory access alive until every child has its own read-only bookmark.
        let scoped = urls.filter { $0.startAccessingSecurityScopedResource() }
        defer { scoped.forEach { $0.stopAccessingSecurityScopedResource() } }
        var expanded: [PhotoReference] = []
        var unreadableFolders = 0
        for url in urls {
            if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                let root = FolderReference(url: url)
                let scan = FolderReader.scan(root)
                if !scan.complete { unreadableFolders += 1 }
                if !folderRoots.contains(where: { FolderReference.contains(root.path, in: $0.path) }) {
                    folderRoots.removeAll { FolderReference.contains($0.path, in: root.path) }
                    folderRoots.append(root)
                }
                folderPaths = Array(Set(folderPaths + scan.directories))
                expanded.append(contentsOf: scan.photos)
                setFolderMode(true)
            } else if url.isFileURL { expanded.append(PhotoReference(url: url)) }
        }
        var known = Set(photos.map { $0.resolve().resolvingSymlinksInPath().standardizedFileURL.path })
        var additions: [PhotoReference] = []
        var skipped = 0
        for photo in expanded {
            let url = URL(fileURLWithPath: photo.path)
            guard url.isFileURL, PhotoReader.supports(url) else { skipped += 1; continue }
            let canonical = url.resolvingSymlinksInPath().standardizedFileURL.path
            excludedPaths.remove(canonical)
            if known.insert(canonical).inserted { additions.append(photo) }
        }
        photos.append(contentsOf: additions)
        if let first = additions.first { select(first.id) }
        else if !urls.isEmpty && !urls.contains(where: { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }) {
            notice = skipped > 0 || expanded.isEmpty ? "所选文件中没有可导入的照片。" : "这些照片已经在列表中了。"
        }
        if folderMode && expandedFolderPath == nil { expandedFolderPath = selected.map { URL(fileURLWithPath: $0.path).deletingLastPathComponent().path } ?? folders.first?.path }
        if skipped > 0 && !additions.isEmpty { notice = "已导入 \(additions.count) 张照片，跳过 \(skipped) 个非照片文件。" }
        if unreadableFolders > 0 { notice = "已导入 \(additions.count) 张照片。部分文件夹无法访问，请检查权限后重新导入。" }
        save()
    }

    func select(_ id: UUID?) {
        task?.cancel()
        selectedID = id
        zoom = 1
        loaded = nil
        loadError = nil
        loading = false
        guard let photo = selected else { save(); return }
        if folderMode { expandedFolderPath = URL(fileURLWithPath: photo.path).deletingLastPathComponent().path }
        loading = true
        task = Task { [weak self] in
            do {
                try Task.checkCancellation()
                let result = try await ImageLoader.shared.load(photo)
                try Task.checkCancellation()
                guard let self, self.selectedID == photo.id else { return }
                self.loaded = result
                self.loading = false
            } catch is CancellationError {} catch {
                guard let self, !Task.isCancelled, self.selectedID == photo.id else { return }
                self.loadError = error.localizedDescription
                self.loading = false
            }
        }
        save()
    }

    func step(_ delta: Int) {
        let candidates = browsingPhotos
        guard !candidates.isEmpty else { return }
        let next = min(max(browsingIndex + delta, 0), candidates.count - 1)
        if candidates[next].id != selectedID { select(candidates[next].id) }
    }

    func removeSelected() {
        guard let id = selectedID else { return }
        folderRevision += 1
        if let selected { excludedPaths.insert(selected.resolve().resolvingSymlinksInPath().path) }
        let index = selectedIndex
        photos.removeAll { $0.id == id }
        select(photos.isEmpty ? nil : photos[min(index, photos.count - 1)].id)
        save()
    }

    func relink() {
        if let activeOpenPanel { activeOpenPanel.makeKeyAndOrderFront(nil); return }
        guard let photo = selected else { return }
        let panel = NSOpenPanel()
        activeOpenPanel = panel
        panel.title = "重新定位 \(photo.filename)"
        panel.prompt = "关联此文件"
        panel.allowedContentTypes = [.image, .rawImage] + PhotoReader.rawExtensions.compactMap { UTType(filenameExtension: $0) }
        panel.begin { [weak self] response in
            Task { @MainActor in
                self?.activeOpenPanel = nil
                guard response == .OK, let url = panel.url else { return }
                guard let self, let index = self.photos.firstIndex(where: { $0.id == photo.id }) else { return }
                var replacement = PhotoReference(url: url)
                replacement.id = photo.id
                self.photos[index] = replacement
                self.select(photo.id)
                self.save()
            }
        }
    }

    func reveal() {
        guard let url = selected?.resolve() else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func save() {
        do {
            try FileManager.default.createDirectory(at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(Archive(photos: photos, selectedID: selectedID,
                folderRoots: folderRoots, folderPaths: folderPaths, folderMode: folderMode,
                expandedFolderPath: expandedFolderPath, excludedPaths: Array(excludedPaths)))
            try data.write(to: storageURL, options: .atomic)
        } catch { notice = "照片列表未能保存：\(error.localizedDescription)" }
    }
}
