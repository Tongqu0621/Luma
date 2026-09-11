import Foundation

struct FolderReference: Identifiable, Codable, Equatable {
    private var location: PhotoReference
    var id: UUID { location.id }
    var path: String { location.path }
    init(url: URL) { location = PhotoReference(url: url) }
    func resolve() -> URL { location.resolve() }

    static func contains(_ path: String, in root: String) -> Bool {
        let child = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
        let parent = URL(fileURLWithPath: root).resolvingSymlinksInPath().standardizedFileURL.path
        return child == parent || child.hasPrefix(parent == "/" ? "/" : parent + "/")
    }
}

struct PhotoFolder: Identifiable {
    let path: String
    let title: String
    let photos: [PhotoReference]
    var id: String { path }
    var name: String { URL(fileURLWithPath: path).lastPathComponent }
}

struct FolderScan {
    let original: FolderReference
    let current: FolderReference
    let directories: [String]
    let photos: [PhotoReference]
    let complete: Bool
}

enum FolderReader {
    /// Enumerates references only. No image bytes are copied or decoded during a scan.
    static func scan(_ root: FolderReference) -> FolderScan {
        let url = root.resolve()
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        var complete = true
        guard FileManager.default.isReadableFile(atPath: url.path),
              (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
              let enumerator = FileManager.default.enumerator(at: url,
                includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { _, _ in complete = false; return true }) else {
            return FolderScan(original: root, current: root, directories: [], photos: [], complete: false)
        }
        var directories = [url.standardizedFileURL.path]
        var photos: [PhotoReference] = []
        for case let child as URL in enumerator {
            guard let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]) else {
                complete = false; continue
            }
            if values.isSymbolicLink == true { continue }
            if values.isDirectory == true { directories.append(child.standardizedFileURL.path) }
            else if values.isRegularFile == true && PhotoReader.supports(child) { photos.append(PhotoReference(url: child)) }
        }
        photos.sort { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        return FolderScan(original: root, current: FolderReference(url: url), directories: directories, photos: photos, complete: complete)
    }
}
