import SwiftUI

@main
struct SDImporterApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(state: state)
        } label: {
            Image(systemName: state.isBusy ? "arrow.down.circle.fill" : "sdcard")
        }
    }
}

struct MenuContent: View {
    @ObservedObject var state: AppState

    var body: some View {
        Text(statusText)

        Divider()

        if state.cameraVolumes.isEmpty {
            Text("SDカードが接続されていません")
        } else {
            ForEach(state.cameraVolumes, id: \.self) { volume in
                Button("「\(volume.lastPathComponent)」から取り込む") {
                    state.startImport(from: volume, askFirst: true)
                }
                .disabled(state.isBusy)
            }
        }

        Divider()

        Text("保存先: \(state.destination.path)")
        Button("保存先を変更…") { state.chooseDestination() }
        Button("保存先をFinderで開く") { state.openDestination() }

        Divider()

        Toggle("ログイン時に起動", isOn: Binding(
            get: { state.launchAtLogin },
            set: { state.setLaunchAtLogin($0) }
        ))
        Button("終了") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private var statusText: String {
        switch state.status {
        case .idle: return "待機中"
        case let .scanning(name): return "「\(name)」を確認中…"
        case let .importing(done, total): return "取り込み中… \(done) / \(total)"
        case let .finished(message): return message
        }
    }
}
