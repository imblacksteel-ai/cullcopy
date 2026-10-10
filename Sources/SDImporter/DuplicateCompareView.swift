import QuickLookThumbnailing
import SwiftUI
import UniformTypeIdentifiers

// MARK: - サムネイル

/// Quick Look でサムネイルを作る（写真・RAW・動画・PDF など Mac が表示できるもの全般）。ファイルは読むだけ
@MainActor
final class ThumbnailCache {
    static let shared = ThumbnailCache()
    private let cache = NSCache<NSString, NSImage>()

    func image(for url: URL, size: CGFloat) async -> NSImage? {
        let key = "\(url.path)#\(Int(size))" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: size, height: size),
                                                   scale: scale, representationTypes: .all)
        guard let rep = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) else {
            return nil
        }
        let image = rep.nsImage
        cache.setObject(image, forKey: key)
        return image
    }
}

struct FileThumbnail: View {
    let url: URL
    let size: CGFloat

    @State private var image: NSImage?
    @State private var loaded = false

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else if loaded {
                // サムネイルを作れない種類はアイコンを出す
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(size * 0.2)
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .frame(width: size, height: size)
        .task(id: url) {
            image = await ThumbnailCache.shared.image(for: url, size: size)
            loaded = true
        }
    }
}

// MARK: - 結果一覧のサムネイル列

/// 重複グループのサムネイルを横に並べる。タップで比較画面を開く
struct DuplicateThumbnailStrip: View {
    let group: DuplicateGroup
    let onCompare: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(group.files, id: \.self) { file in
                    Button(action: onCompare) {
                        VStack(spacing: 4) {
                            FileThumbnail(url: file, size: 96)
                                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                            Text(file.lastPathComponent)
                                .font(.caption)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(width: 96)
                        }
                    }
                    .buttonStyle(.plain)
                    .help("クリックで並べて比較")
                }
            }
            .padding(.vertical, 4)
        }
    }
}

// MARK: - 比較画面

/// 中身が同じファイルを横に並べて大きく表示する。前・次で重複グループを切り替え、不要なものはゴミ箱に入れられる
struct DuplicateCompareView: View {
    @ObservedObject var state: DuplicateState
    @Binding var index: Int?
    let root: URL
    @Environment(\.dismiss) private var dismiss

    @State private var pendingTrash: URL?

    private var groups: [DuplicateGroup] { state.result?.groups ?? [] }

    private var current: Int? {
        guard let index, !groups.isEmpty else { return nil }
        return min(index, groups.count - 1)
    }

    var body: some View {
        VStack(spacing: 0) {
            if let current {
                let group = groups[current]
                header(group, position: current)
                Divider()
                GeometryReader { geo in
                    ScrollView(.horizontal) {
                        HStack(alignment: .top, spacing: 16) {
                            let details = group.files.map(FileDetails.init)
                            let oldest = Self.oldest(in: details)
                            ForEach(details, id: \.url) { detail in
                                CompareColumn(detail: detail, root: root, isOldest: detail.url == oldest,
                                              isTrashing: state.isTrashing) {
                                    pendingTrash = detail.url
                                }
                            }
                        }
                        .padding(20)
                        // 画面より狭いときは中央に、広いときは横スクロール
                        .frame(minWidth: geo.size.width, minHeight: geo.size.height)
                    }
                }
                .id(group.id)
                .transition(.opacity)
                Divider()
                navigation(position: current)
            } else {
                ContentUnavailableView("重複はすべて片付きました", systemImage: "checkmark.circle",
                                       description: Text("比較する重複はもうありません。"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Button("閉じる") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .controlSize(.large)
                    .padding(20)
            }
        }
        .frame(minWidth: 960, idealWidth: 1120, minHeight: 760, idealHeight: 800)
        .animation(.easeInOut(duration: 0.2), value: current)
        .confirmationDialog("ゴミ箱に入れますか？", isPresented: Binding(
            get: { pendingTrash != nil },
            set: { if !$0 { pendingTrash = nil } }
        ), presenting: pendingTrash) { file in
            Button("ゴミ箱に入れる", role: .destructive) {
                if let current { state.trash(file, inGroup: groups[current].id) }
                pendingTrash = nil
            }
            Button("やめる", role: .cancel) { pendingTrash = nil }
        } message: { file in
            Text("「\(file.lastPathComponent)」をゴミ箱に入れます。\n直前に、残るファイルと中身が同じことを確かめます。ゴミ箱から元に戻せます。")
        }
        .alert("ゴミ箱に入れられませんでした", isPresented: Binding(
            get: { state.trashError != nil },
            set: { if !$0 { state.trashError = nil } }
        )) {
            Button("OK") { state.trashError = nil }
        } message: {
            Text(state.trashError ?? "")
        }
    }

    private func header(_ group: DuplicateGroup, position: Int) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(group.files.count) 個のファイルが同じです").font(.title2.weight(.bold))
                Text("中身は完全に一致しています（各 \(bytes(group.size))）。違うのは名前・場所・日付だけです。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if state.isTrashing {
                ProgressView().controlSize(.small)
                Text("確認してゴミ箱へ移動中…").font(.callout).foregroundStyle(.secondary)
            }
            Button("閉じる") { dismiss() }
                .keyboardShortcut(.cancelAction)
                .controlSize(.large)
        }
        .padding(20)
    }

