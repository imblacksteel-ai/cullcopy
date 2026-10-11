import AppKit
import ImageIO
import SwiftUI

/// 「選んでコピー」の1枚
struct PickPhoto: Identifiable, Hashable {
    let url: URL
    let date: Date
    /// どの「写真のフォルダ」から見つかったか（フォルダを外したときに消すため）
    let folder: URL
    var id: URL { url }
}

/// 「選んでコピー」：選んだフォルダの写真を1枚ずつ大きく見て、気に入ったものを指定のフォルダにコピーする
@MainActor
final class PickState: ObservableObject {
    static let shared = PickState()

    @Published var folders: [URL] {
        didSet { UserDefaults.standard.set(folders.map(\.path), forKey: "pickFolders") }
    }
    @Published var destination: URL? {
        didSet { UserDefaults.standard.set(destination?.path, forKey: "pickDestination") }
    }

    @Published var photos: [PickPhoto] = []
    /// 見つけたがまだ撮影日時を読み終わっていない写真の数（読み込み中の表示用）
    @Published var pending = 0
    /// 一覧で選んでいる写真
    @Published var selection: PickPhoto.ID?
    /// プレビューで表示中の番号
    @Published var index = 0
    /// コピー済み（このアプリで今コピーしたもの＋コピー先に同じものがあるもの）
    @Published var copied: Set<URL> = []
    @Published var copying = false
    @Published var flash = 0          // 「コピーしました」の表示のきっかけ
    @Published var flashText = ""
    @Published var errorMessage: String?
    /// プレビューで写真の情報を重ねて表示するか（I キーで切り替え）
    @Published var showInfo = true

    private var loadTasks: [URL: Task<Void, Never>] = [:]

    var loading: Bool { !loadTasks.isEmpty }

    private init() {
        SettingsMigration.run()
        let defaults = UserDefaults.standard
        folders = (defaults.stringArray(forKey: "pickFolders") ?? []).map { URL(fileURLWithPath: $0, isDirectory: true) }
        destination = defaults.string(forKey: "pickDestination").map { URL(fileURLWithPath: $0, isDirectory: true) }
        folders.forEach(load)
    }

    var current: PickPhoto? {
        photos.indices.contains(index) ? photos[index] : nil
    }

    // MARK: フォルダの選択

