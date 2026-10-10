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
            case .completed: return "完了"
            case .partiallyFailed: return "一部失敗"
            case .cancelled: return "中断"
            case .nothingNew: return "新規なし"
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

    var extensionSummary: String {
        extensions.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .map { "\($0.key) \($0.value)" }
            .joined(separator: "、")
    }
}

/// 履歴を ~/Library/Application Support/SDImporter/history.json に保存する
@MainActor
final class HistoryStore: ObservableObject {
    @Published private(set) var entries: [HistoryEntry] = []

    let fileURL: URL

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SDImporter", isDirectory: true)
            .appendingPathComponent("history.json")
        if let data = try? Data(contentsOf: self.fileURL),
           let saved = try? Self.decoder.decode([HistoryEntry].self, from: data) {
            entries = saved
        }
    }

    func add(_ entry: HistoryEntry) {
        entries.insert(entry, at: 0)
        save()
    }

    func update(id: UUID, _ change: (inout HistoryEntry) -> Void) {
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
            try Self.encoder.encode(entries).write(to: fileURL, options: .atomic)
        } catch {
            NSLog("SDImporter: 履歴の保存に失敗 - %@", error.localizedDescription)
        }
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
