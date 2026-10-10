import SwiftUI

@MainActor
final class DuplicateState: ObservableObject {
    enum Phase: Equatable {
        case ready
        case listing
        case comparing
        case finished
    }

    @Published var folder: URL? {
        didSet { UserDefaults.standard.set(folder?.path, forKey: "duplicateFolder") }
    }
    @Published var phase: Phase = .ready
    @Published var scannedFiles = 0
    @Published var candidates = 0
    @Published var compared = 0
    @Published var result: DuplicateScanResult?
    @Published var message = ""

    var isBusy: Bool { phase == .listing || phase == .comparing }

    private var task: Task<Void, Never>?

    init() {
        if let path = UserDefaults.standard.string(forKey: "duplicateFolder") {
            folder = URL(fileURLWithPath: path, isDirectory: true)
        }
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = folder
        panel.prompt = "このフォルダを調べる"
        if panel.runModal() == .OK, let url = panel.url {
            folder = url
        }
    }

    func start() {
        guard let folder, !isBusy else { return }
        phase = .listing
        scannedFiles = 0
        candidates = 0
        compared = 0
        result = nil
        message = ""

        task = Task {
            let scan = Task.detached {
                try DuplicateFinder.find(in: folder) { p in
                    Task { @MainActor in
                        self.phase = p.stage == .listing ? .listing : .comparing
                        self.scannedFiles = p.scannedFiles
                        self.candidates = p.candidates
                        self.compared = p.compared
                    }
                }
            }
            do {
                let found = try await withTaskCancellationHandler {
                    try await scan.value
                } onCancel: {
                    scan.cancel()
                }
                result = found
                message = found.groups.isEmpty
                    ? "同じファイルは見つかりませんでした（\(found.scannedFiles) ファイルを確認）"
                    : "\(found.groups.count) 組の重複が見つかりました（\(found.scannedFiles) ファイルを確認）"
                if found.unreadable > 0 {
                    message += "。読めなかったファイル \(found.unreadable) 件"
                }
            } catch {
                message = error is CancellationError ? "キャンセルしました" : "エラー：\(error.localizedDescription)"
            }
            phase = .finished
            task = nil
        }
    }

    func cancel() {
        task?.cancel()
    }
}

struct DuplicateView: View {
    @ObservedObject var state: DuplicateState
    let importDestination: URL

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Form {
                    LabeledContent("調べるフォルダ") {
                        HStack {
                            Text(state.folder?.path ?? "未選択")
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .foregroundStyle(state.folder == nil ? .secondary : .primary)
                            Button("選択…") { state.chooseFolder() }
                            Button("取り込みのコピー先") { state.folder = importDestination }
                        }
                    }
                }
                .disabled(state.isBusy)

                Text("中身が完全に同じファイルを、サブフォルダまで含めて探します。隠しファイル・0バイトのファイル・写真ライブラリなどのパッケージの中身は対象外です。ファイルの削除や移動はしません。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                progress

                HStack {
                    if let result = state.result, !result.groups.isEmpty {
                        summary(result)
                    }
                    Spacer()
                    if state.isBusy {
                        Button("キャンセル", role: .cancel) { state.cancel() }
                            .keyboardShortcut(.cancelAction)
                    } else {
                        Button("検索開始") { state.start() }
                            .keyboardShortcut(.defaultAction)
                            .disabled(state.folder == nil)
                    }
                }
            }
            .padding(20)

            Divider()

            results
        }
    }

    @ViewBuilder
    private var progress: some View {
        switch state.phase {
        case .ready:
            EmptyView()
        case .listing:
            VStack(alignment: .leading, spacing: 6) {
                ProgressView().progressViewStyle(.linear)
                Text("ファイルを数えています… \(state.scannedFiles) 件").font(.callout.monospacedDigit()).foregroundStyle(.secondary)
            }
        case .comparing:
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: Double(state.compared), total: Double(max(state.candidates, 1)))
                Text("中身を比較中… \(state.compared) / \(state.candidates) 件（全 \(state.scannedFiles) ファイル中、サイズが同じもの）")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        case .finished:
            Label(state.message, systemImage: state.result?.groups.isEmpty == false ? "doc.on.doc" : "checkmark.circle")
                .font(.callout)
        }
    }

    private func summary(_ result: DuplicateScanResult) -> some View {
        let extra = result.groups.reduce(0) { $0 + $1.files.count - 1 }
        let wasted = result.groups.reduce(Int64(0)) { $0 + $1.wasted }
        return Text("余分なファイル \(extra) 個・余分な容量 \(bytes(wasted))")
            .font(.callout.bold())
    }

    @ViewBuilder
    private var results: some View {
        if let result = state.result, !result.groups.isEmpty, let root = state.folder {
            List {
                ForEach(result.groups) { group in
                    Section {
                        ForEach(group.files, id: \.self) { file in
                            DuplicateRow(file: file, root: root)
                        }
                    } header: {
                        Text("\(group.files.count) 個が同じ・各 \(bytes(group.size))・余分 \(bytes(group.wasted))")
                    }
                }
            }
        } else {
            ContentUnavailableView {
                Label(state.isBusy ? "検索中…" : "結果はまだありません", systemImage: "doc.on.doc")
            } description: {
                Text(state.isBusy ? "" : "フォルダを選んで「検索開始」を押してください。")
            }
            .frame(maxHeight: .infinity)
        }
    }

    private func bytes(_ n: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
    }
}

private struct DuplicateRow: View {
    let file: URL
    let root: URL

    var body: some View {
        HStack {
            Image(nsImage: NSWorkspace.shared.icon(forFile: file.path))
                .resizable()
                .frame(width: 16, height: 16)
            Text(relativePath)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(file.path)
            Spacer()
            if let date = modified {
                Text(date.formatted(date: .numeric, time: .shortened))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([file])
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .buttonStyle(.borderless)
            .help("Finderで表示")
        }
        .contextMenu {
            Button("Finderで表示") { NSWorkspace.shared.activateFileViewerSelecting([file]) }
            Button("開く") { NSWorkspace.shared.open(file) }
            Button("パスをコピー") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(file.path, forType: .string)
            }
        }
    }

    private var relativePath: String {
        let rootPath = root.standardizedFileURL.path
        let path = file.standardizedFileURL.path
        return path.hasPrefix(rootPath + "/") ? String(path.dropFirst(rootPath.count + 1)) : path
    }

    private var modified: Date? {
        (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }
}
