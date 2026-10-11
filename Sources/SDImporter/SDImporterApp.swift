import SwiftUI
import UserNotifications

@main
struct SDImporterApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @StateObject private var state = AppState.shared
    @StateObject private var duplicates = DuplicateState.shared

    var body: some Scene {
        Window("CullCopy", id: "main") {
            RootView(state: state, duplicates: duplicates)
        }
        .windowResizability(.contentMinSize)

        Window("プレビュー", id: "pick-preview") {
            PickPreviewView(state: PickState.shared)
        }
        .defaultSize(width: 1400, height: 920)

        MenuBarExtra {
            MenuBarContent(state: state, duplicates: duplicates, pick: PickState.shared)
        } label: {
            MenuBarLabel(state: state, duplicates: duplicates, pick: PickState.shared)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if !granted { NSLog("SDImporter: 通知が許可されていません %@", error?.localizedDescription ?? "") }
        }
    }

    /// コピー中・チェック中にウィンドウを閉じても、終わるまでは動き続ける（メニューバーから様子を見られる）
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !AppState.shared.isBusy && !DuplicateState.shared.isBusy
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard AppState.shared.isBusy else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = String(localized: "コピー中です。終了しますか？")
        alert.informativeText = String(localized: "コピーが終わっているファイルは残ります。次に「開始」を押すと続きからコピーできます。")
        alert.addButton(withTitle: String(localized: "終了しない"))
        alert.addButton(withTitle: String(localized: "終了する"))
        return alert.runModal() == .alertSecondButtonReturn ? .terminateNow : .terminateCancel
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        NSApp.dockTile.badgeLabel = nil
    }

    /// アプリが前面にあっても通知を表示する
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}

// MARK: - メニューバー

/// メニューバーの表示。取り込み中はその進捗、重複チェック中はその進捗（両方なら取り込みを優先）
/// メニューバーの表示。動いている作業ごとに、機能のアイコンと進み具合を横に並べる
/// （例: [取り込みのアイコン] コピー中 128/340   [選んでコピーのアイコン] 読み込み中 444/5555）
struct MenuBarLabel: View {
    @ObservedObject var state: AppState
    @ObservedObject var duplicates: DuplicateState
    @ObservedObject var pick: PickState

    var body: some View {
        Image(nsImage: MenuBarImage.make(segments))
    }

    private var segments: [MenuBarImage.Segment] {
        var result: [MenuBarImage.Segment] = []
        switch state.phase {
        case .copying:
            result.append(.init(feature: .importer, text: String(localized: "コピー中 \(state.done)/\(state.total)")))
        case .scanning:
            result.append(.init(feature: .importer, text: String(localized: "確認中")))
        case .deleting:
            result.append(.init(feature: .importer, text: String(localized: "削除中")))
        case .ready, .finished:
            break
        }
        switch duplicates.phase {
        case .listing:
            result.append(.init(feature: .duplicates, text: String(localized: "ファイル確認中 \(duplicates.scannedFiles)")))
        case .comparing:
            result.append(.init(feature: .duplicates, text: String(localized: "比較中 \(duplicates.compared)/\(duplicates.candidates)")))
        case .ready, .finished:
            break
        }
        if pick.loadTotal > 0 {
            result.append(.init(feature: .pick, text: String(localized: "読み込み中 \(pick.loadDone)/\(pick.loadTotal)")))
        }
        return result
    }
}

struct MenuBarContent: View {
    @ObservedObject var state: AppState
    @ObservedObject var duplicates: DuplicateState
    @ObservedObject var pick: PickState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Section("取り込み") {
            switch state.phase {
            case .ready:
                Text("待機中")
            case .scanning:
                Text("ファイルを確認中…")
            case .copying:
                Text("コピー中：\(state.done) / \(state.total) 件（残り \(state.remaining) 件）")
                if !state.currentFile.isEmpty {
                    Text(state.currentFile)
                }
            case .finished:
                Text(state.resultMessage.isEmpty ? state.resultTitle : "\(state.resultTitle)：\(state.resultMessage)")
            case .deleting:
                Text("コピー元を削除中…")
            }
            if state.isBusy {
                Button("取り込みをキャンセル") { state.cancel() }
            }
        }

        Section("重複チェック") {
            switch duplicates.phase {
            case .ready:
                Text("待機中")
            case .listing:
                Text("ファイルを数えています… \(duplicates.scannedFiles) 件")
            case .comparing:
                Text("中身を比較中：\(duplicates.compared) / \(duplicates.candidates) 件（残り \(max(duplicates.candidates - duplicates.compared, 0)) 件）")
            case .finished:
                Text(duplicates.message.isEmpty ? duplicates.resultTitle : "\(duplicates.resultTitle)：\(duplicates.message)")
            }
            if duplicates.isBusy {
                Button("重複チェックをキャンセル") { duplicates.cancel() }
            }
        }

        Section("選んでコピー") {
            if pick.loadTotal > 0 {
                Text("読み込み中：\(pick.loadDone) / \(pick.loadTotal) 枚")
            } else if pick.folders.isEmpty {
                Text("待機中")
            } else {
                Text("\(pick.photos.count) 枚（コピー済み \(pick.copied.count) 枚）")
            }
        }

