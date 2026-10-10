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

    let history = HistoryStore<DuplicateHistoryEntry>(fileName: "duplicate-history.json")
    /// 過去にチェックしたフォルダで開始しようとしたときの、前回の記録（確認ダイアログ用）
    @Published var pendingRecheck: DuplicateHistoryEntry?

    private var task: Task<Void, Never>?

    /// そのフォルダの最新のチェック記録
    func previousCheck(of folder: URL?) -> DuplicateHistoryEntry? {
        guard let folder else { return nil }
        let path = DuplicateHistoryEntry.normalize(folder)
        return history.entries.first { $0.folderPath == path }
    }

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

    /// 「検索開始」ボタン。過去にチェックしたフォルダなら、まず確認する
    func requestStart() {
        guard !isBusy else { return }
        if let previous = previousCheck(of: folder) {
            pendingRecheck = previous
        } else {
            start()
        }
    }

    func start() {
        pendingRecheck = nil
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
                record(folder: folder, status: .completed, result: found)
            } catch is CancellationError {
                message = "キャンセルしました"
                record(folder: folder, status: .cancelled, result: DuplicateScanResult(scannedFiles: scannedFiles))
            } catch {
                message = "エラー：\(error.localizedDescription)"
            }
            phase = .finished
            task = nil
        }
    }

    func cancel() {
        task?.cancel()
    }

    private func record(folder: URL, status: DuplicateHistoryEntry.Status, result: DuplicateScanResult) {
        history.add(DuplicateHistoryEntry(
            date: Date(),
            folderPath: DuplicateHistoryEntry.normalize(folder),
            status: status,
            scannedFiles: result.scannedFiles,
            groups: result.groups.count,
            extraFiles: result.groups.reduce(0) { $0 + $1.files.count - 1 },
            wastedBytes: result.groups.reduce(Int64(0)) { $0 + $1.wasted },
            unreadable: result.unreadable
        ))
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
                    if let previous = state.previousCheck(of: state.folder) {
                        LabeledContent("前回のチェック") {
                            Text("\(previous.date.formatted(date: .numeric, time: .shortened))　\(previous.summary)")
                                .foregroundStyle(.secondary)
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
                        Button("検索開始") { state.requestStart() }
                            .keyboardShortcut(.defaultAction)
                            .disabled(state.folder == nil)
                    }
                }
            }
            .padding(20)

            Divider()

            results
                .frame(minHeight: 160, maxHeight: .infinity)

            Divider()

            DuplicateHistoryView(history: state.history)
                .frame(height: 180)
        }
        .alert("このフォルダはチェックしたことがあります", isPresented: Binding(
            get: { state.pendingRecheck != nil },
            set: { if !$0 { state.pendingRecheck = nil } }
        ), presenting: state.pendingRecheck) { _ in
            Button("再チェックする") { state.start() }
            Button("やめる", role: .cancel) { state.pendingRecheck = nil }
        } message: { previous in
            Text("前回：\(previous.date.formatted(date: .numeric, time: .shortened))\n結果：\(previous.summary)\n\nもう一度チェックしますか？")
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

private struct DuplicateHistoryView: View {
    @ObservedObject var history: HistoryStore<DuplicateHistoryEntry>
    @State private var confirmingClear = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("チェック履歴").font(.headline)
                Spacer()
                Button("履歴を消去…") { confirmingClear = true }
                    .disabled(history.entries.isEmpty)
            }
            .controlSize(.small)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)

            if history.entries.isEmpty {
                Text("チェックを実行すると、ここに記録されます。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(history.entries) {
                    TableColumn("日時") { e in
                        Text(e.date.formatted(date: .numeric, time: .shortened))
                    }
                    .width(min: 110, ideal: 130)
                    TableColumn("状態") { e in
                        Text(e.status.label).foregroundStyle(e.status == .completed ? .green : .orange)
                    }
                    .width(44)
                    TableColumn("フォルダ") { e in
                        Text(e.folderPath).lineLimit(1).truncationMode(.head).help(e.folderPath)
                    }
                    .width(min: 160, ideal: 260)
                    TableColumn("確認数") { e in Text("\(e.scannedFiles)").monospacedDigit() }.width(60)
                    TableColumn("重複(組)") { e in Text("\(e.groups)").monospacedDigit() }.width(60)
                    TableColumn("余分") { e in Text("\(e.extraFiles)").monospacedDigit() }.width(50)
                    TableColumn("余分な容量") { e in
                        Text(ByteCountFormatter.string(fromByteCount: e.wastedBytes, countStyle: .file)).monospacedDigit()
                    }
                    .width(80)
                    TableColumn("読めず") { e in Text("\(e.unreadable)").monospacedDigit() }.width(50)
                }
            }
        }
        .confirmationDialog("チェック履歴をすべて消去しますか？", isPresented: $confirmingClear) {
            Button("消去する", role: .destructive) { history.clear() }
        } message: {
            Text("ファイルには影響しません。履歴の記録だけを消去します。")
        }
    }
}