    func addFolders() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = String(localized: "追加")
        guard panel.runModal() == .OK else { return }
        for url in panel.urls where !folders.contains(url) {
            FolderAccess.shared.remember(url)
            folders.append(url)
            load(url)   // 追加したフォルダだけ読み込む（改修メモ #8）
        }
    }

    func removeFolder(_ url: URL) {
        loadTasks[url]?.cancel()
        loadTasks[url] = nil
        folders.removeAll { $0 == url }
        let currentURL = current?.url
        photos.removeAll { $0.folder == url }   // 外したフォルダの写真だけ消す
        keepCurrent(currentURL)
        objectWillChange.send()
    }

    func chooseDestination() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = destination
        panel.prompt = String(localized: "ここにコピー")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        FolderAccess.shared.remember(url)
        destination = url
        refreshCopied()
    }

    // MARK: 写真の読み込み（読めたものから順に一覧へ足す）

    private func load(_ folder: URL) {
        FolderAccess.shared.access(folder)
        if let destination { FolderAccess.shared.access(destination) }
        let destination = destination
        loadTasks[folder]?.cancel()
        loadTasks[folder] = Task {
            // 1. ファイルを探す（速い）
            let files = await Task.detached {
                Importer.mediaFiles(in: folder).filter { Importer.photoExtensions.contains($0.pathExtension.lowercased()) }
            }.value
            guard !Task.isCancelled else { return }
            pending += files.count
            // 2. 撮影日時を読みながら、少しずつ一覧に足す
            for start in stride(from: 0, to: files.count, by: 60) {
                let chunk = Array(files[start..<min(start + 60, files.count)])
                let (batch, copiedBatch) = await Task.detached { () -> ([PickPhoto], [URL]) in
                    let photos = chunk.map { PickPhoto(url: $0, date: Importer.captureDate(of: $0), folder: folder) }
                    let copied = destination.map { dest in photos.filter { Importer.existingCopy(of: $0.url, in: dest) != nil }.map(\.url) } ?? []
                    return (photos, copied)
                }.value
                if Task.isCancelled {
                    pending -= files.count - start
                    return
                }
                merge(batch)
                copied.formUnion(copiedBatch)
                pending -= chunk.count
            }
            loadTasks[folder] = nil
        }
    }

    private func merge(_ batch: [PickPhoto]) {
        let currentURL = current?.url
        let known = Set(photos.map(\.url))
        photos.append(contentsOf: batch.filter { !known.contains($0.url) })
        photos.sort { ($0.date, $0.url.lastPathComponent) < ($1.date, $1.url.lastPathComponent) }
        keepCurrent(currentURL)
    }

    /// 一覧が変わっても、プレビューで見ている写真を変えない
    private func keepCurrent(_ url: URL?) {
        if let url, let i = photos.firstIndex(where: { $0.url == url }) {
            index = i
        } else {
            index = min(index, max(photos.count - 1, 0))
        }
    }

    /// コピー先にすでに同じものがある写真に印を付ける
    func refreshCopied() {
        guard let destination else {
            copied = []
            return
        }
        FolderAccess.shared.access(destination)
        let photos = photos
        Task {
            let existing = await Task.detached {
                Set(photos.filter { Importer.existingCopy(of: $0.url, in: destination) != nil }.map(\.url))
            }.value
            copied = existing
        }
    }

    // MARK: プレビューの操作

    func open(at photo: PickPhoto?) {
        if let photo, let i = photos.firstIndex(of: photo) {
            index = i
        } else if let selection, let i = photos.firstIndex(where: { $0.id == selection }) {
            index = i
        } else {
            index = 0
        }
    }

    func previous() {
        if index > 0 { index -= 1 }
    }

    func next() {
        if index < photos.count - 1 { index += 1 }
    }

    /// 今の写真をコピーして、次の写真へ進む
    func copyAndNext() {
        guard let photo = current, !copying else { return }
        guard let destination else {
            chooseDestination()
            return
        }
        if FolderAccess.isSandboxed {
            FolderAccess.shared.access(destination)
            if !FileManager.default.isWritableFile(atPath: destination.path) && FileManager.default.fileExists(atPath: destination.path) {
                let message = String(localized: "コピー先「\(destination.lastPathComponent)」に保存する許可が必要です。フォルダを選んで「許可」を押してください。")
                guard let chosen = FolderAccess.shared.requestAccess(to: destination, message: message) else { return }
                self.destination = chosen
            }
        }
        let target = self.destination ?? destination
        copying = true
        Task {
            let result = await Task.detached { () -> Result<Importer.SingleCopyResult, Error> in
                Result { try Importer.copyOne(photo.url, into: target) }
            }.value
            copying = false
            switch result {
            case let .success(.copied(url)):
                copied.insert(photo.url)
                flashText = String(localized: "コピーしました：\(url.lastPathComponent)")
                flash += 1
                NSSound(named: "Tink")?.play()
                next()
            case .success(.alreadyThere):
                copied.insert(photo.url)
                flashText = String(localized: "コピー済みです")
                flash += 1
                next()
            case let .failure(error):
                errorMessage = String(localized: "コピーできませんでした：\(error.localizedDescription)")
            }
        }
    }
}

// MARK: - 大きなプレビュー用の画像と撮影情報

/// RAW・HEIC も含めて、大きめの縮小画像を作る（ImageIO。埋め込みプレビューがあればそれを使うので速い）
@MainActor
final class PreviewImageCache {
    static let shared = PreviewImageCache()
    private let cache = NSCache<NSURL, NSImage>()

    init() { cache.countLimit = 12 }

    func image(for url: URL) async -> NSImage? {
        if let cached = cache.object(forKey: url as NSURL) { return cached }
        let image = await Task.detached { () -> NSImage? in
            guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 2800,
            ]
            guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary) else { return nil }
            return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        }.value
        if let image { cache.setObject(image, forKey: url as NSURL) }
        return image
    }

    /// 前後の写真を先に読んでおく
    func prefetch(_ urls: [URL]) {
        for url in urls where cache.object(forKey: url as NSURL) == nil {
            Task { _ = await image(for: url) }
        }
    }
}

/// 写真の撮影情報（EXIF）。記録されていない項目は nil（改修メモ #9）
struct PhotoInfo {
    var camera: String?
    var lens: String?
    var exposure: String?     // 例: 50mm  f/2.8  1/250s  ISO 400  +0.3EV
    var dimensions: String?   // 例: 6000 × 4000
    var flash: String?

    static func read(_ url: URL) -> PhotoInfo {
        var info = PhotoInfo()
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] else { return info }
        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        let aux = props[kCGImagePropertyExifAuxDictionary] as? [CFString: Any] ?? [:]