    private func navigation(position: Int) -> some View {
        HStack(spacing: 16) {
            Button {
                index = position - 1
            } label: {
                Label("前の重複", systemImage: "chevron.left")
                    .font(.title3.weight(.bold))
                    .frame(width: 200, height: 48)
            }
            .buttonStyle(BigButtonStyle(tint: .accentColor))
            .keyboardShortcut(.leftArrow, modifiers: [])
            .disabled(position == 0)

            Spacer()
            Text("\(position + 1) / \(groups.count)")
                .font(.title2.weight(.heavy).monospacedDigit())
                .contentTransition(.numericText())
            Spacer()

            Button {
                index = position + 1
            } label: {
                Label {
                    Text("次の重複")
                } icon: {
                    Image(systemName: "chevron.right")
                }
                .labelStyle(TrailingIconLabelStyle())
                .font(.title3.weight(.bold))
                .frame(width: 200, height: 48)
            }
            .buttonStyle(BigButtonStyle(tint: .accentColor))
            .keyboardShortcut(.rightArrow, modifiers: [])
            .disabled(position >= groups.count - 1)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    /// 作成日（なければ変更日）が一番古いファイル。同じ日時が並ぶ場合は決められないので nil
    private static func oldest(in details: [FileDetails]) -> URL? {
        // 表示は秒単位なので、比較も秒単位で行う（1秒未満の差で「一番古い」を決めない）
        let dated = details.map { ($0.url, ($0.created ?? $0.modified ?? .distantFuture).timeIntervalSinceReferenceDate.rounded(.down)) }
        guard let minDate = dated.map(\.1).min() else { return nil }
        let candidates = dated.filter { $0.1 == minDate }
        return candidates.count == 1 ? candidates[0].0 : nil
    }

    private func bytes(_ n: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
    }
}

/// アイコンを文字の右に置く（「次へ ▶」用）
private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.title
            configuration.icon
        }
    }
}

private struct FileDetails {
    let url: URL
    let created: Date?
    let modified: Date?
    let size: Int64?

    init(_ url: URL) {
        self.url = url
        let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey, .fileSizeKey])
        created = values?.creationDate
        modified = values?.contentModificationDate
        size = values?.fileSize.map(Int64.init)
    }

    /// 例: "CR3（Canon RAW 3 イメージ）"
    var kind: String {
        let ext = url.pathExtension.uppercased()
        guard !ext.isEmpty else { return String(localized: "（拡張子なし）") }
        if let description = UTType(filenameExtension: url.pathExtension)?.localizedDescription {
            return String(localized: "\(ext)（\(description)）")
        }
        return ext
    }

    /// 例: "39.2 MB（41,123,456 バイト）"
    var sizeText: String {
        guard let size else { return "—" }
        return String(localized: "\(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))（\(size.formatted()) バイト）")
    }
}

private struct CompareColumn: View {
    let detail: FileDetails
    let root: URL
    let isOldest: Bool
    let isTrashing: Bool
    let onTrash: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            FileThumbnail(url: detail.url, size: 340)
                .frame(maxWidth: .infinity)
                .background(Color.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                .overlay(alignment: .topLeading) {
                    if isOldest {
                        Label("一番古い", systemImage: "clock.arrow.circlepath")
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.green, in: Capsule())
                            .foregroundStyle(.white)
                            .padding(8)
                    }
                }

            Text(detail.url.lastPathComponent)
                .font(.headline)
                .lineLimit(2)
                .textSelection(.enabled)

            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 4) {
                GridRow {
                    Text("場所").foregroundStyle(.secondary)
                    Text(folder).lineLimit(2).truncationMode(.head).textSelection(.enabled).help(detail.url.deletingLastPathComponent().path)
                }
                GridRow {
                    Text("種類").foregroundStyle(.secondary)
                    Text(detail.kind).lineLimit(1)
                }
                GridRow {
                    Text("サイズ").foregroundStyle(.secondary)
                    Text(detail.sizeText).monospacedDigit()
                }
                GridRow {
                    Text("作成日").foregroundStyle(.secondary)
                    Text(format(detail.created))
                }
                GridRow {
                    Text("変更日").foregroundStyle(.secondary)
                    Text(format(detail.modified))
                }
            }
            .font(.callout)

            HStack {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([detail.url])
                } label: {
                    Label("Finderで表示", systemImage: "magnifyingglass")
                }
                Button {
                    NSWorkspace.shared.open(detail.url)
                } label: {
                    Label("開く", systemImage: "arrow.up.forward.app")
                }
            }
            .controlSize(.large)

            Button(action: onTrash) {
                Label("ゴミ箱に入れる", systemImage: "trash.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 40)
            }
            .buttonStyle(BigButtonStyle(tint: .red))
            .disabled(isTrashing)
        }
        .frame(width: 340)
        .padding(12)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(isOldest ? Color.green.opacity(0.6) : .clear, lineWidth: 2))
    }

    /// 調べたフォルダからの相対的な場所
    private var folder: String {
        let rootPath = root.standardizedFileURL.path
        let dir = detail.url.deletingLastPathComponent().standardizedFileURL.path
        if dir == rootPath { return String(localized: "（調べたフォルダの直下）") }
        return dir.hasPrefix(rootPath + "/") ? String(dir.dropFirst(rootPath.count + 1)) : dir
    }

    private func format(_ date: Date?) -> String {
        date?.formatted(date: .numeric, time: .standard) ?? "—"
    }
}
