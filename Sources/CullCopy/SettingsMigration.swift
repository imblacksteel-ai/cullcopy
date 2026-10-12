import Foundation

/// 公開前に Bundle ID を com.ryo.SDImporter から変えたので、古い設定を一度だけ引き継ぐ
enum SettingsMigration {
    private static let oldDomain = "com.ryo.SDImporter"
    private static let keys = ["destination", "folderTemplate", "folderFormat", "separator", "duplicateFolder"]
    private static var done = false

    static func run() {
        guard !done else { return }
        done = true
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: "migratedFromOldBundleID"),
              Bundle.main.bundleIdentifier != oldDomain,
              let old = UserDefaults(suiteName: oldDomain) else { return }
        for key in keys where defaults.object(forKey: key) == nil {
            if let value = old.object(forKey: key) {
                defaults.set(value, forKey: key)
            }
        }
        defaults.set(true, forKey: "migratedFromOldBundleID")
    }
}