        let make = (tiff[kCGImagePropertyTIFFMake] as? String)?.trimmingCharacters(in: .whitespaces)
        let model = (tiff[kCGImagePropertyTIFFModel] as? String)?.trimmingCharacters(in: .whitespaces)
        if let model {
            // 機種名にメーカー名が含まれていれば重ねない（例: "Canon EOS R5"）
            info.camera = (make.map { model.localizedCaseInsensitiveContains($0.components(separatedBy: " ").first ?? $0) } ?? true) ? model : "\(make!) \(model)"
        } else {
            info.camera = make
        }
        info.lens = (exif[kCGImagePropertyExifLensModel] as? String) ?? (aux[kCGImagePropertyExifAuxLensModel] as? String)

        var parts: [String] = []
        if let focal = exif[kCGImagePropertyExifFocalLength] as? Double { parts.append("\(Int(focal.rounded()))mm") }
        if let f = exif[kCGImagePropertyExifFNumber] as? Double { parts.append(String(format: "f/%.1f", f).replacingOccurrences(of: ".0", with: "")) }
        if let t = exif[kCGImagePropertyExifExposureTime] as? Double, t > 0 {
            parts.append(t >= 1 ? String(format: "%.1fs", t).replacingOccurrences(of: ".0", with: "") : "1/\(Int((1 / t).rounded()))s")
        }
        if let iso = (exif[kCGImagePropertyExifISOSpeedRatings] as? [Int])?.first { parts.append("ISO \(iso)") }
        if let bias = exif[kCGImagePropertyExifExposureBiasValue] as? Double, abs(bias) > 0.01 {
            parts.append(String(format: "%+.1fEV", bias))
        }
        info.exposure = parts.isEmpty ? nil : parts.joined(separator: "  ")

        if let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int {
            info.dimensions = "\(w) × \(h)"
        }
        if let flash = exif[kCGImagePropertyExifFlash] as? Int {
            info.flash = flash & 1 == 1 ? String(localized: "フラッシュあり") : String(localized: "フラッシュなし")
        }
        return info
    }
}

// MARK: - タブの画面（フォルダとサムネイル一覧）

struct PickView: View {
    @ObservedObject var state: PickState
    @Environment(\.openWindow) private var openWindow

    private let columns = [GridItem(.adaptive(minimum: 128, maximum: 160), spacing: 12)]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                folderChips
                FolderBox(title: "コピー先", url: state.destination, buttonTitle: "変更…", shortcut: .chooseDestination) {
                    state.chooseDestination()
                }
                BigActionButton(title: "プレビュー開始", systemImage: "rectangle.and.hand.point.up.left.filled", shortcut: .start) {
                    openPreview(at: nil)
                }
                .disabled(state.photos.isEmpty)
            }
            .padding(20)

            Divider()

            grid
        }
    }

    /// 写真のフォルダ（改修メモ #6）：横に並ぶチップ。✕ はチップの中、「フォルダを追加」は最後に大きく
    private var folderChips: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "photo.stack.fill")
                .font(.system(size: 28))
                .foregroundStyle(.blue)
                .frame(width: 40)
            VStack(alignment: .leading, spacing: 8) {
                Text("写真のフォルダ（\(state.folders.count)）").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                FlowLayout(spacing: 8) {
                    ForEach(state.folders, id: \.self) { folder in
                        FolderChip(folder: folder) { state.removeFolder(folder) }
                    }
                    Button {
                        state.addFolders()
                    } label: {
                        ShortcutLabel("フォルダを追加…", systemImage: "plus", shortcut: .chooseFolder, onColor: true)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.chooseFolder)
                }
                Text("サブフォルダの写真も含めて、撮影日ごとに並べます。写真をダブルクリックすると、大きなプレビューが開きます。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.secondary.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.secondary.opacity(0.18)))
    }

    /// 撮影日ごとのまとまり（改修メモ #7）
    private var sections: [(day: Date?, photos: [PickPhoto])] {
        let calendar = Calendar.current
        var result: [(day: Date?, photos: [PickPhoto])] = []
        for photo in state.photos {
            let day: Date? = photo.date == .distantPast ? nil : calendar.startOfDay(for: photo.date)
            if let last = result.last, last.day == day {
                result[result.count - 1].photos.append(photo)
            } else {
                result.append((day, [photo]))
            }
        }
        return result
    }

    @ViewBuilder
    private var grid: some View {
        if state.photos.isEmpty && state.loading {
            ProgressView("写真を探しています…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if state.photos.isEmpty {
            ContentUnavailableView {
                Label(state.folders.isEmpty ? "フォルダを追加してください" : "写真が見つかりません", systemImage: "photo.on.rectangle.angled")
            } description: {
                Text(state.folders.isEmpty ? "「フォルダを追加…」から、写真の入ったフォルダを選んでください（複数選べます）。" : "")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Text("\(state.photos.count) 枚（コピー済み \(state.copied.count) 枚）")
                    if state.pending > 0 {
                        ProgressView().controlSize(.small)
                        Text("読み込み中… あと \(state.pending) 枚")
                    }
                }
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.top, 10)
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12, pinnedViews: [.sectionHeaders]) {
                        ForEach(sections, id: \.photos.first!.url) { section in
                            Section {
                                ForEach(section.photos) { photo in
                                    PickThumbnail(photo: photo, selected: state.selection == photo.id, copied: state.copied.contains(photo.url))
                                        .onTapGesture(count: 2) { openPreview(at: photo) }
                                        .onTapGesture { state.selection = photo.id }
                                }
                            } header: {
                                DayHeader(day: section.day, count: section.photos.count)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
        }
    }

    private func openPreview(at photo: PickPhoto?) {
        state.open(at: photo)
        openWindow(id: "pick-preview")
    }
}

private struct FolderChip: View {
    let folder: URL
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder.fill").foregroundStyle(.blue)
            Text(folder.lastPathComponent).font(.body.weight(.medium)).lineLimit(1)
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("一覧から外す（フォルダは消えません）")
        }
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .padding(.vertical, 7)
        .background(Capsule().fill(Color.secondary.opacity(0.14)))
        .help(folder.path)
    }
}

