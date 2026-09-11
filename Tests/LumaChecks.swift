import AppKit
import ImageIO
import UniformTypeIdentifiers

struct CheckFailure: Error, CustomStringConvertible { let description: String }
func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw CheckFailure(description: message) }
}

/// Standalone integration checks: requires only Apple's Command Line Tools, not XCTest / Xcode.
@main
@MainActor
struct LumaChecks {
    static func fixture(in directory: URL, type: UTType = .jpeg, name: String = "frame") throws -> URL {
        let url = directory.appendingPathComponent(name).appendingPathExtension(type.preferredFilenameExtension ?? "jpg")
        let context = CGContext(data: nil, width: 120, height: 80, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(CGColor(red: 0.3, green: 0.45, blue: 0.55, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 120, height: 80))
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else {
            throw CheckFailure(description: "Cannot create \(type.identifier) fixture")
        }
        let properties: [CFString: Any] = [
            kCGImagePropertyOrientation: 6,
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "Test", kCGImagePropertyTIFFModel: "Camera"],
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifFocalLength: 50, kCGImagePropertyExifFNumber: 1.8,
                kCGImagePropertyExifExposureTime: 0.004, kCGImagePropertyExifISOSpeedRatings: [400],
                kCGImagePropertyExifLensModel: "50 mm Prime", kCGImagePropertyExifDateTimeOriginal: "2026:09:10 10:30:00"]
        ]
        CGImageDestinationAddImage(destination, context.makeImage()!, properties as CFDictionary)
        try check(CGImageDestinationFinalize(destination), "Fixture write failed")
        return url
    }

    static func main() async throws {
        setbuf(stdout, nil)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("LumaChecks-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        for type in [UTType.jpeg, .png, .tiff, .heic] {
            let url = try fixture(in: directory, type: type)
            let result = try PhotoReader.load(PhotoReference(url: url), maxPixel: 40)
            try check(max(result.image.size.width, result.image.size.height) <= 40, "Pixel budget exceeded: \(type)")
            try check(!result.isRAW, "Common format incorrectly classified as RAW")
        }
        print("PASS: JPEG, PNG, TIFF, HEIC decode with bounded image size")

        let jpeg = try fixture(in: directory)
        let result = try PhotoReader.load(PhotoReference(url: jpeg))
        try check(result.metadata.camera == "Test Camera", "Camera EXIF mismatch")
        try check(result.metadata.lens == "50 mm Prime", "Lens EXIF mismatch")
        try check(result.metadata.exposure == ["50 mm", "ƒ/1.8", "1/250 s", "ISO 400"], "Exposure EXIF mismatch")
        try check(result.metadata.date == "2026.09.10", "Capture date mismatch")
        try check(result.metadata.dimensions == "80 × 120", "Oriented dimensions mismatch")
        try check(result.image.size.width < result.image.size.height, "EXIF orientation not applied to rendered image")
        print("PASS: Camera, lens, exposure, date and EXIF orientation from a real JPEG")

        let empty = PhotoMetadata.read([:])
        try check(empty.camera == nil && empty.lens == nil && empty.exposure.isEmpty && !empty.hasCaptureData, "Invented absent EXIF")
        print("PASS: Missing EXIF remains absent")
        let nikon = PhotoMetadata.read([kCGImagePropertyTIFFDictionary as String: [kCGImagePropertyTIFFMake as String: "NIKON CORPORATION", kCGImagePropertyTIFFModel as String: "NIKON D3S"]])
        try check(nikon.camera == "NIKON D3S", "Camera display duplicates manufacturer")

        let second = try fixture(in: directory, name: "second")
        let before = try Data(contentsOf: jpeg)
        let storage = directory.appendingPathComponent("state/library.json")
        let library = Library(storageURL: storage, restore: false)
        library.add([jpeg, second, jpeg])
        try check(library.photos.count == 2, "Import did not deduplicate")
        library.step(1)
        let restored = Library(storageURL: storage)
        try check(restored.photos.count == 2 && restored.selectedID == library.selectedID, "Library restoration mismatch")
        try check(restored.photos[0].resolve().resolvingSymlinksInPath().path == jpeg.resolvingSymlinksInPath().path, "Reference no longer resolves to original")
        restored.removeSelected()
        restored.removeSelected()
        library.select(nil)
        try check(restored.photos.isEmpty, "Remove did not update list")
        try check(FileManager.default.fileExists(atPath: second.path), "Remove deleted original")
        let after = try Data(contentsOf: jpeg)
        try check(before == after, "Import altered original bytes")
        let savedFiles = try FileManager.default.contentsOfDirectory(atPath: storage.deletingLastPathComponent().path)
        try check(savedFiles == ["library.json"], "Unexpected copied file in library directory")
        print("PASS: Batch import, deduplication, bookmark restoration and remove preserve original files")

        let folder = directory.appendingPathComponent("folder/subfolder")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let nested = try fixture(in: folder, name: "nested")
        try Data("ignore me".utf8).write(to: folder.appendingPathComponent("notes.txt"))
        let folderLibrary = Library(storageURL: directory.appendingPathComponent("folder-library.json"), restore: false)
        folderLibrary.add([folder.deletingLastPathComponent()])
        try check(folderLibrary.photos.count == 1, "Folder import did not recurse or included non-photo files")
        try check(folderLibrary.photos[0].resolve().resolvingSymlinksInPath().path == nested.resolvingSymlinksInPath().path, "Folder import copied or changed the source path")
        folderLibrary.select(nil)
        print("PASS: Recursive folder import keeps original references and filters non-photos")

        try check(folderLibrary.folderMode && folderLibrary.folderRoots.count == 1, "Directory connection was not retained")
        try check(folderLibrary.folders.count == 2, "Folder hierarchy lost its empty parent")
        let rootPath = folder.deletingLastPathComponent().path
        let newPhoto = try fixture(in: folder.deletingLastPathComponent(), name: "new-on-disk")
        await folderLibrary.refreshFolders()
        try check(folderLibrary.photos.count == 2, "Folder refresh did not discover new disk photo")
        let parentGroup = folderLibrary.folders.first { FolderReference.contains(rootPath, in: $0.path) && FolderReference.contains($0.path, in: rootPath) }!
        try check(parentGroup.photos.count == 1, "Folder must contain only its immediate photos")
        folderLibrary.toggleFolder(parentGroup)
        try check(folderLibrary.browsingPhotos.count == 1 && !folderLibrary.canStepForward, "Navigation escaped the open folder")
        let parentSelection = folderLibrary.selectedID
        folderLibrary.step(1)
        try check(folderLibrary.selectedID == parentSelection, "Arrow navigation crossed folder boundary")
        folderLibrary.toggleFolder(parentGroup)
        try check(folderLibrary.expandedFolderPath == nil && folderLibrary.browsingPhotos.isEmpty, "Folder did not collapse")
        await folderLibrary.refreshFolders(reportErrors: true)
        try check(folderLibrary.expandedFolderPath == nil, "Refresh unexpectedly reopened a collapsed folder")
        folderLibrary.toggleFolder(parentGroup)
        let refreshed = Library(storageURL: directory.appendingPathComponent("folder-library.json"))
        try check(refreshed.folderMode && refreshed.folderRoots.count == 1, "Folder mode or bookmarks did not persist")
        try check(refreshed.expandedFolderPath == folderLibrary.expandedFolderPath, "Expanded folder did not restore")
        try FileManager.default.removeItem(at: newPhoto)
        await folderLibrary.refreshFolders()
        try check(folderLibrary.photos.count == 1, "Removed disk photo remained in connected folder")
        try check(folderLibrary.expandedFolder?.photos.isEmpty == true && folderLibrary.selected == nil,
                  "Refreshing an empty open folder jumped to an unrelated folder")
        let parked = directory.appendingPathComponent("parked-folder")
        try FileManager.default.moveItem(at: folder.deletingLastPathComponent(), to: parked)
        // A bookmark may follow the moved directory. Either way, refresh must preserve access or the prior list.
        await folderLibrary.refreshFolders()
        try check(folderLibrary.photos.count == 1, "Temporarily unavailable or moved folder erased its photo list")
        try check(FileManager.default.fileExists(atPath: parked.appendingPathComponent("subfolder/nested.jpg").path)
                  || FileManager.default.fileExists(atPath: parked.appendingPathComponent("subfolder/nested.jpeg").path), "Folder refresh altered original")
        folderLibrary.select(nil)
        refreshed.select(nil)
        print("PASS: Folder hierarchy, expand/collapse, bounded navigation, disk refresh and folder restoration")

        let legacyURL = directory.appendingPathComponent("legacy.json")
        let legacyData = try JSONEncoder().encode(Library.Archive(photos: [PhotoReference(url: jpeg)], selectedID: nil))
        try legacyData.write(to: legacyURL)
        let legacy = Library(storageURL: legacyURL)
        try check(legacy.photos.count == 1 && legacy.folderRoots.isEmpty && !legacy.folderMode, "Legacy library migration lost photos or silently connected unrelated folders")
        legacy.select(nil)
        print("PASS: Existing photo-only libraries restore without losing references")

        var missingFailed = false
        do { _ = try PhotoReader.load(PhotoReference(url: directory.appendingPathComponent("missing.nef"))) }
        catch PhotoReadError.missing { missingFailed = true }
        try check(missingFailed, "Missing file error not surfaced")
        let corrupt = directory.appendingPathComponent("corrupt.jpg")
        try Data("not an image".utf8).write(to: corrupt)
        var corruptFailed = false
        do { _ = try PhotoReader.load(PhotoReference(url: corrupt)) }
        catch PhotoReadError.unsupported { corruptFailed = true }
        try check(corruptFailed, "Corrupt file error not surfaced")
        print("PASS: Missing and corrupt files report recoverable errors")

        if let path = ProcessInfo.processInfo.environment["LUMA_RAW_FIXTURE"] {
            let raw = try PhotoReader.load(PhotoReference(url: URL(fileURLWithPath: path)), maxPixel: 1200)
            try check(raw.isRAW && !raw.usesEmbeddedPreview, "Fixture did not exercise actual RAW development")
            try check(raw.metadata.camera != nil && raw.image.size.width > 100, "RAW decode incomplete")
            try check(max(raw.image.size.width, raw.image.size.height) <= 1202, "RAW decode exceeds pixel budget")
            print("PASS: Actual RAW development — \(raw.metadata.camera ?? "") · \(raw.metadata.exposure.joined(separator: " · "))")
        } else { print("SKIP: Set LUMA_RAW_FIXTURE to exercise a real camera RAW file") }
        print("All checks passed.")
    }
}
