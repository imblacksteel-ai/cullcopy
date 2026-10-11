import SwiftUI

/// フォルダを選ぶ欄（改修メモ #3・#5・#6）。大きなアイコン・フォルダ名・パスと、右側に「選ぶ」ボタンを並べる。
/// 欄のどこを押してもフォルダを選べる
struct FolderBox<Accessory: View>: View {
    let title: LocalizedStringKey
    let url: URL?
    var systemImage = "folder.fill"
    var placeholder: LocalizedStringKey = "未選択"
    let buttonTitle: LocalizedStringKey
    var shortcut: KeyboardShortcut?
    let action: () -> Void
    @ViewBuilder var accessory: () -> Accessory

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 30))
                .foregroundStyle(.blue)
                .frame(width: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                if let url {
                    Text(url.lastPathComponent).font(.title3.weight(.semibold)).lineLimit(1)
                    Text(url.path).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                } else {
                    Text(placeholder).font(.title3).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            accessory()
            Button(action: action) {
                ShortcutLabel(buttonTitle, systemImage: "folder.badge.plus", shortcut: shortcut)
            }
            .controlSize(.large)
            .keyboardShortcut(ifPresent: shortcut)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.secondary.opacity(hovering ? 0.12 : 0.07)))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.secondary.opacity(0.18)))
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onTapGesture(perform: action)
        .onHover { hovering = $0 }
    }
}

extension FolderBox where Accessory == EmptyView {
    init(title: LocalizedStringKey, url: URL?, systemImage: String = "folder.fill", placeholder: LocalizedStringKey = "未選択",
         buttonTitle: LocalizedStringKey, shortcut: KeyboardShortcut? = nil, action: @escaping () -> Void) {
        self.init(title: title, url: url, systemImage: systemImage, placeholder: placeholder, buttonTitle: buttonTitle,
                  shortcut: shortcut, action: action) { EmptyView() }
    }
}

/// 折り返して横に並べるレイアウト（フォルダのチップ用）
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: proposal.width ?? maxX, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// 複数フォルダの欄：フォルダをチップで並べ、最後に「フォルダを追加」。チップにはフォルダ名と場所（親フォルダ）を出す
struct FolderListBox<Accessory: View>: View {
    let title: LocalizedStringKey
    let folders: [URL]
    var systemImage = "folder.fill"
    var caption: LocalizedStringKey?
    let onAdd: () -> Void
    let onRemove: (URL) -> Void
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 28))
                .foregroundStyle(.blue)
                .frame(width: 40)
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                FlowLayout(spacing: 8) {
                    ForEach(folders, id: \.self) { folder in
                        FolderChip(folder: folder) { onRemove(folder) }
                    }
                    Button(action: onAdd) {
                        ShortcutLabel("フォルダを追加…", systemImage: "plus", shortcut: .chooseFolder, onColor: true)
                            .frame(minHeight: 36)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.chooseFolder)
                    accessory()
                }
                if let caption {
                    Text(caption).font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.secondary.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.secondary.opacity(0.18)))
    }
}

extension FolderListBox where Accessory == EmptyView {
    init(title: LocalizedStringKey, folders: [URL], systemImage: String = "folder.fill", caption: LocalizedStringKey? = nil,
         onAdd: @escaping () -> Void, onRemove: @escaping (URL) -> Void) {
        self.init(title: title, folders: folders, systemImage: systemImage, caption: caption, onAdd: onAdd, onRemove: onRemove) { EmptyView() }
    }
}

/// フォルダのチップ：フォルダ名（太字）と、その下に場所（親フォルダのパス）。✕ で一覧から外す
struct FolderChip: View {
    let folder: URL
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder.fill").foregroundStyle(.blue).font(.title3)
            VStack(alignment: .leading, spacing: 0) {
                Text(folder.lastPathComponent).font(.body.weight(.semibold)).lineLimit(1)
                Text(folder.deletingLastPathComponent().path)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .frame(maxWidth: 240, alignment: .leading)
            }
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
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.14)))
        .help(folder.path)
    }
}

/// 複数の「調べるフォルダ」のうち、ファイルを含むものからの位置（例: "2026_09_23/sub/IMG_0001.JPG"）。
/// フォルダが1つなら、そのフォルダからの位置だけ
func displayPath(of url: URL, roots: [URL]) -> String {
    let path = url.standardizedFileURL.path
    guard let root = roots.map({ $0.standardizedFileURL.path }).filter({ path.hasPrefix($0 + "/") }).max(by: { $0.count < $1.count })
    else { return path }
    let relative = String(path.dropFirst(root.count + 1))
    return roots.count > 1 ? (root as NSString).lastPathComponent + "/" + relative : relative
}
