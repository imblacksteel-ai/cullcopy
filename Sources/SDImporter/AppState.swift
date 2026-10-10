import AppKit

@MainActor
final class AppState: ObservableObject {
    enum Phase: Equatable {
        case ready
        case scanning
        case copying
        case finished
    }

    // MARK: 設定

    @Published var volumes: [URL] = []
    @Published var source: URL?
    @Published var destination: URL {
        didSet { UserDefaults.standard.set(destination.path, forKey: "destination") }
    }
    @Published var format: FolderFormat {
        didSet { UserDefaults.standard.set(format.rawValue, forKey: "folderFormat") }
    }

    // MARK: 進捗

    @Published var phase: Phase = .ready
    @Published var total = 0
    @Published var done = 0
    @Published var skipped = 0
    @Published var currentFile = ""
    @Published var resultMessage = ""

    var isBusy: Bool { phase == .scanning || phase == .copying }

    private var task: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []

    init() {
        let defaults = UserDefaults.standard
        if let path = defaults.string(forKey: "destination") {
            destination = URL(fileURLWithPath: path, isDirectory: true)
        } else {
            destination = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("SD Import", isDirectory: true)
        }
        format = defaults.string(forKey: "folderFormat").flatMap(FolderFormat.init(rawValue:)) ?? .yearThenDay

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
        panel.prompt = "コピー元にする"
        if panel.runModal() == .OK, let url = panel.url {
            source = url
        }
    }

    func chooseDestination() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = destination
        panel.prompt = "ここに保存"
        if panel.runModal() == .OK, let url = panel.url {
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
        let folder = format.relativePath(day: day)
        let file = "IMG_0001.JPG"
        return destination.appendingPathComponent(folder.isEmpty ? file : "\(folder)/\(file)").path
    }

    func start() {
        guard let source, !isBusy else { return }
        let root = destination
        let format = format

        phase = .scanning
        total = 0
        done = 0
        skipped = 0
        currentFile = ""
        resultMessage = ""

        task = Task {
            let plan = await Task.detached { await Importer.plan(volume: source, destinationRoot: root, format: format) }.value
            if Task.isCancelled {
                finish("キャンセルしました")
                return
            }
            skipped = plan.skipped
            total = plan.items.count
            guard !plan.items.isEmpty else {
                finish(plan.skipped > 0 ? "新しいファイルはありません（取り込み済み \(plan.skipped) 件）" : "写真・動画が見つかりませんでした")
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
            var message = result.cancelled ? "中断しました：\(result.copied) 件コピー" : "完了：\(result.copied) 件コピー"
            if plan.skipped > 0 { message += "、取り込み済み \(plan.skipped) 件をスキップ" }
            if !result.failed.isEmpty {
                message += "、失敗 \(result.failed.count) 件"
                for (url, error) in result.failed {
                    NSLog("SDImporter: 失敗 %@ - %@", url.path, error.localizedDescription)
                }
            }
            finish(message)
        }
    }

    func cancel() {
        task?.cancel()
    }

    private func finish(_ message: String) {
        resultMessage = message
        currentFile = ""
        phase = .finished
        task = nil
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}
