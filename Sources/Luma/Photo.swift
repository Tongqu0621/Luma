import AppKit
import ImageIO
import CoreImage
import UniformTypeIdentifiers

struct PhotoReference: Identifiable, Codable, Equatable {
    var id = UUID()
    var path: String
    var bookmark: Data?

    init(url: URL) {
        path = url.standardizedFileURL.path
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        bookmark = (try? url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess]))
            ?? (try? url.bookmarkData(options: []))
    }

    var filename: String { URL(fileURLWithPath: path).lastPathComponent }
    var format: String { URL(fileURLWithPath: path).pathExtension.uppercased() }

    func resolve() -> URL {
        guard let bookmark else { return URL(fileURLWithPath: path) }
        var stale = false
        return (try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI, .withoutMounting], bookmarkDataIsStale: &stale))
            ?? (try? URL(resolvingBookmarkData: bookmark, options: [.withoutUI, .withoutMounting], bookmarkDataIsStale: &stale))
            ?? URL(fileURLWithPath: path)
    }
}

struct PhotoMetadata {
    var camera: String?
    var lens: String?
    var focalLength: String?
    var aperture: String?
    var shutter: String?
    var iso: String?
    var date: String?
    var dimensions: String?

    var exposure: [String] { [focalLength, aperture, shutter, iso.map { "ISO \($0)" }].compactMap { $0 } }
    var hasCaptureData: Bool { camera != nil || lens != nil || !exposure.isEmpty }

    static func read(_ properties: [String: Any]) -> PhotoMetadata {
        let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any] ?? [:]
        let tiff = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any] ?? [:]
        func string(_ value: Any?) -> String? {
            guard let value = value as? String else { return nil }
            let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return clean.isEmpty ? nil : clean
        }
        func number(_ key: CFString) -> Double? { (exif[key as String] as? NSNumber)?.doubleValue }
        func decimal(_ value: Double) -> String { value.rounded() == value ? String(format: "%.0f", value) : String(format: "%.1f", value) }
        let model = string(tiff[kCGImagePropertyTIFFModel as String])
        let make = string(tiff[kCGImagePropertyTIFFMake as String])?.replacingOccurrences(
            of: #"(?i)\s+(corporation|corp\.?|co\.,?\s*ltd\.?|inc\.?)$"#, with: "", options: .regularExpression)
        let camera: String?
        if let model, let make, !model.lowercased().contains(make.lowercased()) { camera = "\(make) \(model)" }
        else { camera = model ?? make }
        let exposure = number(kCGImagePropertyExifExposureTime)
        let shutter: String? = exposure.flatMap { t in
            guard t > 0 else { return nil }
            if t < 1 { return "1/\(Int((1 / t).rounded())) s" }
            return "\(decimal(t)) s"
        }
        let rawDate = string(exif[kCGImagePropertyExifDateTimeOriginal as String])
        let date = rawDate.map { String($0.prefix(10)).replacingOccurrences(of: ":", with: ".") }
        var dimensions: String?
        if let w = properties[kCGImagePropertyPixelWidth as String] as? NSNumber,
           let h = properties[kCGImagePropertyPixelHeight as String] as? NSNumber {
            let rotated = [5, 6, 7, 8].contains((properties[kCGImagePropertyOrientation as String] as? NSNumber)?.intValue ?? 1)
            dimensions = rotated ? "\(h) × \(w)" : "\(w) × \(h)"
        }
        return PhotoMetadata(camera: camera,
                             lens: string(exif[kCGImagePropertyExifLensModel as String]),
                             focalLength: number(kCGImagePropertyExifFocalLength).map { "\(decimal($0)) mm" },
                             aperture: number(kCGImagePropertyExifFNumber).map { "ƒ/\(decimal($0))" },
                             shutter: shutter,
                             iso: (exif[kCGImagePropertyExifISOSpeedRatings as String] as? [NSNumber])?.first?.stringValue,
                             date: date, dimensions: dimensions)
    }
}

struct LoadedPhoto {
    let image: NSImage
    let metadata: PhotoMetadata
    let isRAW: Bool
    let usesEmbeddedPreview: Bool
}

enum PhotoReadError: LocalizedError {
    case missing, unsupported
    var errorDescription: String? {
        switch self {
        case .missing: return "原文件暂时无法访问。它可能已被移动，或所在的硬盘尚未连接。"
        case .unsupported: return "无法读取这张照片。文件可能已损坏，或当前 macOS 尚不支持这款相机的 RAW。"
        }
    }
}

enum PhotoReader {
    static let rawExtensions: Set<String> = ["raw", "dng", "cr2", "cr3", "crw", "nef", "nrw", "arw", "srf", "sr2", "raf", "orf", "rw2", "rwl", "pef", "ptx", "srw", "3fr", "fff", "iiq", "mos", "mrw", "kdc", "dcr", "erf", "x3f"]
    static func supports(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return rawExtensions.contains(ext) || UTType(filenameExtension: ext)?.conforms(to: .image) == true
    }

    static func load(_ reference: PhotoReference, maxPixel: Int = 4600, thumbnailOnly: Bool = false) throws -> LoadedPhoto {
        let url = reference.resolve()
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard FileManager.default.isReadableFile(atPath: url.path) else { throw PhotoReadError.missing }
        let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)
        let properties = source.flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [String: Any] } ?? [:]
        let metadata = PhotoMetadata.read(properties)
        let raw = rawExtensions.contains(url.pathExtension.lowercased())
            || source.flatMap { CGImageSourceGetType($0) }.flatMap { UTType($0 as String) }?.conforms(to: .rawImage) == true
        var cgImage: CGImage?
        var preview = false
        if raw && !thumbnailOnly, let filter = CIRAWFilter(imageURL: url) {
            let size = filter.nativeSize
            filter.scaleFactor = Float(min(1, CGFloat(maxPixel) / max(size.width, size.height)))
            if let output = filter.outputImage {
                cgImage = context.createCGImage(output, from: output.extent)
            }
        }
        if cgImage == nil, let source {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixel,
                kCGImageSourceShouldCacheImmediately: true
            ]
            cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
            preview = raw
        }
        guard let cgImage else { throw PhotoReadError.unsupported }
        return LoadedPhoto(image: NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height)), metadata: metadata, isRAW: raw, usesEmbeddedPreview: preview)
    }

    private static let context = CIContext(options: [.cacheIntermediates: false])
}

/// Decoding stays off the main thread and runs serially to bound RAW memory usage.
actor ImageLoader {
    static let shared = ImageLoader()
    private let cache = NSCache<NSString, NSImage>()
    init() { cache.totalCostLimit = 32 * 1024 * 1024 }
    func load(_ photo: PhotoReference) throws -> LoadedPhoto {
        try Task.checkCancellation()
        return try PhotoReader.load(photo)
    }
    func thumbnail(_ photo: PhotoReference) -> NSImage? {
        guard !Task.isCancelled else { return nil }
        let key = "\(photo.id)-\(photo.path)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        guard let result = try? PhotoReader.load(photo, maxPixel: 240, thumbnailOnly: true) else { return nil }
        cache.setObject(result.image, forKey: key, cost: Int(result.image.size.width * result.image.size.height * 4))
        return result.image
    }
}