        Divider()

        Button("ウィンドウを開く") { show("main") }
            .keyboardShortcut("0")
        #if APPSTORE
        Button("開発を支援する…") {
            show("main")   // チップの画面はメインウィンドウに出す
            Support.open()
        }
        #endif

        Divider()

        Button("終了") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func show(_ id: String) {
        openWindow(id: id)
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// 画面上部の大きなタブ（改修メモ #2）
enum AppTab: String, CaseIterable {
    case importer
    case duplicates
    case pick

    var title: LocalizedStringKey {
        switch self {
        case .importer: return "取り込み"
        case .duplicates: return "重複チェック"
        case .pick: return "選んでコピー"
        }
    }

    var feature: Feature {
        switch self {
        case .importer: return .importer
        case .duplicates: return .duplicates
        case .pick: return .pick
        }
    }

    var shortcut: KeyboardShortcut {
        switch self {
        case .importer: return .tabImport
        case .duplicates: return .tabDuplicates
        case .pick: return .tabPick
        }
    }
}

struct AppTabBar: View {
    @Binding var selection: AppTab

    var body: some View {
        HStack(spacing: 10) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                AppTabButton(tab: tab, selected: selection == tab) {
                    withAnimation(.snappy(duration: 0.2)) { selection = tab }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

private struct AppTabButton: View {
    let tab: AppTab
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                FeatureGlyph(feature: tab.feature, size: 22)
                Text(tab.title)
                KeyHint(text: tab.shortcut.symbol, onColor: selected)
            }
                .font(.title3.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 46)
                .foregroundStyle(selected ? .white : .primary)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(selected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.secondary.opacity(hovering ? 0.18 : 0.10)))
                )
                .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .keyboardShortcut(tab.shortcut)
        .onHover { hovering = $0 }
    }
}

struct RootView: View {
    @ObservedObject var state: AppState
    @ObservedObject var duplicates: DuplicateState
    #if APPSTORE
    @ObservedObject private var tips = TipStore.shared
    #endif

    @AppStorage("selectedTab") private var tab: AppTab = .importer

    var body: some View {
        VStack(spacing: 0) {
            AppTabBar(selection: $tab)
            Divider()
            switch tab {
            case .importer:
                ContentView(state: state)
            case .duplicates:
                DuplicateView(state: duplicates, importDestination: state.destination)
            case .pick:
                PickView(state: PickState.shared)
            }
        }
        .frame(minWidth: 960, minHeight: 720)
        #if APPSTORE
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Support.open()
                } label: {
                    Label("開発を支援する", systemImage: "heart")
                }
                .help("開発を支援する")
            }
        }
        .sheet(isPresented: $tips.isPresented) {
            TipJarView(store: tips)
        }
        #endif
    }
}

