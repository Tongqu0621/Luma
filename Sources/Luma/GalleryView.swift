import SwiftUI
import AppKit

private enum Palette {
    static let background = Color(red: 0.062, green: 0.066, blue: 0.064)
    static let panel = Color(red: 0.083, green: 0.087, blue: 0.083)
    static let ink = Color(red: 0.91, green: 0.89, blue: 0.83)
    static let muted = Color(red: 0.53, green: 0.55, blue: 0.51)
    static let accent = Color(red: 0.77, green: 0.69, blue: 0.51)
    static let line = Color.white.opacity(0.09)
}

struct GalleryView: View {
    @ObservedObject var library: Library
    @State private var targeted = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Palette.line).frame(height: 1)
            ZStack {
                if library.folderMode && library.expandedFolder?.photos.isEmpty == true && library.selected == nil {
                    VStack(spacing: 15) {
                        Image(systemName: "folder").font(.system(size: 38, weight: .ultraLight)).foregroundStyle(Palette.accent)
                        Text(library.expandedFolder?.name ?? "文件夹").font(.system(size: 20, weight: .light))
                        Text("这个文件夹里还没有照片").font(.system(size: 12)).foregroundStyle(Palette.muted)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if library.photos.isEmpty { emptyState }
                else { stage }
                if targeted {
                    RoundedRectangle(cornerRadius: 12).fill(Palette.accent.opacity(0.08))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.accent, style: StrokeStyle(lineWidth: 1, dash: [7])))
                        .padding(16).allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if (!library.photos.isEmpty || !library.folderRoots.isEmpty) && library.showFilmstrip { filmstrip }
            footer
        }
        .foregroundStyle(Palette.ink)
        .background(Palette.background)
        .tint(Palette.accent)
        .task { await library.refreshFolders() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await library.refreshFolders() }
        }
        .dropDestination(for: URL.self) { urls, _ in library.add(urls); return true } isTargeted: { targeted = $0 }
        .alert("光隙", isPresented: Binding(get: { library.notice != nil }, set: { if !$0 { library.notice = nil } })) {
            Button("知道了", role: .cancel) { library.notice = nil }
        } message: { Text(library.notice ?? "") }
    }

    private var header: some View {
        HStack(spacing: 20) {
            HStack(spacing: 10) {
                Image(systemName: "viewfinder").font(.system(size: 19, weight: .ultraLight)).foregroundStyle(Palette.accent)
                Text("LUMA").font(.system(size: 17, weight: .medium, design: .serif)).tracking(5)
                Rectangle().fill(Palette.line).frame(width: 1, height: 16)
                Text("光隙").font(.system(size: 12, weight: .light)).tracking(3).foregroundStyle(Palette.muted)
            }
            Spacer()
            if !library.photos.isEmpty {
                HStack(spacing: 2) {
                    styleButton("展签", minimal: false)
                    styleButton("极简", minimal: true)
                }.padding(3).background(.white.opacity(0.035), in: Capsule())
                Rectangle().fill(Palette.line).frame(width: 1, height: 18)
                iconButton("info", label: "显示或隐藏拍摄参数 · I", active: library.showInfo) { library.showInfo.toggle() }
                iconButton("rectangle.split.3x1", label: "显示或隐藏缩略图 · T", active: library.showFilmstrip) { library.showFilmstrip.toggle() }
                iconButton("arrow.up.left.and.arrow.down.right", label: "全屏") { NSApp.keyWindow?.toggleFullScreen(nil) }
            }
            Button { library.importPanel() } label: {
                HStack(spacing: 8) { Image(systemName: "plus"); Text("导入照片") }
                    .font(.system(size: 12, weight: .medium)).padding(.horizontal, 15).padding(.vertical, 9)
                    .background(Palette.ink.opacity(0.07), in: Capsule())
                    .overlay(Capsule().strokeBorder(Palette.ink.opacity(0.13)))
            }.buttonStyle(.plain).help("导入照片 · ⌘O")
        }
        .padding(.leading, 28).padding(.trailing, 25).padding(.top, 28).padding(.bottom, 18)
    }

    private func styleButton(_ title: String, minimal: Bool) -> some View {
        Button { library.minimal = minimal; library.showInfo = true } label: {
            Text(title).font(.system(size: 11)).padding(.horizontal, 14).padding(.vertical, 6)
                .foregroundStyle(library.minimal == minimal ? Palette.ink : Palette.muted)
                .background(library.minimal == minimal ? .white.opacity(0.08) : .clear, in: Capsule())
        }.buttonStyle(.plain)
    }

    private func iconButton(_ symbol: String, label: String, active: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 14, weight: .light))
                .frame(width: 27, height: 28).contentShape(Rectangle())
                .foregroundStyle(active ? Palette.ink : Palette.muted)
        }.buttonStyle(.plain).help(label).accessibilityLabel(label)
    }

    private var emptyState: some View {
        GeometryReader { geometry in
            ZStack {
                RadialGradient(colors: [Palette.accent.opacity(0.06), .clear], center: UnitPoint(x: 0.5, y: 0.35), startRadius: 0, endRadius: 420)
                VStack(spacing: 0) {
                    ZStack {
                        ForEach(0..<4) { index in
                            RoundedRectangle(cornerRadius: 2)
                                .stroke(Palette.accent.opacity(0.22 - Double(index) * 0.035), lineWidth: 0.7)
                                .frame(width: 120, height: 152)
                                .rotationEffect(.degrees(Double(index) * 9 - 13.5))
                        }
                        Image(systemName: "sun.horizon").font(.system(size: 36, weight: .ultraLight)).foregroundStyle(Palette.accent.opacity(0.8))
                    }.frame(height: geometry.size.height < 480 ? 120 : 175).padding(.bottom, 34)
                    Text("A LITTLE SPACE FOR LIGHT").font(.system(size: 9, weight: .medium)).tracking(4).foregroundStyle(Palette.accent).padding(.bottom, 17)
                    Text("留住光，慢慢看。").font(.system(size: 34, weight: .ultraLight, design: .serif)).tracking(5).padding(.bottom, 15)
                    Text("让每一张照片，都有自己的展位。").font(.system(size: 12, weight: .light)).tracking(2).foregroundStyle(Palette.muted)
                    Button { library.importPanel() } label: {
                        HStack(spacing: 12) { Image(systemName: "plus"); Text("选择照片"); Text("⌘ O").foregroundStyle(.black.opacity(0.45)) }
                            .font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.background)
                            .padding(.horizontal, 23).padding(.vertical, 13).background(Palette.ink, in: Capsule())
                    }.buttonStyle(.plain).padding(.top, 30)
                    Text("或将照片、文件夹拖放到这里").font(.system(size: 11)).foregroundStyle(Palette.muted).padding(.top, 14)
                    HStack(spacing: 18) {
                        Text("RAW"); Text("JPEG"); Text("HEIC"); Text("PNG"); Text("TIFF")
                    }.font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(1.5).foregroundStyle(Palette.muted.opacity(0.75)).padding(.top, 30)
                }.padding(.vertical, 20)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var stage: some View {
        ZStack(alignment: .bottomLeading) {
            if let photo = library.loaded {
                PhotoCanvas(image: photo.image, zoom: $library.zoom)
                    .padding(.horizontal, 48).padding(.vertical, 30)
                if library.showInfo {
                    metadata(photo.metadata)
                        .padding(26)
                        .background {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(.black.opacity(library.minimal ? 0.58 : 0.7))
                                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.white.opacity(0.07)))
                        }
                        .padding(.leading, 34).padding(.bottom, 26)
                        .allowsHitTesting(false)
                }
                VStack {
                    HStack {
                        Text(library.selected?.format ?? "")
                            .font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(2)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(.black.opacity(0.55), in: Capsule())
                        if photo.usesEmbeddedPreview {
                            Text("内嵌预览").font(.system(size: 10)).foregroundStyle(Palette.accent)
                                .padding(6).background(.black.opacity(0.55), in: Capsule())
                        }
                        Spacer()
                    }
                    Spacer()
                    HStack {
                        Spacer()
                        HStack(spacing: 10) {
                            iconButton("minus", label: "缩小") { library.zoom = max(1, library.zoom - 0.5) }
                            Button { library.zoom = 1 } label: {
                                Text(library.zoom < 1.01 ? "适应" : String(format: "%.1f×", library.zoom))
                                    .font(.system(size: 10, design: .monospaced)).frame(width: 38)
                            }.buttonStyle(.plain).help("适应窗口 · ⌘0；倍率相对于适应窗口")
                            iconButton("plus", label: "放大") { library.zoom = min(6, library.zoom + 0.5) }
                        }.padding(.horizontal, 10).padding(.vertical, 4).background(.black.opacity(0.65), in: Capsule())
                    }
                }.padding(28)
            } else if library.loading {
                VStack(spacing: 17) {
                    ProgressView().controlSize(.small)
                    Text("正在读取光影").font(.system(size: 12, weight: .light)).tracking(3)
                    Text(library.selected?.filename ?? "").font(.system(size: 10)).foregroundStyle(Palette.muted)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = library.loadError {
                VStack(spacing: 16) {
                    Image(systemName: "photo.badge.exclamationmark").font(.system(size: 34, weight: .ultraLight)).foregroundStyle(Palette.accent)
                    Text("暂时看不到这张照片").font(.system(size: 20, weight: .light))
                    Text(error).font(.system(size: 12)).foregroundStyle(Palette.muted).multilineTextAlignment(.center).frame(maxWidth: 410)
                    Text(library.selected?.filename ?? "").font(.system(size: 11, design: .monospaced))
                    HStack(spacing: 18) {
                        Button("重新定位…", action: library.relink)
                        Button("重试") { library.select(library.selectedID) }
                    }.buttonStyle(.bordered).padding(.top, 8)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .contextMenu {
            Button("在 Finder 中显示", action: library.reveal)
            Button("重新定位原文件…", action: library.relink)
            Divider()
            Button("从列表移除", action: library.removeSelected)
        }
    }

    private func metadata(_ metadata: PhotoMetadata) -> some View {
        VStack(alignment: .leading, spacing: library.minimal ? 10 : 16) {
            if !library.minimal {
                HStack(spacing: 10) {
                    Rectangle().fill(Palette.accent).frame(width: 22, height: 1)
                    Text(String(format: "NO. %03d", library.browsingIndex + 1))
                        .font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(2)
                    if let date = metadata.date {
                        Text("/  " + date).font(.system(size: 9, design: .monospaced)).tracking(1)
                    }
                }.foregroundStyle(Palette.accent)
            }
            Text(metadata.camera ?? library.selected?.filename ?? "未命名")
                .font(.system(size: library.minimal ? 17 : 26, weight: .regular, design: .serif))
                .lineLimit(1).truncationMode(.middle)
            if !library.minimal, let lens = metadata.lens {
                Text(lens).font(.system(size: 11, weight: .light)).foregroundStyle(Palette.ink.opacity(0.65)).lineLimit(2)
            }
            if !metadata.exposure.isEmpty {
                HStack(spacing: 13) {
                    ForEach(Array(metadata.exposure.enumerated()), id: \.offset) { index, value in
                        if index > 0 { Rectangle().fill(Palette.ink.opacity(0.22)).frame(width: 1, height: 9) }
                        Text(value).font(.system(size: 11, design: .monospaced)).fixedSize()
                    }
                }
            } else {
                Text("此照片没有拍摄参数").font(.system(size: 11)).foregroundStyle(Palette.muted)
            }
        }.frame(maxWidth: 475, alignment: .leading).fixedSize(horizontal: true, vertical: true)
    }

    private var filmstrip: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Palette.line).frame(height: 1)
            HStack(spacing: 16) {
                HStack(spacing: 2) {
                    browseModeButton("照片", symbol: "photo", folders: false)
                    browseModeButton("文件夹", symbol: "folder", folders: true)
                }.padding(3).background(.white.opacity(0.035), in: Capsule())
                Rectangle().fill(Palette.line).frame(width: 1, height: 22)
                if library.folderMode {
                    ScrollViewReader { proxy in
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 9) {
                                ForEach(library.folders) { folder in folderButton(folder).id(folder.id) }
                            }.padding(.vertical, 4)
                        }
                        .onChange(of: library.expandedFolderPath) { _, path in
                            withAnimation(.easeOut(duration: 0.18)) { proxy.scrollTo(path, anchor: .center) }
                        }
                        .onAppear { proxy.scrollTo(library.expandedFolderPath, anchor: .center) }
                    }
                } else {
                    Text("全部照片 · \(library.photos.count) 张").font(.system(size: 10)).foregroundStyle(Palette.muted)
                    Spacer()
                }
                if library.refreshingFolders { ProgressView().controlSize(.mini).frame(width: 27) }
                else if library.folderMode {
                    iconButton("arrow.clockwise", label: "重新读取文件夹", active: !library.folderRoots.isEmpty) {
                        Task { await library.refreshFolders(reportErrors: true) }
                    }.disabled(library.folderRoots.isEmpty)
                }
                Button { library.importPanel(foldersOnly: true) } label: {
                    Label("打开文件夹", systemImage: "folder.badge.plus").font(.system(size: 11))
                        .foregroundStyle(Palette.accent)
                }.buttonStyle(.plain).help("直接读取文件夹及子文件夹 · ⌘⇧O")
            }.padding(.horizontal, 28).frame(height: 54)

            if !library.folderMode || library.expandedFolder != nil {
                Rectangle().fill(Palette.line).frame(height: 1).padding(.horizontal, 28)
                photoStrip
            } else if library.folders.isEmpty {
                Text("打开一个文件夹，让照片各归其位。")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted).padding(.bottom, 18)
            }
        }.background(Palette.panel)
    }

    private func browseModeButton(_ title: String, symbol: String, folders: Bool) -> some View {
        Button { library.setFolderMode(folders) } label: {
            Label(title, systemImage: symbol).font(.system(size: 10)).padding(.horizontal, 11).padding(.vertical, 6)
                .foregroundStyle(library.folderMode == folders ? Palette.ink : Palette.muted)
                .background(library.folderMode == folders ? .white.opacity(0.08) : .clear, in: Capsule())
        }.buttonStyle(.plain).accessibilityLabel(folders ? "文件夹模式" : "全部照片模式")
    }

    private func folderButton(_ folder: PhotoFolder) -> some View {
        let expanded = library.expandedFolderPath == folder.path
        return Button { library.toggleFolder(folder) } label: {
            HStack(spacing: 9) {
                Image(systemName: expanded ? "folder.fill" : "folder").foregroundStyle(Palette.accent)
                Text(folder.title).lineLimit(1).truncationMode(.middle)
                Text("\(folder.photos.count)").font(.system(size: 9, design: .monospaced)).foregroundStyle(Palette.muted)
                Image(systemName: expanded ? "chevron.down" : "chevron.right").font(.system(size: 8))
            }
            .font(.system(size: 11)).foregroundStyle(expanded ? Palette.ink : Palette.muted)
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(expanded ? Palette.accent.opacity(0.08) : .white.opacity(0.025), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(expanded ? Palette.accent.opacity(0.4) : Palette.line))
        }.buttonStyle(.plain).help(folder.path)
            .accessibilityLabel("\(folder.title)，\(folder.photos.count) 张，\(expanded ? "已展开" : "已收起")")
    }

    private var photoStrip: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 7) {
                Text(library.folderMode ? (library.expandedFolder?.name ?? "") : "COLLECTION")
                    .font(.system(size: 9, weight: .medium)).lineLimit(1).truncationMode(.middle)
                Text(String(format: "%02d", library.browsingPhotos.count))
                    .font(.system(size: 23, weight: .light, design: .serif))
            }.foregroundStyle(Palette.muted).frame(width: 88, alignment: .leading).padding(.leading, 30)
            if library.browsingPhotos.isEmpty {
                Text("这个文件夹里还没有照片").font(.system(size: 11)).foregroundStyle(Palette.muted)
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 10) {
                            ForEach(library.browsingPhotos) { photo in
                                ThumbnailView(photo: photo, selected: photo.id == library.selectedID) { library.select(photo.id) }
                                    .id(photo.id)
                            }
                        }.padding(.vertical, 10).padding(.horizontal, 4)
                    }
                    .onChange(of: library.selectedID) { _, id in
                        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(id, anchor: .center) }
                    }
                    .onAppear { proxy.scrollTo(library.selectedID, anchor: .center) }
                }
            }
        }.padding(.trailing, 28).frame(height: 102)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Image(systemName: "link").font(.system(size: 10)).foregroundStyle(Palette.accent)
            Text("原片留在原处").font(.system(size: 10)).foregroundStyle(Palette.muted)
            if let selected = library.selected {
                Text("·").foregroundStyle(Palette.muted)
                Text(selected.filename).font(.system(size: 10)).foregroundStyle(Palette.muted).lineLimit(1).truncationMode(.middle)
                if let dimensions = library.loaded?.metadata.dimensions {
                    Text(dimensions).font(.system(size: 9, design: .monospaced)).foregroundStyle(Palette.muted.opacity(0.7)).padding(.leading, 6)
                }
            }
            Spacer(minLength: 10)
            if !library.photos.isEmpty {
                iconButton("chevron.left", label: "上一张 · ←") { library.step(-1) }.disabled(!library.canStepBack)
                Text(library.browsingPhotos.isEmpty ? "— / —" : "\(library.browsingIndex + 1) / \(library.browsingPhotos.count)")
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.muted)
                iconButton("chevron.right", label: "下一张 · →") { library.step(1) }.disabled(!library.canStepForward)
            } else {
                Text("为摄影而留白").font(.system(size: 9, weight: .light)).tracking(2).foregroundStyle(Palette.muted)
            }
        }.padding(.horizontal, 28).frame(height: 40).background(Palette.panel)
    }
}