private struct DayHeader: View {
    let day: Date?
    let count: Int

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "calendar")
            if let day {
                Text(day.formatted(.dateTime.year().month().day().weekday(.abbreviated)))
            } else {
                Text("撮影日なし")
            }
            Text("\(count) 枚").foregroundStyle(.secondary)
            Spacer()
        }
        .font(.headline)
        .padding(.vertical, 8)
        .padding(.top, 6)
        .background(.bar)
    }
}

private struct PickThumbnail: View {
    let photo: PickPhoto
    let selected: Bool
    let copied: Bool

    var body: some View {
        VStack(spacing: 4) {
            FileThumbnail(url: photo.url, size: 128)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 3))
                .overlay(alignment: .topTrailing) {
                    if copied {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.white, .green)
                            .padding(4)
                    }
                }
            Text(photo.url.lastPathComponent)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(width: 140)
        .contentShape(Rectangle())
    }
}

// MARK: - 大きなプレビューのウィンドウ（改修メモ #9〜#14：情報とボタンを写真の上に重ねる）

struct PickPreviewView: View {
    @ObservedObject var state: PickState
    @State private var image: NSImage?
    @State private var info = PhotoInfo()
    @State private var showFlash = false

    var body: some View {
        ZStack {
            Color.black
            if let photo = state.current {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .id(photo.url)
                        .transition(.opacity)
                } else {
                    ProgressView().controlSize(.large).tint(.white)
                }
                overlays(photo)
            } else {
                ContentUnavailableView("写真がありません", systemImage: "photo",
                                       description: Text("「選んでコピー」タブで、写真のフォルダを追加してください。"))
                    .foregroundStyle(.white)
            }
            if showFlash {
                Label(state.flashText, systemImage: "checkmark.circle.fill")
                    .font(.title2.weight(.bold))
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .background(.green, in: Capsule())
                    .foregroundStyle(.white)
                    .shadow(radius: 10)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.15), value: state.current?.url)
        .frame(minWidth: 900, minHeight: 640)
        .task(id: state.current?.url) { await load() }
        .onChange(of: state.flash) {
            withAnimation(.spring(duration: 0.3)) { showFlash = true }
            Task {
                try? await Task.sleep(nanoseconds: 900_000_000)
                withAnimation(.easeOut(duration: 0.3)) { showFlash = false }
            }
        }
        .alert("コピーできませんでした", isPresented: Binding(
            get: { state.errorMessage != nil },
            set: { if !$0 { state.errorMessage = nil } }
        )) {
            Button("OK") { state.errorMessage = nil }
        } message: {
            Text(state.errorMessage ?? "")
        }
    }

    private func load() async {
        guard let photo = state.current else { return }
        image = nil
        async let loadedInfo = Task.detached { PhotoInfo.read(photo.url) }.value
        image = await PreviewImageCache.shared.image(for: photo.url)
        info = await loadedInfo
        let neighbors = [state.index - 1, state.index + 1, state.index + 2]
            .filter { state.photos.indices.contains($0) }
            .map { state.photos[$0].url }
        PreviewImageCache.shared.prefetch(neighbors)
    }

    @ViewBuilder
    private func overlays(_ photo: PickPhoto) -> some View {
        // 左上：写真の情報・撮影情報・コピー先（#9・#14）
        VStack {
            HStack(alignment: .top) {
                if state.showInfo {
                    infoPanel(photo)
                }
                Spacer()
                // 右上：何枚目か（#12）と、情報の表示切り替え
                VStack(alignment: .trailing, spacing: 8) {
                    Text("\(state.index + 1) / \(state.photos.count)")
                        .font(.title2.weight(.heavy).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.45), in: Capsule())
                    Button {
                        state.showInfo.toggle()
                    } label: {
                        ShortcutLabel(state.showInfo ? "情報を隠す" : "情報を表示", systemImage: "info.circle",
                                      shortcut: .toggleInfo, onColor: true)
                            .font(.callout)
                            .foregroundStyle(.white.opacity(0.85))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(.black.opacity(0.35), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.toggleInfo)
                }
            }
            Spacer()
        }
        .padding(16)

        // 左右の矢印（#10）
        HStack {
            ArrowButton(systemImage: "chevron.left", shortcut: .previousItem, enabled: state.index > 0, action: state.previous)
            Spacer()
            ArrowButton(systemImage: "chevron.right", shortcut: .nextItem, enabled: state.index < state.photos.count - 1, action: state.next)
        }
        .padding(.horizontal, 16)

        // 下：コピーして次へ（#11・#13：Return とスペース）
        VStack {
            Spacer()
            Button(action: state.copyAndNext) {
                ShortcutLabel(state.copied.contains(photo.url) ? "コピー済み・次へ" : "コピーして次へ",
                              systemImage: state.copying ? "hourglass" : "square.and.arrow.down.on.square",
                              shortcuts: [.copyAndNext, .copyAndNextSpace], onColor: true)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 40)
                    .padding(.vertical, 18)
                    .background(.black.opacity(0.4), in: Capsule())
                    .overlay(Capsule().strokeBorder(.white.opacity(0.85), lineWidth: 2))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.copyAndNext)
            .disabled(state.copying)
            // スペースキーでも押せるように（見えないボタン）
            Button("", action: state.copyAndNext)
                .keyboardShortcut(.copyAndNextSpace)
                .frame(width: 0, height: 0)
                .opacity(0)
                .disabled(state.copying)
        }
        .padding(.bottom, 24)
    }

    private func infoPanel(_ photo: PickPhoto) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(photo.url.lastPathComponent).font(.headline).foregroundStyle(.white)
                if state.copied.contains(photo.url) {
                    Label("コピー済み", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(.green, in: Capsule())
                        .foregroundStyle(.white)
                }
            }
            Group {
                Text(basicLine(photo))
                Text(photo.url.deletingLastPathComponent().path).lineLimit(1).truncationMode(.middle)
                if let camera = [info.camera, info.lens].compactMap({ $0 }).joined(separator: "  ·  ").nilIfEmpty {
                    Text(camera)
                }
                if let exposure = info.exposure { Text(exposure) }
                if let extra = [info.dimensions, info.flash].compactMap({ $0 }).joined(separator: "  ·  ").nilIfEmpty {
                    Text(extra)
                }
                Text("コピー先：\(state.destination?.path ?? String(localized: "未選択"))")
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.top, 2)
            }
            .font(.callout.monospacedDigit())
            .foregroundStyle(.white.opacity(0.75))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: 520, alignment: .leading)
        .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
    }

    private func basicLine(_ photo: PickPhoto) -> String {
        var parts: [String] = []
        if photo.date != .distantPast { parts.append(photo.date.formatted(date: .numeric, time: .standard)) }
        if let size = (try? photo.url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize {
            parts.append(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
        }
        return parts.joined(separator: "  ·  ")
    }
}

/// 写真の左右に重ねる矢印（#10）
private struct ArrowButton: View {
    let systemImage: String
    let shortcut: KeyboardShortcut
    let enabled: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 34, weight: .semibold))
                    .frame(width: 64, height: 64)
                    .background(.black.opacity(hovering ? 0.55 : 0.35), in: Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.5), lineWidth: 1))
                KeyHint(text: shortcut.symbol, onColor: true)
            }
            .foregroundStyle(.white.opacity(hovering ? 1 : 0.8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(shortcut)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.2)
        .onHover { hovering = $0 }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
