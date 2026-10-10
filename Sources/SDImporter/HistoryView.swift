import SwiftUI

struct HistoryView: View {
    @ObservedObject var history: HistoryStore<HistoryEntry>
    @State private var confirmingClear = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("取り込み履歴").font(.headline)
                Spacer()
                Button("履歴ファイルを表示") {
                    NSWorkspace.shared.activateFileViewerSelecting([history.fileURL])
                }
                .disabled(history.entries.isEmpty)
                Button("履歴を消去…") { confirmingClear = true }
                    .disabled(history.entries.isEmpty)
            }
            .controlSize(.small)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)

            if history.entries.isEmpty {
                ContentUnavailableView("履歴はまだありません", systemImage: "clock",
                                       description: Text("コピーを実行すると、ここに記録されます。"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(history.entries) {
                    TableColumn("日時") { (e: HistoryEntry) in
                        Text(e.date.formatted(date: .numeric, time: .shortened))
                    }
                    .width(min: 110, ideal: 120)
                    TableColumn("状態") { (e: HistoryEntry) in
                        Text(e.status.label).foregroundStyle(color(for: e.status))
                    }
                    .width(56)
                    TableColumn("コピー元") { (e: HistoryEntry) in
                        Text(e.sourceName).help(e.sourcePath)
                    }
                    .width(min: 70, ideal: 90)
                    TableColumn("コピー先") { (e: HistoryEntry) in
                        Text(e.destinationPath).lineLimit(1).truncationMode(.head).help("\(e.destinationPath)\n形式: \(e.template)")
                    }
                    .width(min: 80, ideal: 100)
                    Group {
                    TableColumn("対象") { (e: HistoryEntry) in number(e.target) }.width(40)
                    TableColumn("成功") { (e: HistoryEntry) in number(e.copied) }.width(40)
                    TableColumn("残り") { (e: HistoryEntry) in
                        number(e.remaining).foregroundStyle(e.remaining > 0 ? .orange : .primary)
                    }
                    .width(40)
                    TableColumn("スキップ") { (e: HistoryEntry) in number(e.skipped) }.width(50)
                    }
                    Group {
                    TableColumn("元ファイル") { (e: HistoryEntry) in
                        Text(e.sourceActionLabel)
                            .foregroundStyle(sourceActionColor(e))
                            .help(sourceActionHelp(e))
                    }
                    .width(min: 90, ideal: 130)
                    TableColumn("削除/残した") { (e: HistoryEntry) in
                        if let date = e.sourceActionDate {
                            Text(date.formatted(.dateTime.month(.defaultDigits).day().hour().minute()))
                                .help(date.formatted(date: .complete, time: .standard))
                        } else {
                            Text("—").foregroundStyle(.secondary)
                        }
                    }
                    .width(min: 76, ideal: 80)
                    TableColumn("種類") { (e: HistoryEntry) in
                        Text(e.extensionSummary.isEmpty ? "—" : e.extensionSummary).help(e.extensionSummary)
                    }
                    .width(min: 80, ideal: 150)
                    }
                }
            }

            Text("対象＝今回コピーしようとした数　スキップ＝取り込み済み　残り＝失敗・中断でコピーできなかった数　元ファイル＝コピー元を削除したか残したか")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.vertical, 6)
        }
        .confirmationDialog("履歴をすべて消去しますか？", isPresented: $confirmingClear) {
            Button("消去する", role: .destructive) { history.clear() }
        } message: {
            Text("コピーしたファイルは消えません。履歴の記録だけを消去します。")
        }
    }

    private func sourceActionColor(_ e: HistoryEntry) -> Color {
        switch e.sourceAction {
        case .deleted: return (e.deleteFailed ?? 0) > 0 ? .orange : .red
        case .kept: return .primary
        case nil: return .secondary
        }
    }

    private func sourceActionHelp(_ e: HistoryEntry) -> String {
        switch e.sourceAction {
        case .deleted:
            var text = "コピー元から \(e.deleted ?? 0) 件を削除"
            if let failed = e.deleteFailed, failed > 0 { text += "（中身が一致しないなどで削除しなかったもの \(failed) 件）" }
            return text
        case .kept: return "コピー元を削除せずに残しました"
        case nil: return e.deletionOffered == true ? "削除するか選ばないまま次の操作に進みました" : "削除の確認は表示されませんでした"
        }
    }

    private func number(_ n: Int) -> Text {
        Text("\(n)").monospacedDigit()
    }

    private func color(for status: HistoryEntry.Status) -> Color {
        switch status {
        case .completed: return .green
        case .partiallyFailed: return .orange
        case .cancelled: return .orange
        case .nothingNew: return .secondary
        }
    }
}
