import AVFoundation
import CryptoKit
import Foundation
import ImageIO

/// 取り込み対象の1ファイル
struct ImportItem {
    let source: URL
    let destination: URL
    let size: Int64
}

struct ImportPlan {
    var items: [ImportItem] = []
    /// 保存先に同名・同サイズがあり、取り込み済みとみなしたファイル（destination は既存のファイル）
    var skippedItems: [ImportItem] = []
    var skipped: Int { skippedItems.count }
}

struct ImportResult {
    var copiedItems: [ImportItem] = []
    var copied: Int { copiedItems.count }
    var failed: [(URL, Error)] = []
    var cancelled = false
}

enum Importer {
    static let photoExtensions: Set<String> = [
        "jpg", "jpeg", "heic", "heif", "png", "tif", "tiff", "dng",
        "arw", "cr2", "cr3", "crw", "nef", "nrw", "orf", "raf", "rw2",
        "pef", "srw", "raw", "3fr", "iiq", "x3f", "gpr",
    ]
    static let videoExtensions: Set<String> = [
        "mp4", "mov", "m4v", "avi", "mts", "m2ts", "3gp", "mxf", "insv", "lrv",
    ]

    /// カメラのメモリーカードかどうか（DCIM / Sony・AVCHD の動画フォルダがあるか）
    static func isCameraCard(_ volume: URL) -> Bool {
        let fm = FileManager.default
        return ["DCIM", "PRIVATE/M4ROOT", "PRIVATE/AVCHD", "AVCHD"].contains {
            fm.fileExists(atPath: volume.appendingPathComponent($0).path)
        }
    }

    /// カード内を走査し、まだ保存先に無いファイルの取り込み計画を作る
    static func plan(volume: URL, destinationRoot: URL, template: String) async -> ImportPlan {
        let sources = mediaFiles(in: volume)

        var plan = ImportPlan()
        var planned = Set<String>()
        for source in sources {
            if Task.isCancelled { break }
            let size = Int64((try? source.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
            let day = await captureDay(of: source)
            let folder = destinationRoot.appendingPathComponent(FolderFormat.relativePath(template: template, day: day), isDirectory: true)
            switch resolveDestination(for: source, in: folder, size: size, planned: planned) {
            case let .existing(dest):
                plan.skippedItems.append(ImportItem(source: source, destination: dest, size: size))
            case let .new(dest):
                planned.insert(dest.path)
                plan.items.append(ImportItem(source: source, destination: dest, size: size))
            }
        }
        return plan
    }

    /// カード内の写真・動画ファイルを列挙する
    static func mediaFiles(in volume: URL) -> [URL] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .creationDateKey, .contentModificationDateKey]
        guard let enumerator = FileManager.default.enumerator(at: volume, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else {
            return []
        }
        var sources: [URL] = []
        for case let url as URL in enumerator {
            let ext = url.pathExtension.lowercased()
            guard photoExtensions.contains(ext) || videoExtensions.contains(ext) else { continue }
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
            sources.append(url)
        }
        return sources.sorted { $0.path < $1.path }
    }

    static let partSuffix = ".sdimport-part"

    /// 計画どおりにコピーする。一時ファイルにコピー → ディスクへ書き込み → 中身（SHA-256）を照合 → 本来の名前にリネーム
    /// Task がキャンセルされたら、その時点で中断する（コピー済みのファイルは残す）
    static func run(_ items: [ImportItem], progress: @escaping (Int, ImportItem) -> Void) -> ImportResult {
        let fm = FileManager.default
        var result = ImportResult()
        removeLeftoverParts(in: Set(items.map { $0.destination.deletingLastPathComponent() }))
        for (index, item) in items.enumerated() {
            if Task.isCancelled {
                result.cancelled = true
                break
            }
            progress(index, item)
            let temp = item.destination.deletingLastPathComponent()
                .appendingPathComponent(".\(item.destination.lastPathComponent)\(partSuffix)")
            do {
                try fm.createDirectory(at: item.destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? fm.removeItem(at: temp)
                try copyVerified(from: item.source, to: temp, expectedSize: item.size)
                try fm.moveItem(at: temp, to: item.destination)
                result.copiedItems.append(item)
            } catch is CancellationError {
                try? fm.removeItem(at: temp)
                result.cancelled = true
                break
            } catch {
                try? fm.removeItem(at: temp)
                result.failed.append((item.source, error))
            }
        }
        return result
    }

    /// 読みながら SHA-256 を計算してコピーし、ディスクへ確実に書き込んでから、書いたファイルを読み直して照合する。
    /// 作成日・変更日はコピー元に合わせる
    private static func copyVerified(from source: URL, to temp: URL, expectedSize: Int64) throws {
        let fm = FileManager.default
        guard fm.createFile(atPath: temp.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: temp.path])
        }
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        let output = try FileHandle(forWritingTo: temp)

        var hasher = SHA256()
        var written: Int64 = 0
        do {
            while true {
                if Task.isCancelled { throw CancellationError() }
                guard let chunk = try input.read(upToCount: chunkSize), !chunk.isEmpty else { break }
                try output.write(contentsOf: chunk)
                hasher.update(data: chunk)
                written += Int64(chunk.count)
            }
            // キャッシュではなくディスク本体まで書き込ませる（停電・強制終了への備え）
            if fcntl(output.fileDescriptor, F_FULLFSYNC) == -1 {
                try output.synchronize()
            }
            try output.close()
        } catch {
            try? output.close()
            throw error
        }

        guard written == expectedSize else {
            throw ImportError.sizeMismatch(expected: expectedSize, actual: written)
        }
        guard try sha256(of: temp) == hasher.finalize() else {
            throw ImportError.contentMismatch
        }

        let attrs = try fm.attributesOfItem(atPath: source.path)
        var dates: [FileAttributeKey: Any] = [:]
        dates[.creationDate] = attrs[.creationDate]
        dates[.modificationDate] = attrs[.modificationDate]
        try? fm.setAttributes(dates, ofItemAtPath: temp.path)
    }

