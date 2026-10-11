import SwiftUI

// アプリ全体のショートカットキー（改修メモ #4）。ボタン名の後ろに記号で表示する
// 同じキーでも、別のタブ・別の画面にあれば重ならない（表示中の画面のボタンだけが反応する）
extension KeyboardShortcut {
    // タブ
    static let tabImport = KeyboardShortcut("1", modifiers: .command)
    static let tabDuplicates = KeyboardShortcut("2", modifiers: .command)
    static let tabPick = KeyboardShortcut("3", modifiers: .command)
    // 各タブ共通
    static let start = KeyboardShortcut("r", modifiers: .command)
    static let chooseFolder = KeyboardShortcut("o", modifiers: .command)
    static let chooseDestination = KeyboardShortcut("o", modifiers: [.command, .shift])
    // 取り込み
    static let refreshVolumes = KeyboardShortcut("r", modifiers: [.command, .shift])
    static let openDestination = KeyboardShortcut("e", modifiers: .command)
    static let deleteSources = KeyboardShortcut(.delete, modifiers: .command)
    static let keepSources = KeyboardShortcut("k", modifiers: .command)
    static let showHistoryFile = KeyboardShortcut("h", modifiers: [.command, .option])
    static let clearHistory = KeyboardShortcut(.delete, modifiers: [.command, .option])
    // 重複チェック
    static let useImportDestination = KeyboardShortcut("i", modifiers: [.command, .shift])
    // 比較画面・プレビュー
    static let previousItem = KeyboardShortcut(.leftArrow, modifiers: [])
    static let nextItem = KeyboardShortcut(.rightArrow, modifiers: [])
    static let copyAndNext = KeyboardShortcut(.return, modifiers: [])
    static let copyAndNextSpace = KeyboardShortcut(.space, modifiers: [])
    static let toggleInfo = KeyboardShortcut("i", modifiers: [])

    /// 比較画面で N 番目のファイルをゴミ箱に入れる（⌘1〜⌘9）
    static func trashColumn(_ index: Int) -> KeyboardShortcut? {
        guard (0..<9).contains(index) else { return nil }
        return KeyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
    }

    /// ボタンに表示する記号（例: ⌘R、⇧⌘O、⏎、esc）
    var symbol: String {
        var text = ""
        if modifiers.contains(.control) { text += "⌃" }
        if modifiers.contains(.option) { text += "⌥" }
        if modifiers.contains(.shift) { text += "⇧" }
        if modifiers.contains(.command) { text += "⌘" }
        switch key {
        case .return: text += "⏎"
        case .escape: text += "esc"
        case .space: text += "space"
        case .delete: text += "⌫"
        case .leftArrow: text += "←"
        case .rightArrow: text += "→"
        case .upArrow: text += "↑"
        case .downArrow: text += "↓"
        case .tab: text += "⇥"
        default: text += String(key.character).uppercased()
        }
        return text
    }
}

/// キーの記号を小さな枠で表示する
struct KeyHint: View {
    let text: String
    var onColor = false   // 色付きのボタンの上に置くとき

    var body: some View {
        Text(text)
            .font(.system(.caption, design: .rounded).weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(onColor ? AnyShapeStyle(.white.opacity(0.9)) : AnyShapeStyle(.secondary))
            .background(onColor ? AnyShapeStyle(.white.opacity(0.22)) : AnyShapeStyle(.secondary.opacity(0.15)),
                        in: RoundedRectangle(cornerRadius: 5))
            .fixedSize()
    }
}

/// アイコン・ボタン名・キーの記号を並べたボタンの中身
struct ShortcutLabel: View {
    let title: LocalizedStringKey
    var systemImage: String?
    let shortcuts: [KeyboardShortcut]
    var onColor = false

    init(_ title: LocalizedStringKey, systemImage: String? = nil, shortcut: KeyboardShortcut?, onColor: Bool = false) {
        self.title = title
        self.systemImage = systemImage
        self.shortcuts = shortcut.map { [$0] } ?? []
        self.onColor = onColor
    }

    init(_ title: LocalizedStringKey, systemImage: String? = nil, shortcuts: [KeyboardShortcut], onColor: Bool = false) {
        self.title = title
        self.systemImage = systemImage
        self.shortcuts = shortcuts
        self.onColor = onColor
    }

    var body: some View {
        HStack(spacing: 8) {
            if let systemImage {
                Image(systemName: systemImage)
            }
            Text(title)
            if !shortcuts.isEmpty {
                KeyHint(text: shortcuts.map(\.symbol).joined(separator: " / "), onColor: onColor)
            }
        }
    }
}

extension View {
    /// nil のときは何もしない keyboardShortcut
    @ViewBuilder
    func keyboardShortcut(ifPresent shortcut: KeyboardShortcut?) -> some View {
        if let shortcut { keyboardShortcut(shortcut) } else { self }
    }
}
