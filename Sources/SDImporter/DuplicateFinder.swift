import CryptoKit
import Foundation

/// 中身が完全に同じファイルのまとまり
struct DuplicateGroup: Identifiable {
    let id = UUID()
    let size: Int64
    let files: [URL]

    /// 1つだけ残した場合に空く容量
    var wasted: Int64 { size * Int64(files.count - 1) }
}

struct DuplicateScanResult {
    var groups: [DuplicateGroup] = []
    /// 調べたファイル数
    var scannedFiles = 0
    /// 読めなかったファイル数（権限がないなど）
    var unreadable = 0
}

/// 指定フォルダ内の、中身が完全に同じファイルを探す
///
/// サイズで候補を絞り → 先頭 64KB のハッシュで絞り → ファイル全体の SHA-256 で確定する
enum DuplicateFinder {
    enum Stage {
        case listing
        case comparing
    }

    struct Progress {
        var stage: Stage
        var scannedFiles = 0
        /// 中身を比較するファイルの数と、そのうち処理済みの数
        var candidates = 0
        var compared = 0
    }

    private static let headSize = 64 * 1024
    private static let chunkSize = 8 * 1024 * 1024

    /// Task がキャンセルされたら CancellationError を投げる
    static func find(in root: URL, progress: @escaping (Progress) -> Void) throws -> DuplicateScanResult {
        var result = DuplicateScanResult()

        // 1. ファイルを列挙してサイズで分ける
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return result }

        var bySize: [Int64: [URL]] = [:]
        var status = Progress(stage: .listing)
        while let url = enumerator.nextObject() as? URL {
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
            result.scannedFiles += 1
            if let size = values.fileSize, size > 0 {
                bySize[Int64(size), default: []].append(url)
            }
            if result.scannedFiles % 500 == 0 {
                try Task.checkCancellation()
                status.scannedFiles = result.scannedFiles
                progress(status)
            }
        }

        let sizeGroups = bySize.filter { $0.value.count > 1 }
        status = Progress(stage: .comparing, scannedFiles: result.scannedFiles,
                          candidates: sizeGroups.values.reduce(0) { $0 + $1.count })
        progress(status)

        // 2. 先頭 64KB で絞り、3. 残ったものはファイル全体で比べる
        for (size, files) in sizeGroups {
            var byHead: [Data: [URL]] = [:]
            for file in files {
                try Task.checkCancellation()
                if let head = try? hash(of: file, limit: headSize) {
                    byHead[head, default: []].append(file)
                } else {
                    result.unreadable += 1
                }
                if size <= headSize {
                    status.compared += 1
                    progress(status)
                }
            }

            for headGroup in byHead.values where headGroup.count > 1 {
                if size <= headSize {
                    // 先頭 64KB がファイル全体なので、これで確定
                    result.groups.append(DuplicateGroup(size: size, files: headGroup.sorted { $0.path < $1.path }))
                    continue
                }
                var byFull: [Data: [URL]] = [:]
                for file in headGroup {
                    try Task.checkCancellation()
                    if let full = try? hash(of: file, limit: nil) {
                        byFull[full, default: []].append(file)
                    } else {
                        result.unreadable += 1
                    }
                    status.compared += 1
                    progress(status)
                }
                for group in byFull.values where group.count > 1 {
                    result.groups.append(DuplicateGroup(size: size, files: group.sorted { $0.path < $1.path }))
                }
            }

            if size > headSize {
                // 先頭で外れたファイルの分も処理済みに数える
                let fullyCompared = byHead.values.filter { $0.count > 1 }.reduce(0) { $0 + $1.count }
                status.compared += files.count - fullyCompared
                progress(status)
            }
        }

        result.groups.sort { $0.wasted != $1.wasted ? $0.wasted > $1.wasted : $0.files[0].path < $1.files[0].path }
        return result
    }

    /// limit を指定すると先頭 limit バイトだけのハッシュ
    private static func hash(of url: URL, limit: Int?) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        var remaining = limit ?? Int.max
        while remaining > 0 {
            if limit == nil { try Task.checkCancellation() }
            guard let chunk = try handle.read(upToCount: min(chunkSize, remaining)), !chunk.isEmpty else { break }
            hasher.update(data: chunk)
            remaining -= chunk.count
        }
        return Data(hasher.finalize())
    }
}
