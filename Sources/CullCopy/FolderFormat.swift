import Foundation

/// コピー先のフォルダ名の形式。"yyyy/yyyy年MM月dd日" のように書く
///
/// - yyyy → 2026、yy → 26、MM → 08、dd → 15（大文字・小文字は区別しない）
/// - "/" で区切るとサブフォルダになる。空文字ならフォルダ分けしない
enum FolderFormat {
    static let defaultTemplate = "yyyy/yyyy-MM-dd"

    static let presets: [String] = [
        "yyyy/yyyy-MM-dd",
        "yyyy-MM-dd",
        "yyyy_MM_dd",
        "yyyy/MM/dd",
        "yyyy年MM月dd日",
        "yyyy/yyyy年MM月dd日",
        "yyyy/yyyy-MM",
        "yyyy/MM",
    ]

    /// 長いものから順に照合する
    private static let tokens = ["yyyy", "yy", "mm", "dd"]

    /// day は "yyyy-MM-dd"。保存先フォルダからの相対パスを返す（フォルダ分けしない場合は空文字）
    static func relativePath(template: String, day: String) -> String {
        let parts = day.split(separator: "-").map(String.init)
        guard parts.count == 3 else { return "" }
        let values = ["yyyy": parts[0], "yy": String(parts[0].suffix(2)), "mm": parts[1], "dd": parts[2]]

        var output = ""
        var rest = Substring(template)
        while !rest.isEmpty {
            if let token = tokens.first(where: { rest.lowercased().hasPrefix($0) }) {
                output += values[token]!
                rest = rest.dropFirst(token.count)
            } else {
                output.append(rest.removeFirst())
            }
        }
        return sanitize(output)
    }

    /// ":" を除き、空の階層や "." / ".." を取り除く（保存先の外に出ないように）
    private static func sanitize(_ path: String) -> String {
        path.replacingOccurrences(of: ":", with: "")
            .split(separator: "/")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0 != "." && $0 != ".." }
            .joined(separator: "/")
    }
}