struct ContentView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                settings
                actionButton
                progress
            }
            .padding(20)
            .animation(.spring(duration: 0.45, bounce: 0.3), value: state.phase)
            .animation(.spring(duration: 0.45, bounce: 0.3), value: state.deletableItems.isEmpty)

            Divider()

            HistoryView(history: state.history)
                .frame(minHeight: 200, maxHeight: .infinity)
        }
        .overlay { ConfettiView(trigger: state.celebration) }
    }

    // MARK: 1・2 コピー元とフォルダ分けの選択

    private var settings: some View {
        VStack(alignment: .leading, spacing: 12) {
            // コピー元：SDカードの一覧から選ぶか、フォルダを選ぶ
            HStack(spacing: 14) {
                Image(systemName: state.source.map { Importer.isCameraCard($0) ? "sdcard.fill" : "externaldrive.fill" } ?? "sdcard")
                    .font(.system(size: 30))
                    .foregroundStyle(.blue)
                    .frame(width: 40)
                VStack(alignment: .leading, spacing: 4) {
                    Text("コピー元").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Picker("コピー元", selection: $state.source) {
                        if state.volumes.isEmpty && state.source == nil {
                            Text("SDカードが見つかりません").tag(URL?.none)
                        }
                        ForEach(state.volumes, id: \.self) { volume in
                            Label(volume.lastPathComponent, systemImage: Importer.isCameraCard(volume) ? "sdcard" : "externaldrive")
                                .tag(URL?.some(volume))
                        }
                        if let source = state.source, !state.volumes.contains(source) {
                            Label(source.lastPathComponent, systemImage: "folder").tag(URL?.some(source))
                        }
                    }
                    .labelsHidden()
                    .controlSize(.large)
                    .font(.title3)
                    if let source = state.source {
                        Text(source.path).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    state.refreshVolumes(select: nil)
                } label: {
                    ShortcutLabel("更新", systemImage: "arrow.clockwise", shortcut: .refreshVolumes)
                }
                .controlSize(.large)
                .keyboardShortcut(.refreshVolumes)
                .help("SDカードの一覧を更新")
                Button {
                    state.chooseSourceFolder()
                } label: {
                    ShortcutLabel("フォルダを選ぶ…", systemImage: "folder.badge.plus", shortcut: .chooseFolder)
                }
                .controlSize(.large)
                .keyboardShortcut(.chooseFolder)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.secondary.opacity(0.07)))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.secondary.opacity(0.18)))

            if state.sourceNeedsAccess {
                HStack {
                    Label("このSDカードを読むには、最初に許可が必要です", systemImage: "lock.fill")
                        .foregroundStyle(.orange)
                    Spacer()
                    Button("アクセスを許可…") { state.grantSourceAccess() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                }
                .padding(.horizontal, 16)
            }

            FolderBox(title: "コピー先", url: state.destination, buttonTitle: "変更…", shortcut: .chooseDestination) {
                state.chooseDestination()
            }

            // フォルダ名の形式
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "calendar")
                    .font(.system(size: 28))
                    .foregroundStyle(.blue)
                    .frame(width: 40)
                VStack(alignment: .leading, spacing: 6) {
                    Text("フォルダ名").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    HStack {
                        TextField("空欄ならフォルダ分けしない", text: $state.template)
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .font(.title3.monospaced())
                            .controlSize(.large)
                        Menu {
                            ForEach(FolderFormat.presets, id: \.self) { preset in
                                Button("\(preset)　→　\(FolderFormat.relativePath(template: preset, day: "2026-08-15"))") {
                                    state.template = preset
                                }
                            }
                            Divider()
                            Button("フォルダ分けしない") { state.template = "" }
                        } label: {
                            Label("よく使う形式", systemImage: "list.bullet")
                        }
                        .controlSize(.large)
                        .fixedSize()
                    }
                    Text("yyyy=年  yy=年(2桁)  MM=月  dd=日　/ で区切るとサブフォルダ")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        Text("保存例").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Text(state.examplePath).font(.caption).lineLimit(1).truncationMode(.head).textSelection(.enabled)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.secondary.opacity(0.07)))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.secondary.opacity(0.18)))
        }
        .disabled(state.isBusy)
    }

    // MARK: 4 開始ボタンと進捗

    private var actionButton: some View {
        HStack(spacing: 12) {
            if state.isBusy {
                BigActionButton(title: "キャンセル", systemImage: "stop.fill", tint: .red, shortcut: .cancelAction) {
                    state.cancel()
                }
                .disabled(state.phase == .deleting)
            } else {
                BigActionButton(title: "取り込み開始", systemImage: "play.fill", shortcut: .start) {
                    state.start()
                }
                .disabled(state.source == nil)
            }
            Button {
                state.openDestination()
            } label: {
                ShortcutLabel("コピー先を開く", systemImage: "folder", shortcut: .openDestination, onColor: true)
                    .font(.headline)
                    .frame(width: 220, height: 56)
            }
            .buttonStyle(BigButtonStyle(tint: .gray))
            .keyboardShortcut(.openDestination)
            .help("コピー先をFinderで開く")
        }
    }

    @ViewBuilder
    private var progress: some View {
        switch state.phase {
        case .ready:
            EmptyView()
        case .scanning:
            ProgressCard(title: "ファイルを確認中…", systemImage: "magnifyingglass", detail: "コピー元の写真・動画を探しています")
        case .copying:
            ProgressCard(title: "コピー中", systemImage: "arrow.down.circle.fill", done: state.done, total: state.total,
                         detail: "\(state.done) / \(state.total) 件（残り \(state.remaining) 件）　\(state.currentFile)")
        case .finished:
            ResultCard(outcome: state.outcome, title: state.resultTitle, message: state.resultMessage) {
                if !state.deletableItems.isEmpty {
                    deletePrompt
                }
                if !state.deleteMessage.isEmpty {
                    Label(state.deleteMessage, systemImage: "trash").font(.callout)
                }
            }
        case .deleting:
            ProgressCard(title: "コピー元を削除中…", systemImage: "trash", detail: "中身を照合してから削除しています", tint: .red)
        }
    }

    private var deletePrompt: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Text("コピー元フォルダを削除しますか？").font(.headline)
                Text(state.lastSourceIsVolume
                    ? String(localized: "コピー先にあることを確認できた \(state.deletableItems.count) 件の写真・動画をSDカードから削除します。フォルダ構成（DCIM など）は残します。")
                    : String(localized: "コピー先にあることを確認できた \(state.deletableItems.count) 件の写真・動画を削除し、空になったフォルダも削除します。"))
                    .fixedSize(horizontal: false, vertical: true)
                Text("ゴミ箱には入らず、元に戻せません。").foregroundStyle(.red)
                HStack {
                    Spacer()
                    Button {
                        state.keepSources()
                    } label: {
                        ShortcutLabel("残す", shortcut: .keepSources)
                    }
                    .controlSize(.large)
                    .keyboardShortcut(.keepSources)
                    Button(role: .destructive) {
                        state.deleteSources()
                    } label: {
                        ShortcutLabel("削除する", systemImage: "trash", shortcut: .deleteSources, onColor: true)
                    }
                    .keyboardShortcut(.deleteSources)
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
            }
            .padding(4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

}
