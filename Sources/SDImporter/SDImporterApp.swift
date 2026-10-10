import SwiftUI
import UserNotifications

@main
struct SDImporterApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @StateObject private var state = AppState.shared
    @StateObject private var duplicates = DuplicateState()

    var body: some Scene {
        Window("SD Importer", id: "main") {
            RootView(state: state, duplicates: duplicates)
        }
        .windowResizability(.contentMinSize)

        MenuBarExtra {
            MenuBarContent(state: state)
        } label: {
            MenuBarLabel(state: state)
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

    /// コピー中にウィンドウを閉じても、終わるまでは動き続ける（メニューバーから様子を見られる）
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !AppState.shared.isBusy
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard AppState.shared.isBusy else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "コピー中です。終了しますか？"
        alert.informativeText = "コピーが終わっているファイルは残ります。次に「開始」を押すと続きからコピーできます。"
        alert.addButton(withTitle: "終了しない")
        alert.addButton(withTitle: "終了する")
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

struct MenuBarLabel: View {
    @ObservedObject var state: AppState

    var body: some View {
        switch state.phase {
        case .copying:
            Label("\(state.done)/\(state.total) 残り\(state.remaining)", systemImage: "arrow.down.circle")
                .labelStyle(.titleAndIcon)
        case .scanning, .deleting:
            Image(systemName: "hourglass")
        case .ready, .finished:
            Image(systemName: "sdcard")
        }
    }
}

struct MenuBarContent: View {
    @ObservedObject var state: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
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
            Text(state.resultMessage)
        case .deleting:
            Text("コピー元を削除中…")
        }

        Divider()

        Button("ウィンドウを開く") { show("main") }
        if state.isBusy {
            Button("キャンセル") { state.cancel() }
        }

        Divider()

        Button("終了") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func show(_ id: String) {
        openWindow(id: id)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct RootView: View {
    @ObservedObject var state: AppState
    @ObservedObject var duplicates: DuplicateState

    var body: some View {
        TabView {
            ContentView(state: state)
                .tabItem { Label("取り込み", systemImage: "sdcard") }
            DuplicateView(state: duplicates, importDestination: state.destination)
                .tabItem { Label("重複チェック", systemImage: "doc.on.doc") }
        }
        .frame(minWidth: 860, minHeight: 640)
    }
}

struct ContentView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                settings
                summary
                progress
                buttons
            }
            .padding(20)

            Divider()

            HistoryView(history: state.history)
                .frame(minHeight: 220, maxHeight: .infinity)
        }
    }

    // MARK: 1・2 コピー元とフォルダ分けの選択

    private var settings: some View {
        Form {
            LabeledContent("コピー元") {
                HStack {
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
                    Button("フォルダ…") { state.chooseSourceFolder() }
                    Button {
                        state.refreshVolumes(select: nil)
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("SDカードの一覧を更新")
                }
            }

            LabeledContent("コピー先") {
                HStack {
                    Text(state.destination.path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("変更…") { state.chooseDestination() }
                }
            }

            LabeledContent("フォルダ名") {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        TextField("空欄ならフォルダ分けしない", text: $state.template)
                            .labelsHidden()
                            .font(.body.monospaced())
                        Menu("よく使う形式") {
                            ForEach(FolderFormat.presets, id: \.self) { preset in
                                Button("\(preset)　→　\(FolderFormat.relativePath(template: preset, day: "2026-08-15"))") {
                                    state.template = preset
                                }
                            }
                            Divider()
                            Button("フォルダ分けしない") { state.template = "" }
                        }
                        .fixedSize()
                    }
                    Text("yyyy=年  yy=年(2桁)  MM=月  dd=日　/ で区切るとサブフォルダ")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .disabled(state.isBusy)
    }

    // MARK: 3 選択内容の表示

    private var summary: some View {
        GroupBox {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                GridRow {
                    Text("コピー元").foregroundStyle(.secondary)
                    Text(state.source?.path ?? "未選択").textSelection(.enabled)
                }
                GridRow {
                    Text("コピー先").foregroundStyle(.secondary)
                    Text(state.destination.path).textSelection(.enabled)
                }
                GridRow {
                    Text("保存例").foregroundStyle(.secondary)
                    Text(state.examplePath).textSelection(.enabled)
                }
            }
            .font(.callout)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        } label: {
            Text("選択内容")
        }
    }

    // MARK: 4 進捗

    @ViewBuilder
    private var progress: some View {
        switch state.phase {
        case .ready:
            EmptyView()
        case .scanning:
            VStack(alignment: .leading, spacing: 6) {
                ProgressView().progressViewStyle(.linear)
                Text("ファイルを確認中…").font(.callout).foregroundStyle(.secondary)
            }
        case .copying:
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: Double(state.done), total: Double(max(state.total, 1)))
                HStack {
                    Text("\(state.done) / \(state.total) 件")
                    Spacer()
                    Text(state.currentFile).lineLimit(1).truncationMode(.middle)
                }
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
            }
        case .finished:
            VStack(alignment: .leading, spacing: 10) {
                Label(state.resultMessage, systemImage: "checkmark.circle")
                if !state.deletableItems.isEmpty {
                    deletePrompt
                }
                if !state.deleteMessage.isEmpty {
                    Label(state.deleteMessage, systemImage: "trash")
                }
            }
            .font(.callout)
        case .deleting:
            VStack(alignment: .leading, spacing: 6) {
                ProgressView().progressViewStyle(.linear)
                Text("コピー元を削除中…").font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private var deletePrompt: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Text("コピー元フォルダを削除しますか？").font(.headline)
                Text(state.lastSourceIsVolume
                    ? "コピー先にあることを確認できた \(state.deletableItems.count) 件の写真・動画をSDカードから削除します。フォルダ構成（DCIM など）は残します。"
                    : "コピー先にあることを確認できた \(state.deletableItems.count) 件の写真・動画を削除し、空になったフォルダも削除します。")
                    .fixedSize(horizontal: false, vertical: true)
                Text("ゴミ箱には入らず、元に戻せません。").foregroundStyle(.red)
                HStack {
                    Spacer()
                    Button("残す") { state.keepSources() }
                    Button("削除する", role: .destructive) { state.deleteSources() }
                }
            }
            .padding(4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var buttons: some View {
        HStack {
            Button("コピー先をFinderで開く") { state.openDestination() }
            Spacer()
            if state.isBusy {
                Button("キャンセル", role: .cancel) { state.cancel() }
                    .keyboardShortcut(.cancelAction)
            } else {
                Button("開始") { state.start() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(state.source == nil)
            }
        }
    }
}
