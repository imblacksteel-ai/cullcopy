import Foundation

/// コピー先のフォルダ分けの形式
enum FolderFormat: String, CaseIterable, Identifiable {
    case yearThenDay = "yyyy/yyyy-MM-dd"
    case day = "yyyy-MM-dd"
    case yearMonthDay = "yyyy/MM/dd"
    case yearThenMonth = "yyyy/yyyy-MM"
    case yearMonth = "yyyy/MM"
    case compactDay = "yyyyMMdd"
    case none = "none"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .yearThenDay: return "年 / 年-月-日"
        case .day: return "年-月-日"
        case .yearMonthDay: return "年 / 月 / 日"
        case .yearThenMonth: return "年 / 年-月"
        case .yearMonth: return "年 / 月"
        case .compactDay: return "年月日（8桁）"
        case .none: return "分けない"
        }
    }

    /// day は "yyyy-MM-dd"。保存先フォルダからの相対パスを返す（分けない場合は空文字）
    func relativePath(day: String) -> String {
        let parts = day.split(separator: "-").map(String.init)
        guard parts.count == 3 else { return "" }
        let (y, m, d) = (parts[0], parts[1], parts[2])
        switch self {
        case .yearThenDay: return "\(y)/\(y)-\(m)-\(d)"
        case .day: return "\(y)-\(m)-\(d)"
        case .yearMonthDay: return "\(y)/\(m)/\(d)"
        case .yearThenMonth: return "\(y)/\(y)-\(m)"
        case .yearMonth: return "\(y)/\(m)"
        case .compactDay: return "\(y)\(m)\(d)"
        case .none: return ""
        }
    }
}
