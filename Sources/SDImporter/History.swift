import Foundation

/// 1回分の取り込みの記録（ファイル名は残さない）
struct HistoryEntry: Codable, Identifiable {
    enum Status: String, Codable {
        case completed
        case partiallyFailed
        case cancelled
        case nothingNew

        var label: String {
            switch self {
            case .completed: return String(localized: "完了")
            case .partiallyFailed: return String(localized: "一部失敗")
            case .cancelled: return String(localized: "中断")
            case .nothingNew: return String(localized: "新規なし")
            }
        }
    }

    var id = UUID()
    var date: Date
    var sourceName: String
    var sourcePath: String
    var destinationPath: String
    var template: String
    /// コピー元で見つかった写真・動画の数（取り込み済みを含む）
    var found: Int
    /// 今回コピーしようとした数（取り込み済みを除く）
    var target: Int
    var copied: Int
    var failed: Int
    /// コピーできずに残った数（失敗＋中断で未処理）
    var remaining: Int
    /// 取り込み済みとしてスキップした数
    var skipped: Int
    /// コピーしようとしたファイルの拡張子ごとの数（例: ["JPG": 120, "ARW": 120]）
    var extensions: [String: Int]
    var status: Status
    /// コピー元から削除した数（削除しなかった場合は nil）
    var deleted: Int?

    // MARK: コピー元の扱い（古い履歴にはないので、すべて省略可能）

    enum SourceAction: String, Codable {
        case deleted
        case kept
    }

    /// 完了後に「コピー元を削除しますか？」を表示したか
    var deletionOffered: Bool?
    /// 「削除する」「残す」のどちらを選んだか（どちらも選ばなかった場合は nil）
    var sourceAction: SourceAction?
    /// 削除または「残す」を選んだ日時
    var sourceActionDate: Date?
    /// 中身が一致しないなどで削除しなかった数
    var deleteFailed: Int?

    /// 履歴の「コピー元」列に出す文言
    var sourceActionLabel: String {
        switch sourceAction {
        case .deleted:
            let failed = deleteFailed ?? 0
            return failed > 0 ? String(localized: "削除 \(deleted ?? 0)・失敗 \(failed)") : String(localized: "削除 \(deleted ?? 0)")
        case .kept:
            return String(localized: "残した")
        case nil:
            return deletionOffered == true ? String(localized: "未選択") : "—"
        }
    }

    var extensionSummary: String {
        extensions.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .map { "\($0.key) \($0.value)" }
            .joined(separator: String(localized: "、"))
    }
}

/// 重複チェック1回分の記録（ファイル名は残さない）
struct DuplicateHistoryEntry: Codable, Identifiable {
    enum Status: String, Codable {
        case completed
        case cancelled

        var label: String {
            switch self {
            case .completed: return String(localized: "完了")
            case .cancelled: return String(localized: "中断")
            }
        }
    }

    var id = UUID()
    var date: Date
    var folderPath: String
    var status: Status
    /// 確認したファイル数
    var scannedFiles: Int
    /// 重複のグループ数
    var groups: Int
    /// 1つずつ残した場合に余分なファイル数
    var extraFiles: Int
    /// 1つずつ残した場合に空く容量（バイト）
    var wastedBytes: Int64
    var unreadable: Int
    /// 比較画面からゴミ箱に入れた数（古い履歴にはないので省略可能）
    var trashed: Int?

    var summary: String {
        switch status {
        case .cancelled:
            return String(localized: "途中で中断")
        case .completed where groups == 0:
            return String(localized: "重複なし（\(scannedFiles) ファイルを確認）")
        case .completed:
            return String(localized: "重複 \(groups) 組・余分なファイル \(extraFiles) 個・余分な容量 \(ByteCountFormatter.string(fromByteCount: wastedBytes, countStyle: .file))")
        }
    }

    /// 同じフォルダかどうかの比較に使う
    static func normalize(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }
}

/// 履歴を ~/Library/Application Support/SDImporter/<fileName> に保存する
@MainActor
final class HistoryStore<Entry: Codable & Identifiable>: ObservableObject {
    @Published private(set) var entries: [Entry] = []

    let fileURL: URL

    init(fileName: String) {
        fileURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SDImporter", isDirectory: true)
            .appendingPathComponent(fileName)
        if let data = try? Data(contentsOf: fileURL),
           let saved = try? decoder.decode([Entry].self, from: data) {
            entries = saved
        }
    }

    func add(_ entry: Entry) {
        entries.insert(entry, at: 0)
        save()
    }

    func update(id: Entry.ID, _ change: (inout Entry) -> Void) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        change(&entries[index])
        save()
    }

    func clear() {
        entries = []
        save()
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoder.encode(entries).write(to: fileURL, options: .atomic)
        } catch {
            NSLog("SDImporter: 履歴の保存に失敗 - %@", error.localizedDescription)
        }
    }

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