private struct ThumbnailView: View {
    let photo: PhotoReference
    let selected: Bool
    let action: () -> Void
    @State private var image: NSImage?

    private var thumbnailSize: CGSize {
        guard let image, image.size.height > 0 else { return CGSize(width: 48, height: 72) }
        let ratio = image.size.width / image.size.height
        let height = min(72, 180 / max(ratio, 0.01))
        return CGSize(width: height * ratio, height: height)
    }

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomTrailing) {
                Rectangle().fill(.white.opacity(0.035))
                if let image {
                    Image(nsImage: image).resizable().scaledToFit()
                        .frame(width: thumbnailSize.width, height: thumbnailSize.height)
                }
                else { Image(systemName: "photo").frame(maxWidth: .infinity, maxHeight: .infinity).foregroundStyle(Palette.muted) }
                Text(photo.format).font(.system(size: 7, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.85)).padding(3).background(.black.opacity(0.6)).padding(3)
            }
            .frame(width: thumbnailSize.width, height: thumbnailSize.height).clipShape(RoundedRectangle(cornerRadius: 3))
            .padding(4)
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(selected ? Palette.accent : .clear, lineWidth: 1))
            .opacity(selected ? 1 : 0.6)
        }.buttonStyle(.plain).help(photo.filename).accessibilityLabel(photo.filename)
            .task(id: photo.path) { image = await ImageLoader.shared.thumbnail(photo) }
    }
}

