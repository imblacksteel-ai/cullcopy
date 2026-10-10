import AppKit

/// App Store 版（サンドボックス）で、利用者が選んだフォルダや SD カードに次回以降も入れるようにする。
/// 選んだ場所をセキュリティスコープ付きブックマークとして保存し、使う前にアクセスを開始する。
/// サンドボックスでない GitHub 版では、何もしなくても読み書きできるので素通りする
@MainActor
final class FolderAccess {
    static let shared = FolderAccess()

    static var isSandboxed: Bool {
        ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
    }

    /// 本当のホームフォルダ（サンドボックスでは homeDirectoryForCurrentUser がコンテナを指すため）
    static var realHome: URL {
        if let dir = getpwuid(getuid())?.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir), isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    private let defaultsKey = "folderBookmarks"
    /// 保存したブックマーク（キーは選んだときのパス）
    private var bookmarks: [String: Data]
    /// アクセスを開始済みの場所（アプリを終了するまで開いたままにする）
    private var started: [String: URL] = [:]

    private init() {
        bookmarks = UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: Data] ?? [:]
    }

    /// 利用者がパネルで選んだ場所を覚えて、すぐにアクセスを開始する
    func remember(_ url: URL) {
        guard Self.isSandboxed else { return }
        if let data = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
            bookmarks[url.standardizedFileURL.path] = data
            UserDefaults.standard.set(bookmarks, forKey: defaultsKey)
        }
        if url.startAccessingSecurityScopedResource() {
            started[url.standardizedFileURL.path] = url
        }
    }

    /// その場所（またはそれを含むフォルダ）のブックマークがあれば、アクセスを開始する
    func access(_ url: URL) {
        guard Self.isSandboxed else { return }
        let path = url.standardizedFileURL.path
        if started.keys.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) { return }
        for (key, data) in bookmarks {
            var stale = false
            guard let resolved = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil,
                                          bookmarkDataIsStale: &stale) else { continue }
            let resolvedPath = resolved.standardizedFileURL.path
            guard path == resolvedPath || path.hasPrefix(resolvedPath + "/") else { continue }
            if resolved.startAccessingSecurityScopedResource() {
                started[resolvedPath] = resolved
                if stale || key != resolvedPath, let fresh = try? resolved.bookmarkData(options: .withSecurityScope,
                                                                                        includingResourceValuesForKeys: nil, relativeTo: nil) {
                    bookmarks[key] = nil
                    bookmarks[resolvedPath] = fresh
                    UserDefaults.standard.set(bookmarks, forKey: defaultsKey)
                }
                return
            }
        }
    }

    /// 中を読めるか（サンドボックスで許可がない場所は読めない）
    func canRead(_ url: URL) -> Bool {
        access(url)
        return (try? FileManager.default.contentsOfDirectory(atPath: url.path)) != nil
    }

    /// その場所へのアクセスを許可してもらう（フォルダ選択パネルをその場所で開く）。選ばれた場所を返す
    func requestAccess(to url: URL, message: String) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = false
        panel.directoryURL = url
        panel.message = message
        panel.prompt = String(localized: "許可")
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let chosen = panel.url else { return nil }
        remember(chosen)
        return chosen
    }
}
