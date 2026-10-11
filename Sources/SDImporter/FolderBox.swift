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
