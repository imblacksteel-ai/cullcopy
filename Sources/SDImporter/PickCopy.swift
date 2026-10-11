import AppKit
import ImageIO
import SwiftUI

/// 「選んでコピー」の1枚
struct PickPhoto: Identifiable, Hashable {
    let url: URL
    let date: Date
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
    @Published var loading = false
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

    private var loadTask: Task<Void, Never>?

    private init() {
        SettingsMigration.run()
        let defaults = UserDefaults.standard
        folders = (defaults.stringArray(forKey: "pickFolders") ?? []).map { URL(fileURLWithPath: $0, isDirectory: true) }
        destination = defaults.string(forKey: "pickDestination").map { URL(fileURLWithPath: $0, isDirectory: true) }
        reload()
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
        }
        reload()
    }

    func removeFolder(_ url: URL) {
        folders.removeAll { $0 == url }
        reload()
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

    // MARK: 写真の読み込み

    /// 選んだフォルダの写真を、撮影日時の順に並べる
    func reload() {
        loadTask?.cancel()
        let folders = folders
        folders.forEach { FolderAccess.shared.access($0) }
        guard !folders.isEmpty else {
            photos = []
            return
        }
        loading = true
        loadTask = Task {
            let found = await Task.detached { () -> [PickPhoto] in
                var seen = Set<String>()
                var result: [PickPhoto] = []
                for folder in folders {
                    for url in Importer.mediaFiles(in: folder)
                    where Importer.photoExtensions.contains(url.pathExtension.lowercased()) && seen.insert(url.path).inserted {
                        if Task.isCancelled { return [] }
                        result.append(PickPhoto(url: url, date: Importer.captureDate(of: url)))
                    }
                }
                return result.sorted { ($0.date, $0.url.lastPathComponent) < ($1.date, $1.url.lastPathComponent) }
            }.value
            guard !Task.isCancelled else { return }
            photos = found
            index = min(index, max(found.count - 1, 0))
            loading = false
            refreshCopied()
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

// MARK: - 大きなプレビュー用の画像

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

// MARK: - タブの画面（フォルダとサムネイル一覧）

struct PickView: View {
    @ObservedObject var state: PickState
    @Environment(\.openWindow) private var openWindow

    private let columns = [GridItem(.adaptive(minimum: 128, maximum: 160), spacing: 12)]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                Form {
                    LabeledContent("写真のフォルダ") {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(state.folders, id: \.self) { folder in
                                HStack {
                                    Image(systemName: "folder.fill").foregroundStyle(.blue)
                                    Text(folder.path).lineLimit(1).truncationMode(.middle)
                                    Spacer()
                                    Button {
                                        state.removeFolder(folder)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.borderless)
                                    .help("一覧から外す（フォルダは消えません）")
                                }
                            }
                            Button("フォルダを追加…") { state.addFolders() }
                        }
                    }
                    LabeledContent("コピー先") {
                        HStack {
                            Text(state.destination?.path ?? String(localized: "未選択"))
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .foregroundStyle(state.destination == nil ? .secondary : .primary)
                            Button("変更…") { state.chooseDestination() }
                        }
                    }
                }

                Text("サブフォルダの写真も含めて、撮影日時の順に並べます。写真をダブルクリックすると、大きなプレビューが開きます。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                BigActionButton(title: "プレビュー開始", systemImage: "rectangle.and.hand.point.up.left.filled",
                                shortcut: .defaultAction) {
                    openPreview(at: nil)
                }
                .disabled(state.photos.isEmpty)
            }
            .padding(20)

            Divider()

            grid
        }
    }

    @ViewBuilder
    private var grid: some View {
        if state.loading {
            ProgressView("写真を読み込んでいます…")
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
                Text("\(state.photos.count) 枚（コピー済み \(state.copied.count) 枚）")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(state.photos) { photo in
                            PickThumbnail(photo: photo, selected: state.selection == photo.id, copied: state.copied.contains(photo.url))
                                .onTapGesture(count: 2) { openPreview(at: photo) }
                                .onTapGesture { state.selection = photo.id }
                        }
                    }
                    .padding(20)
                }
            }
        }
    }

    private func openPreview(at photo: PickPhoto?) {
        state.open(at: photo)
        openWindow(id: "pick-preview")
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

// MARK: - 大きなプレビューのウィンドウ

struct PickPreviewView: View {
    @ObservedObject var state: PickState
    @State private var image: NSImage?
    @State private var showFlash = false

    var body: some View {
        VStack(spacing: 0) {
            if let photo = state.current {
                header(photo)
                Divider()
                ZStack {
                    Color.black.opacity(0.85)
                    if let image {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .padding(12)
                            .id(photo.url)
                            .transition(.opacity)
                    } else {
                        ProgressView().controlSize(.large).tint(.white)
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
                .animation(.easeInOut(duration: 0.15), value: photo.url)
                Divider()
                controls(photo)
            } else {
                ContentUnavailableView("写真がありません", systemImage: "photo",
                                       description: Text("「選んでコピー」タブで、写真のフォルダを追加してください。"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
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
        image = await PreviewImageCache.shared.image(for: photo.url)
        let neighbors = [state.index - 1, state.index + 1, state.index + 2]
            .filter { state.photos.indices.contains($0) }
            .map { state.photos[$0].url }
        PreviewImageCache.shared.prefetch(neighbors)
    }

    private func header(_ photo: PickPhoto) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(photo.url.lastPathComponent).font(.title3.weight(.bold)).lineLimit(1)
                Text(details(photo)).font(.callout).foregroundStyle(.secondary).lineLimit(1)
            }
            if state.copied.contains(photo.url) {
                Label("コピー済み", systemImage: "checkmark.circle.fill")
                    .font(.callout.weight(.bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.green, in: Capsule())
                    .foregroundStyle(.white)
            }
            Spacer()
            Text("\(state.index + 1) / \(state.photos.count)")
                .font(.title2.weight(.heavy).monospacedDigit())
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private func details(_ photo: PickPhoto) -> String {
        var parts: [String] = []
        if photo.date != .distantPast { parts.append(photo.date.formatted(date: .numeric, time: .standard)) }
        if let size = (try? photo.url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize {
            parts.append(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
        }
        parts.append(photo.url.deletingLastPathComponent().path)
        return parts.joined(separator: "  ·  ")
    }

    private func controls(_ photo: PickPhoto) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 16) {
                Button(action: state.previous) {
                    Label("前", systemImage: "chevron.left")
                        .font(.title3.weight(.bold))
                        .frame(width: 160, height: 52)
                }
                .buttonStyle(BigButtonStyle(tint: .accentColor))
                .keyboardShortcut(.leftArrow, modifiers: [])
                .disabled(state.index == 0)

                Button(action: state.copyAndNext) {
                    Label(state.copied.contains(photo.url) ? "コピー済み・次へ" : "コピーして次へ",
                          systemImage: state.copying ? "hourglass" : "square.and.arrow.down.on.square.fill")
                        .font(.title2.weight(.heavy))
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(BigButtonStyle(tint: .green))
                .keyboardShortcut(.return, modifiers: [])
                .disabled(state.copying)

                Button(action: state.next) {
                    Label {
                        Text("次")
                    } icon: {
                        Image(systemName: "chevron.right")
                    }
                    .labelStyle(TrailingIcon())
                    .font(.title3.weight(.bold))
                    .frame(width: 160, height: 52)
                }
                .buttonStyle(BigButtonStyle(tint: .accentColor))
                .keyboardShortcut(.rightArrow, modifiers: [])
                .disabled(state.index >= state.photos.count - 1)
            }
            HStack {
                Text("コピー先：\(state.destination?.path ?? String(localized: "未選択"))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Button("変更…") { state.chooseDestination() }.controlSize(.small)
                Spacer()
                Text("← → で移動、Return でコピーして次へ").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}

private struct TrailingIcon: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.title
            configuration.icon
        }
    }
}