    private static let chunkSize = 8 * 1024 * 1024

    static func sha256(of url: URL) throws -> SHA256.Digest {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: chunkSize), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize()
    }

    /// 前回アプリが途中で止まったときに残った一時ファイル（.〜.sdimport-part）を消す
    static func removeLeftoverParts(in folders: Set<URL>) {
        let fm = FileManager.default
        for folder in folders {
            guard let names = try? fm.contentsOfDirectory(atPath: folder.path) else { continue }
            for name in names where name.hasPrefix(".") && name.hasSuffix(partSuffix) {
                try? fm.removeItem(at: folder.appendingPathComponent(name))
            }
        }
    }

    // MARK: - コピー元の削除

    /// コピー先に同じ中身（サイズと SHA-256）で存在することを確かめてから、コピー元のファイルを完全に削除する。
    /// removeEmptyFolders が true なら、空になったフォルダ（root 自身を含む）も削除する
    static func deleteSources(_ items: [ImportItem], root: URL, removeEmptyFolders: Bool) -> (deleted: Int, failed: [(URL, Error)]) {
        let fm = FileManager.default
        var deleted = 0
        var failed: [(URL, Error)] = []
        for item in items {
            do {
                let destSize = (try fm.attributesOfItem(atPath: item.destination.path)[.size] as? NSNumber)?.int64Value ?? -1
                let sourceSize = (try fm.attributesOfItem(atPath: item.source.path)[.size] as? NSNumber)?.int64Value ?? -1
                guard destSize == item.size, sourceSize == item.size else {
                    throw ImportError.sizeMismatch(expected: item.size, actual: destSize)
                }
                guard try sha256(of: item.source) == sha256(of: item.destination) else {
                    throw ImportError.contentMismatch
                }
                try fm.removeItem(at: item.source)
                deleted += 1
            } catch {
                failed.append((item.source, error))
            }
        }
        if removeEmptyFolders {
            removeEmptyDirectories(in: root)
        }
        return (deleted, failed)
    }

    /// 空のフォルダを下から順に削除する（.DS_Store などの隠しファイルだけなら空とみなす）
    @discardableResult
    private static func removeEmptyDirectories(in dir: URL) -> Bool {
        let fm = FileManager.default
        guard let children = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey]) else { return false }
        var empty = true
        for child in children {
            let isDir = (try? child.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            if child.lastPathComponent.hasPrefix(".") && !isDir { continue }
            if !(isDir && removeEmptyDirectories(in: child)) { empty = false }
        }
        guard empty else { return false }
        return (try? fm.removeItem(at: dir)) != nil
    }

    // MARK: - 保存先の決定

    /// 同名ファイルがあれば: 同サイズなら取り込み済み、違えば "-1", "-2"… を付ける
    private enum Resolution {
        case new(URL)
        case existing(URL)
    }

    private static func resolveDestination(for source: URL, in folder: URL, size: Int64, planned: Set<String>) -> Resolution {
        let fm = FileManager.default
        let base = source.deletingPathExtension().lastPathComponent
        let ext = source.pathExtension
        var n = 0
        while true {
            let name = n == 0 ? source.lastPathComponent : "\(base)-\(n).\(ext)"
            let candidate = folder.appendingPathComponent(name)
            if planned.contains(candidate.path) {
                n += 1
                continue
            }
            if let attrs = try? fm.attributesOfItem(atPath: candidate.path) {
                if (attrs[.size] as? NSNumber)?.int64Value == size { return .existing(candidate) }
                n += 1
                continue
            }
            return .new(candidate)
        }
    }

    // MARK: - 撮影日の取得

    /// "yyyy-MM-dd" を返す。EXIF → 動画メタデータ → ファイル日付の順に試す
    static func captureDay(of url: URL) async -> String {
        let ext = url.pathExtension.lowercased()
        if photoExtensions.contains(ext), let day = exifDay(of: url) {
            return day
        }
        if videoExtensions.contains(ext), let date = await videoCreationDate(of: url) {
            return dayFormatter.string(from: date)
        }
        let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        return dayFormatter.string(from: values?.creationDate ?? values?.contentModificationDate ?? Date())
    }

    private static func exifDay(of url: URL) -> String? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
        else { return nil }
        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        let raw = (exif?[kCGImagePropertyExifDateTimeOriginal] ?? exif?[kCGImagePropertyExifDateTimeDigitized]
            ?? tiff?[kCGImagePropertyTIFFDateTime]) as? String
        // EXIF の日付は "yyyy:MM:dd HH:mm:ss"（タイムゾーンなし）なので、日付部分をそのまま使う
        guard let raw, raw.count >= 10 else { return nil }
        let day = raw.prefix(10).replacingOccurrences(of: ":", with: "-")
        return day.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil && !day.hasPrefix("0000") ? day : nil
    }

    private static func videoCreationDate(of url: URL) async -> Date? {
        let asset = AVURLAsset(url: url)
        guard let item = try? await asset.load(.creationDate) else { return nil }
        return try? await item.load(.dateValue)
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}

enum ImportError: LocalizedError {
    case sizeMismatch(expected: Int64, actual: Int64)
    case contentMismatch

    var errorDescription: String? {
        switch self {
        case let .sizeMismatch(expected, actual):
            return String(localized: "コピー後のサイズが一致しません（元: \(expected) / コピー: \(actual)）")
        case .contentMismatch:
            return String(localized: "コピー元とコピー先の中身が一致しません")
        }
    }
}
