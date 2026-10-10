import QuickLookThumbnailing
import SwiftUI

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

/// 中身が同じファイルを横に並べて大きく表示する
struct DuplicateCompareView: View {
    let group: DuplicateGroup
    let root: URL
    @Environment(\.dismiss) private var dismiss

    private var details: [FileDetails] {
        group.files.map(FileDetails.init)
    }

    /// 作成日（なければ変更日）が一番古いファイル
    private var oldest: URL? {
        details.min { ($0.created ?? $0.modified ?? .distantFuture) < ($1.created ?? $1.modified ?? .distantFuture) }?.url
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(group.files.count) 個のファイルが同じです").font(.title2.weight(.bold))
                    Text("中身は完全に一致しています（各 \(bytes(group.size))）。違うのは名前・場所・日付だけです。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("閉じる") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .controlSize(.large)
            }
            .padding(20)

            Divider()

            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(details, id: \.url) { detail in
                        CompareColumn(detail: detail, root: root, isOldest: detail.url == oldest && group.files.count > 1)
                    }
                }
                .padding(20)
            }
        }
        .frame(minWidth: 900, idealWidth: 1100, minHeight: 620, idealHeight: 720)
    }

    private func bytes(_ n: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
    }
}

private struct FileDetails {
    let url: URL
    let created: Date?
    let modified: Date?

    init(_ url: URL) {
        self.url = url
        let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        created = values?.creationDate
        modified = values?.contentModificationDate
    }
}

private struct CompareColumn: View {
    let detail: FileDetails
    let root: URL
    let isOldest: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            FileThumbnail(url: detail.url, size: 360)
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
        }
        .frame(width: 360)
        .padding(12)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(isOldest ? Color.green.opacity(0.6) : .clear, lineWidth: 2))
    }

    /// 調べたフォルダからの相対的な場所
    private var folder: String {
        let rootPath = root.standardizedFileURL.path
        let dir = detail.url.deletingLastPathComponent().standardizedFileURL.path
        if dir == rootPath { return "（調べたフォルダの直下）" }
        return dir.hasPrefix(rootPath + "/") ? String(dir.dropFirst(rootPath.count + 1)) : dir
    }

    private func format(_ date: Date?) -> String {
        date?.formatted(date: .numeric, time: .standard) ?? "—"
    }
}
