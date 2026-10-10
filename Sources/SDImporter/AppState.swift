import AppKit
import UserNotifications

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    enum Phase: Equatable {
        case ready
        case scanning
        case copying
        case finished
        case deleting
    }

    // MARK: 設定

    @Published var volumes: [URL] = []
    @Published var source: URL? {
        didSet { updateSourceAccess() }
    }
    /// App Store 版で、選んだコピー元を読む許可がまだないとき true（「アクセスを許可…」ボタンを出す）
    @Published var sourceNeedsAccess = false
    @Published var destination: URL {
        didSet { UserDefaults.standard.set(destination.path, forKey: "destination") }
    }
    /// フォルダ名の形式（例: "yyyy/yyyy年MM月dd日"）。書き方は FolderFormat を参照
    @Published var template: String {
        didSet { UserDefaults.standard.set(template, forKey: "folderTemplate") }
    }

    // MARK: 進捗

    @Published var phase: Phase = .ready
    @Published var total = 0
    @Published var done = 0
    @Published var skipped = 0
    @Published var currentFile = ""
    @Published var resultMessage = ""
    @Published var resultTitle = ""
    @Published var outcome: Outcome = .info
    /// 成功したときに増やす（紙吹雪のきっかけ）
    @Published var celebration = 0

    // MARK: コピー元の削除

    /// コピー先にあることが確認できた（削除してよい）コピー元ファイル
    @Published var deletableItems: [ImportItem] = []
    @Published var deleteMessage = ""
    private var lastSource: URL?

    // MARK: 履歴

    let history = HistoryStore<HistoryEntry>(fileName: "history.json")
    private var lastHistoryID: UUID?

    /// 残り件数（メニューバーの表示用）
    var remaining: Int { max(total - done, 0) }

    var isBusy: Bool { phase == .scanning || phase == .copying || phase == .deleting }

    /// 最後にコピーしたコピー元がSDカードなどのボリュームそのものか（フォルダ構成を残すかの判断に使う）
    var lastSourceIsVolume: Bool {
        guard let lastSource else { return false }
        return (try? lastSource.resourceValues(forKeys: [.isVolumeKey]))?.isVolume == true
    }

    private var task: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []

    init() {
        SettingsMigration.run()
        let defaults = UserDefaults.standard
        if let path = defaults.string(forKey: "destination") {
            destination = URL(fileURLWithPath: path, isDirectory: true)
        } else {
            destination = FolderAccess.realHome
                .appendingPathComponent("Pictures", isDirectory: true)
                .appendingPathComponent("SD Import", isDirectory: true)
        }
        if let saved = defaults.string(forKey: "folderTemplate") {
            template = saved
        } else if let oldFormat = defaults.string(forKey: "folderFormat") {
            // 旧バージョンの「形式＋区切り文字」の設定を引き継ぐ
            let oldSeparator = defaults.string(forKey: "separator") ?? "-"
            template = oldFormat == "none" ? "" : oldFormat.replacingOccurrences(of: "-", with: oldSeparator)
        } else {
            template = FolderFormat.defaultTemplate
        }

        // SDカードの抜き差しで一覧を更新する
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let mounted = note.name == NSWorkspace.didMountNotification
                    ? note.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL : nil
                MainActor.assumeIsolated { self?.refreshVolumes(select: mounted) }
            })
        }
        refreshVolumes(select: nil)
    }

    /// 外部ボリューム（SDカードなど）の一覧を更新する。カメラのカードを優先して選択する
    func refreshVolumes(select newVolume: URL?) {
        let keys: [URLResourceKey] = [.volumeIsInternalKey, .volumeIsRemovableKey, .volumeIsEjectableKey]
        let all = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        all.forEach { FolderAccess.shared.access($0) }   // App Store 版：許可済みのカードは中を見られるように
        volumes = all.filter { url in
            guard url.path.hasPrefix("/Volumes/"), let v = try? url.resourceValues(forKeys: Set(keys)) else { return false }
            return v.volumeIsRemovable == true || v.volumeIsEjectable == true || v.volumeIsInternal == false
        }
        .sorted { (Importer.isCameraCard($0) ? 0 : 1, $0.lastPathComponent) < (Importer.isCameraCard($1) ? 0 : 1, $1.lastPathComponent) }

        guard !isBusy else { return }
        if let newVolume, volumes.contains(newVolume) {
            source = newVolume
        } else if let current = source, !volumes.contains(current), current.path.hasPrefix("/Volumes/") {
            source = volumes.first // 選択中のカードが抜かれた
        } else if source == nil {
            source = volumes.first
        }
    }

    // MARK: 操作

    func chooseSourceFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = String(localized: "コピー元にする")
        if panel.runModal() == .OK, let url = panel.url {
            FolderAccess.shared.remember(url)
            source = url
        }
    }

    private func updateSourceAccess() {
        guard FolderAccess.isSandboxed, let source else {
            sourceNeedsAccess = false
            return
        }
        sourceNeedsAccess = !FolderAccess.shared.canRead(source)
    }

    /// App Store 版：コピー元（SDカード）を読む許可をもらう
    func grantSourceAccess() {
        guard let source else { return }
        let message = String(localized: "「\(source.lastPathComponent)」を選んだまま「許可」を押してください。次回からは聞かれません。")
        if let chosen = FolderAccess.shared.requestAccess(to: source, message: message) {
            self.source = chosen
            refreshVolumes(select: chosen)
        }
        updateSourceAccess()
    }

    /// App Store 版：コピー先に書き込めなければ、許可をもらう。書き込めるようになったら true
    private func ensureDestinationAccess() -> Bool {
        guard FolderAccess.isSandboxed else { return true }
        FolderAccess.shared.access(destination)
        var probe = destination
        while !FileManager.default.fileExists(atPath: probe.path), probe.pathComponents.count > 1 {
            probe.deleteLastPathComponent()
        }
        if FileManager.default.isWritableFile(atPath: probe.path) { return true }
        let message = String(localized: "コピー先「\(destination.lastPathComponent)」に保存する許可が必要です。フォルダを選んで「許可」を押してください。")
        guard let chosen = FolderAccess.shared.requestAccess(to: probe, message: message) else { return false }
        destination = chosen
        return true
    }

    func chooseDestination() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = destination
        panel.prompt = String(localized: "ここに保存")
        if panel.runModal() == .OK, let url = panel.url {
            FolderAccess.shared.remember(url)
            destination = url
        }
    }

    func openDestination() {
        try? FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        NSWorkspace.shared.open(destination)
    }

    /// 選択中の形式でのコピー先の例（今日の日付）
    var examplePath: String {
        let day = Self.dayFormatter.string(from: Date())
        let folder = FolderFormat.relativePath(template: template, day: day)
        let file = "IMG_0001.JPG"
        return destination.appendingPathComponent(folder.isEmpty ? file : "\(folder)/\(file)").path
    }

    func start() {
        guard let source, !isBusy else { return }
        if FolderAccess.isSandboxed {
            if !FolderAccess.shared.canRead(source) {
                grantSourceAccess()
                guard !sourceNeedsAccess else { return }
            }
            guard ensureDestinationAccess() else { return }
        }
        guard let source = self.source else { return }
        let root = destination
        let template = template

        phase = .scanning
        total = 0
        done = 0
        skipped = 0
        currentFile = ""
        resultMessage = ""
        deletableItems = []
        deleteMessage = ""
        lastSource = source
        lastHistoryID = nil
        NSApp.dockTile.badgeLabel = nil
        Sounds.start()

        task = Task {
            let plan = await Task.detached { await Importer.plan(volume: source, destinationRoot: root, template: template) }.value
            if Task.isCancelled {
                finish(title: String(localized: "キャンセルしました"), message: "", outcome: .cancelled)
                return
            }
            skipped = plan.skipped
            total = plan.items.count
            guard !plan.items.isEmpty else {
                deletableItems = plan.skippedItems
                let message = plan.skipped > 0 ? String(localized: "新しいファイルはありません（取り込み済み \(plan.skipped) 件）") : String(localized: "写真・動画が見つかりませんでした")
                record(source: source, root: root, template: template, plan: plan, result: ImportResult(), status: .nothingNew)
                finish(title: String(localized: "コピーするファイルはありませんでした"), message: message, outcome: .info)
                return
            }

            phase = .copying
            let copyTask = Task.detached {
                Importer.run(plan.items) { index, item in
                    Task { @MainActor in
                        self.done = index
                        self.currentFile = item.source.lastPathComponent
                    }
                }
            }
            let result = await withTaskCancellationHandler {
                await copyTask.value
            } onCancel: {
                copyTask.cancel()
            }

            done = result.copied + result.failed.count
            var message = result.cancelled ? String(localized: "\(result.copied) 件コピーしたところで中断しました") : String(localized: "\(result.copied) 件コピーしました")
            if plan.skipped > 0 { message += String(localized: "、取り込み済み \(plan.skipped) 件をスキップ") }
            if !result.failed.isEmpty {
                message += String(localized: "、失敗 \(result.failed.count) 件")
                for (url, error) in result.failed {
                    NSLog("SDImporter: 失敗 %@ - %@", url.path, error.localizedDescription)
                }
            }
            if !result.cancelled {
                deletableItems = result.copiedItems + plan.skippedItems
            }
            let status: HistoryEntry.Status = result.cancelled ? .cancelled : (result.failed.isEmpty ? .completed : .partiallyFailed)
            record(source: source, root: root, template: template, plan: plan, result: result, status: status)
            if result.cancelled {
                finish(title: String(localized: "コピーを中断しました"), message: message, outcome: .cancelled)
            } else if result.failed.isEmpty {
                finish(title: String(localized: "コピーが完了しました"), message: message, outcome: .success)
            } else {
                finish(title: String(localized: "コピーが完了しました（一部失敗）"), message: message, outcome: .warning)
            }
        }
    }

    private func record(source: URL, root: URL, template: String, plan: ImportPlan, result: ImportResult, status: HistoryEntry.Status) {
        var extensions: [String: Int] = [:]
        for item in plan.items {
            extensions[item.source.pathExtension.uppercased(), default: 0] += 1
        }
        let entry = HistoryEntry(
            date: Date(),
            sourceName: source.lastPathComponent,
            sourcePath: source.path,
            destinationPath: root.path,
            template: template,
            found: plan.items.count + plan.skipped,
            target: plan.items.count,
            copied: result.copied,
            failed: result.failed.count,
            remaining: plan.items.count - result.copied,
            skipped: plan.skipped,
            extensions: extensions,
            status: status,
            deletionOffered: !deletableItems.isEmpty
        )
        history.add(entry)
        lastHistoryID = entry.id
    }

    /// 完了の通知を出し、Dock のアイコンに印を付ける（アプリを前面に出すと消える）
    static func notifyFinished(title: String, body: String) {
        NSApp.dockTile.badgeLabel = "✓"
        NSApp.requestUserAttention(.informationalRequest)

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    func deleteSources() {
        guard let root = lastSource, !deletableItems.isEmpty, !isBusy else { return }
        let items = deletableItems
        let removeFolders = !lastSourceIsVolume
        phase = .deleting
        Task {
            let result = await Task.detached {
                Importer.deleteSources(items, root: root, removeEmptyFolders: removeFolders)
            }.value
            for (url, error) in result.failed {
                NSLog("SDImporter: 削除失敗 %@ - %@", url.path, error.localizedDescription)
            }
            deleteMessage = result.failed.isEmpty
                ? String(localized: "コピー元から \(result.deleted) 件を削除しました")
                : String(localized: "コピー元から \(result.deleted) 件を削除しました（削除できなかったもの \(result.failed.count) 件）")
            if let id = lastHistoryID {
                history.update(id: id) {
                    $0.deleted = ($0.deleted ?? 0) + result.deleted
                    $0.deleteFailed = ($0.deleteFailed ?? 0) + result.failed.count
                    $0.sourceAction = .deleted
                    $0.sourceActionDate = Date()
                }
            }
            deletableItems = []
            phase = .finished
            refreshVolumes(select: nil)
        }
    }

    func keepSources() {
        if let id = lastHistoryID {
            history.update(id: id) {
                $0.sourceAction = .kept
                $0.sourceActionDate = Date()
            }
        }
        deletableItems = []
        deleteMessage = String(localized: "コピー元はそのまま残しました")
    }

    func cancel() {
        task?.cancel()
    }

    private func finish(title: String, message: String, outcome: Outcome) {
        resultTitle = title
        resultMessage = message
        self.outcome = outcome
        currentFile = ""
        phase = .finished
        task = nil
        Sounds.finish(outcome)
        if outcome == .success { celebration += 1 }
        if outcome != .cancelled { Self.notifyFinished(title: title, body: message) }
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}
