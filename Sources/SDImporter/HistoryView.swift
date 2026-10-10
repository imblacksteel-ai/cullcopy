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
            } else {
                Table(history.entries) {
                    TableColumn("日時") { e in
                        Text(e.date.formatted(date: .numeric, time: .shortened))
                    }
                    .width(min: 110, ideal: 130)
                    TableColumn("状態") { e in
                        Text(e.status.label).foregroundStyle(color(for: e.status))
                    }
                    .width(60)
                    TableColumn("コピー元") { e in
                        Text(e.sourceName).help(e.sourcePath)
                    }
                    .width(min: 80, ideal: 110)
                    TableColumn("コピー先") { e in
                        Text(e.destinationPath).lineLimit(1).truncationMode(.head).help("\(e.destinationPath)\n形式: \(e.template)")
                    }
                    .width(min: 120, ideal: 200)
                    TableColumn("対象") { e in number(e.target) }.width(44)
                    TableColumn("成功") { e in number(e.copied) }.width(44)
                    TableColumn("残り") { e in
                        number(e.remaining).foregroundStyle(e.remaining > 0 ? .orange : .primary)
                    }
                    .width(44)
                    TableColumn("スキップ") { e in number(e.skipped) }.width(56)
                    TableColumn("削除") { e in
                        if let deleted = e.deleted { number(deleted) } else { Text("—").foregroundStyle(.secondary) }
                    }
                    .width(44)
                    TableColumn("種類") { e in
                        Text(e.extensionSummary.isEmpty ? "—" : e.extensionSummary).help(e.extensionSummary)
                    }
                    .width(min: 100, ideal: 180)
                }
            }

            Text("対象＝今回コピーしようとした数　スキップ＝取り込み済み　残り＝失敗・中断でコピーできなかった数")
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
