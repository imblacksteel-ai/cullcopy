import Foundation

/// コピー先のフォルダ分けの形式
enum FolderFormat: String, CaseIterable, Identifiable {
    case yearThenDay = "yyyy/yyyy-MM-dd"
    case day = "yyyy-MM-dd"
    case yearMonthDay = "yyyy/MM/dd"
    case yearThenMonth = "yyyy/yyyy-MM"
    case yearMonth = "yyyy/MM"
    case none = "none"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .yearThenDay: return "年 / 年-月-日"
        case .day: return "年-月-日"
        case .yearMonthDay: return "年 / 月 / 日"
        case .yearThenMonth: return "年 / 年-月"
        case .yearMonth: return "年 / 月"
        case .none: return "分けない"
        }
    }

    /// 年月日の間の区切り文字を使う形式か
    var usesSeparator: Bool {
        switch self {
        case .yearThenDay, .day, .yearThenMonth: return true
        case .yearMonthDay, .yearMonth, .none: return false
        }
    }

    /// フォルダ名に使えない "/" と ":" を取り除く
    static func sanitize(separator: String) -> String {
        separator.filter { $0 != "/" && $0 != ":" }
    }

    /// day は "yyyy-MM-dd"。保存先フォルダからの相対パスを返す（分けない場合は空文字）
    func relativePath(day: String, separator: String = "-") -> String {
        let parts = day.split(separator: "-").map(String.init)
        guard parts.count == 3 else { return "" }
        let (y, m, d) = (parts[0], parts[1], parts[2])
        let s = Self.sanitize(separator: separator)
        switch self {
        case .yearThenDay: return "\(y)/\(y)\(s)\(m)\(s)\(d)"
        case .day: return "\(y)\(s)\(m)\(s)\(d)"
        case .yearMonthDay: return "\(y)/\(m)/\(d)"
        case .yearThenMonth: return "\(y)/\(y)\(s)\(m)"
        case .yearMonth: return "\(y)/\(m)"
        case .none: return ""
        }
    }
}
