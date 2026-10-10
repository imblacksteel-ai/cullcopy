import AppKit
import ServiceManagement
import UserNotifications

@MainActor
final class AppState: ObservableObject {
    enum Status: Equatable {
        case idle
        case scanning(String)
        case importing(done: Int, total: Int)
        case finished(String)
    }

    @Published var status: Status = .idle
    @Published var destination: URL {
        didSet { UserDefaults.standard.set(destination.path, forKey: "destination") }
    }
    @Published var cameraVolumes: [URL] = []
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled

    var isBusy: Bool {
        switch status {
        case .scanning, .importing: return true
        default: return false
        }
    }

    private var observers: [NSObjectProtocol] = []

    init() {
        if let path = UserDefaults.standard.string(forKey: "destination") {
            destination = URL(fileURLWithPath: path, isDirectory: true)
        } else {
            destination = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("SD Import", isDirectory: true)
        }

        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.didMountNotification, object: nil, queue: .main) { [weak self] note in
            guard let volume = note.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL else { return }
            MainActor.assumeIsolated {
                self?.refreshVolumes()
                if Importer.isCameraCard(volume) {
                    self?.startImport(from: volume, askFirst: true)
                }
            }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didUnmountNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshVolumes() }
        })
        refreshVolumes()
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func refreshVolumes() {
        let volumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: [.skipHiddenVolumes]) ?? []
        cameraVolumes = volumes.filter { $0.path.hasPrefix("/Volumes/") && Importer.isCameraCard($0) }
    }

    func startImport(from volume: URL, askFirst: Bool) {
        guard !isBusy else { return }
        let name = volume.lastPathComponent
        let root = destination
        status = .scanning(name)

        Task {
            let items = await Task.detached { await Importer.plan(volume: volume, destinationRoot: root) }.value

            guard !items.isEmpty else {
                status = .finished("\(name): 新しいファイルはありません")
                return
            }
            if askFirst && !confirm(volume: name, items: items) {
                status = .idle
                return
            }

            let total = items.count
            status = .importing(done: 0, total: total)
            let result = await Task.detached {
                Importer.run(items) { done in
                    Task { @MainActor in self.status = .importing(done: done, total: total) }
                }
            }.value

            var message = "\(name): \(result.copied) 件コピーしました"
            if !result.failed.isEmpty {
                message += "（失敗 \(result.failed.count) 件）"
                for (url, error) in result.failed {
                    NSLog("SDImporter: 失敗 %@ - %@", url.path, error.localizedDescription)
                }
            }
            status = .finished(message)
            notify(title: "取り込み完了", body: message)
        }
    }

    private func confirm(volume: String, items: [ImportItem]) -> Bool {
        let bytes = items.reduce(Int64(0)) { $0 + $1.size }
        let size = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "「\(volume)」を検出しました"
        alert.informativeText = "新しいファイル \(items.count) 件（\(size)）を\n\(destination.path)\nにコピーしますか？\n\nSDカードのファイルは削除しません。"
        alert.addButton(withTitle: "取り込む")
        alert.addButton(withTitle: "キャンセル")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    func chooseDestination() {
        NSApp.activate(ignoringOtherApps: true)
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

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("SDImporter: ログイン項目の変更に失敗 - %@", error.localizedDescription)
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}