/// AppKit gives the canvas native trackpad magnification and scrolling while zoomed.
struct PhotoCanvas: NSViewRepresentable {
    let image: NSImage
    @Binding var zoom: CGFloat

    func makeNSView(context: Context) -> CanvasScrollView {
        let view = CanvasScrollView()
        view.allowsMagnification = true
        view.minMagnification = 1
        view.maxMagnification = 6
        view.drawsBackground = false
        view.hasVerticalScroller = false
        view.hasHorizontalScroller = false
        view.automaticallyAdjustsContentInsets = false
        view.imageView.imageScaling = .scaleProportionallyUpOrDown
        view.imageView.imageAlignment = .alignCenter
        view.documentView = view.imageView
        view.onZoom = { value in DispatchQueue.main.async { self.zoom = value } }
        return view
    }
    func updateNSView(_ view: CanvasScrollView, context: Context) {
        if view.imageView.image !== image {
            view.imageView.image = image
            view.magnification = 1
        }
        if abs(view.magnification - zoom) > 0.01 {
            view.setMagnification(zoom, centeredAt: NSPoint(x: view.imageView.bounds.midX, y: view.imageView.bounds.midY))
        }
        view.needsLayout = true
    }

    final class CanvasScrollView: NSScrollView {
        let imageView = NSImageView()
        var onZoom: ((CGFloat) -> Void)?
        private var priorSize = NSSize.zero
        override func layout() {
            super.layout()
            if bounds.size != priorSize {
                priorSize = bounds.size
                imageView.frame = NSRect(origin: .zero, size: bounds.size)
            }
        }
        override func magnify(with event: NSEvent) {
            super.magnify(with: event)
            onZoom?(magnification)
        }
        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2 {
                setMagnification(magnification > 1.01 ? 1 : 2, centeredAt: imageView.convert(event.locationInWindow, from: nil))
                onZoom?(magnification)
            } else { super.mouseDown(with: event) }
        }
    }
}
