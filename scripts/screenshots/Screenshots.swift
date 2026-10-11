// App Store 用スクリーンショットを作る（scripts/make_screenshots.sh から使う）
// 架空の写真・パス・履歴で画面を描き、背景と見出しを付けて 2880×1800 の PNG にする
import AppKit
import SwiftUI

let outDir = URL(fileURLWithPath: CommandLine.arguments[1])
let lang = CommandLine.arguments[2]
let demoRoot = URL(fileURLWithPath: CommandLine.arguments[3])
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

// MARK: - 見出し

let captions: [String: [String]] = [
    "ja": ["SDカードの写真を、撮影日ごとに自動で整理", "中身まで照合する、安全なコピー", "重複ファイルを見つけて、すっきり", "並べて比較して、残すものを選べる"],
    "en": ["Sort SD card photos by date, automatically", "Safe copies, verified byte by byte", "Find duplicate files in seconds", "Compare side by side, keep what matters"],
    "ko": ["SD 카드 사진을 촬영일별로 자동 정리", "내용까지 대조하는 안전한 복사", "중복 파일을 찾아 깔끔하게", "나란히 비교하고 남길 파일을 선택"],
    "zh-Hans": ["按拍摄日期自动整理 SD 卡照片", "逐字节核对的安全复制", "快速找出重复文件", "并排比较，选择要保留的文件"],
    "zh-Hant": ["依拍攝日期自動整理 SD 卡照片", "逐位元組核對的安全複製", "快速找出重複檔案", "並排比較，選擇要保留的檔案"],
]
let tabTitles: [String: (String, String)] = [
    "ja": ("取り込み", "重複チェック"), "en": ("Import", "Duplicates"), "ko": ("가져오기", "중복 검사"),
    "zh-Hans": ("导入", "重复检查"), "zh-Hant": ("匯入", "重複檢查"),
]

// MARK: - 架空の写真

func makePhoto(seed: Int, to url: URL) throws {
    var rng = SeededRandom(seed: UInt64(seed))
    let w = 1600, h = 1067
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let palettes: [[(CGFloat, CGFloat, CGFloat)]] = [
        [(0.98, 0.62, 0.40), (0.55, 0.36, 0.62), (0.18, 0.16, 0.35)],   // 夕焼け
        [(0.55, 0.80, 0.98), (0.30, 0.55, 0.85), (0.10, 0.25, 0.45)],   // 青空
        [(0.99, 0.85, 0.60), (0.85, 0.50, 0.35), (0.30, 0.20, 0.25)],   // 朝焼け
        [(0.70, 0.90, 0.85), (0.30, 0.60, 0.55), (0.08, 0.25, 0.25)],   // 湖
    ]
    let p = palettes[seed % palettes.count]
    let sky = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                         colors: [CGColor(red: p[0].0, green: p[0].1, blue: p[0].2, alpha: 1),
                                  CGColor(red: p[1].0, green: p[1].1, blue: p[1].2, alpha: 1)] as CFArray,
                         locations: [0, 1])!
    ctx.drawLinearGradient(sky, start: CGPoint(x: 0, y: CGFloat(h) * 0.35), end: CGPoint(x: 0, y: CGFloat(h)), options: [])
    // 太陽
    ctx.setFillColor(CGColor(red: 1, green: 0.95, blue: 0.8, alpha: 0.9))
    let sunX = CGFloat(rng.next(in: 300...1300)), sunY = CGFloat(rng.next(in: 600...850))
    ctx.fillEllipse(in: CGRect(x: sunX, y: sunY, width: 150, height: 150))
    // 山並み（奥から手前へ濃く）
    for layer in 0..<4 {
        let t = CGFloat(layer) / 3
        let r = p[1].0 * (1 - t) + p[2].0 * t, g = p[1].1 * (1 - t) + p[2].1 * t, b = p[1].2 * (1 - t) + p[2].2 * t
        ctx.setFillColor(CGColor(red: r * (1 - t * 0.4), green: g * (1 - t * 0.4), blue: b * (1 - t * 0.4), alpha: 1))
        let base = CGFloat(h) * (0.55 - CGFloat(layer) * 0.11)
        let phase = Double(rng.next(in: 0...100)), freq = Double(rng.next(in: 2...5)) / 1000
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: 0))
        for x in stride(from: 0, through: w, by: 8) {
            let y = base + CGFloat(sin(Double(x) * freq + phase) * 60 + sin(Double(x) * freq * 3.1 + phase) * 25)
            path.addLine(to: CGPoint(x: CGFloat(x), y: y))
        }
        path.addLine(to: CGPoint(x: CGFloat(w), y: 0))
        path.closeSubpath()
        ctx.addPath(path)
        ctx.fillPath()
    }
    let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
    CGImageDestinationFinalize(dest)
}

struct SeededRandom {
    var state: UInt64
    init(seed: UInt64) { state = seed &* 6364136223846793005 &+ 1442695040888963407 }
    mutating func next(in range: ClosedRange<Int>) -> Int {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return range.lowerBound + Int((state >> 33) % UInt64(range.count))
    }
}

// MARK: - 描画と合成

@MainActor
func render<V: View>(_ view: V, size: NSSize) -> NSBitmapImageRep {
    let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height)
        .background(Color(nsColor: .windowBackgroundColor)))
    host.frame = NSRect(origin: .zero, size: size)
    let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
    window.appearance = NSAppearance(named: .aqua)
    window.contentView = host
    window.setFrameOrigin(NSPoint(x: -20000, y: -20000))
    window.orderFrontRegardless()
    host.layoutSubtreeIfNeeded()
    RunLoop.current.run(until: Date().addingTimeInterval(2.5))   // サムネイルの読み込みを待つ
    let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
    host.cacheDisplay(in: host.bounds, to: rep)
    window.orderOut(nil)
    return rep
}

/// 背景・見出し・ウィンドウ枠を付けて 2880×1800 の PNG にする
@MainActor
func compose(_ content: NSBitmapImageRep, caption: String, selectedTab: Int, name: String) throws {
    let W = 2880, H = 1800
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: W, pixelsHigh: H, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: W, height: H)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let canvas = NSRect(x: 0, y: 0, width: W, height: H)

    NSGradient(colors: [NSColor(calibratedRed: 0.10, green: 0.75, blue: 0.85, alpha: 1),
                        NSColor(calibratedRed: 0.15, green: 0.45, blue: 0.95, alpha: 1)])!.draw(in: canvas, angle: -90)

    // 見出し
    let style = NSMutableParagraphStyle()
    style.alignment = .center
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 112, weight: .heavy), .foregroundColor: NSColor.white, .paragraphStyle: style,
    ]
    caption.draw(in: NSRect(x: 80, y: CGFloat(H) - 290, width: CGFloat(W) - 160, height: 180), withAttributes: attrs)

    // ウィンドウ（タイトルバー＋中身）
    let titleBar: CGFloat = 104
    let contentSize = NSSize(width: content.pixelsWide, height: content.pixelsHigh)
    let maxW = CGFloat(W) - 360, maxH = CGFloat(H) - 420 - titleBar
    let scale = min(maxW / contentSize.width, maxH / contentSize.height)
    let winW = contentSize.width * scale, winH = contentSize.height * scale + titleBar
    let win = NSRect(x: (CGFloat(W) - winW) / 2, y: 90, width: winW, height: winH)
    let shape = NSBezierPath(roundedRect: win, xRadius: 28, yRadius: 28)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = 60
    shadow.shadowOffset = NSSize(width: 0, height: -24)
    shadow.set()
    NSColor.windowBackgroundColor.setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    NSColor(calibratedWhite: 0.96, alpha: 1).setFill()
    NSRect(x: win.minX, y: win.maxY - titleBar, width: win.width, height: titleBar).fill()
    // 信号機ボタン
    for (i, color) in [NSColor.systemRed, NSColor.systemYellow, NSColor.systemGreen].enumerated() {
        color.setFill()
        NSBezierPath(ovalIn: NSRect(x: win.minX + 40 + CGFloat(i) * 52, y: win.maxY - titleBar / 2 - 17, width: 34, height: 34)).fill()
    }
    // タブ
    let tabs = tabTitles[lang] ?? tabTitles["en"]!
    let tabFont = NSFont.systemFont(ofSize: 34, weight: .medium)
    let tabW: CGFloat = 300, tabH: CGFloat = 64
    let tabsRect = NSRect(x: win.midX - tabW, y: win.maxY - titleBar / 2 - tabH / 2, width: tabW * 2, height: tabH)
    NSColor(calibratedWhite: 0.88, alpha: 1).setFill()
    NSBezierPath(roundedRect: tabsRect, xRadius: 32, yRadius: 32).fill()
    let selected = NSRect(x: tabsRect.minX + CGFloat(selectedTab) * tabW + 4, y: tabsRect.minY + 4, width: tabW - 8, height: tabH - 8)
    NSColor.white.setFill()
    NSBezierPath(roundedRect: selected, xRadius: 28, yRadius: 28).fill()
    for (i, title) in [tabs.0, tabs.1].enumerated() {
        let tabStyle = NSMutableParagraphStyle()
        tabStyle.alignment = .center
        title.draw(in: NSRect(x: tabsRect.minX + CGFloat(i) * tabW, y: tabsRect.minY + 12, width: tabW, height: 44),
                   withAttributes: [.font: tabFont, .foregroundColor: NSColor(calibratedWhite: 0.15, alpha: 1), .paragraphStyle: tabStyle])
    }
    content.draw(in: NSRect(x: win.minX, y: win.minY, width: winW, height: winH - titleBar))
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.restoreGraphicsState()
    try rep.representation(using: .png, properties: [:])!.write(to: outDir.appendingPathComponent("\(lang)-\(name).png"))
}

// MARK: - 架空のデータを用意して撮影

// アプリ内課金（チップ）の審査用スクリーンショット：チップの画面を 1280×800 で描く
if lang == "tips" {
    MainActor.assumeIsolated {
        let store = TipStore.shared
        store.options = [
            TipOption(id: "small", displayName: "小さなチップ", displayPrice: "¥160"),
            TipOption(id: "medium", displayName: "チップ", displayPrice: "¥480"),
            TipOption(id: "large", displayName: "大きなチップ", displayPrice: "¥1,000"),
        ]
        let view = ZStack {
            Color(nsColor: .windowBackgroundColor)
            TipJarView(store: store)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 16))
                .shadow(radius: 20)
        }
        let rep = render(view, size: NSSize(width: 1280, height: 800))
        try! rep.representation(using: .png, properties: [:])!.write(to: outDir.appendingPathComponent("tip-review.png"))
        print("tips: 審査用 1 枚")
    }
    exit(0)
}

MainActor.assumeIsolated {
    let fm = FileManager.default
    // 重複チェック用の写真（demoRoot は make_screenshots.sh が用意した一時ディスク）
    for item in (try? fm.contentsOfDirectory(at: demoRoot, includingPropertiesForKeys: nil)) ?? [] {
        try? fm.removeItem(at: item)
    }
    let layout: [(String, Int)] = [
        ("2026/2026-08-15/DSC00121.JPG", 1), ("Backup/Summer trip/DSC00121.JPG", 1), ("Export/DSC00121.JPG", 1),
        ("2026/2026-08-16/DSC00188.JPG", 2), ("Backup/Summer trip/DSC00188.JPG", 2),
        ("2026/2026-09-02/DSC00342.JPG", 3), ("Shared/DSC00342 copy.JPG", 3),
        ("2026/2026-09-03/DSC00350.JPG", 4),
    ]
    for (path, seed) in layout {
        let url = demoRoot.appendingPathComponent(path)
        try! fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let first = layout.first(where: { $0.1 == seed && $0.0 != path }).map({ demoRoot.appendingPathComponent($0.0) }),
           fm.fileExists(atPath: first.path) {
            try! fm.copyItem(at: first, to: url)
        } else {
            try! makePhoto(seed: seed, to: url)
        }
    }

    // 架空の履歴
    let historyDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("sdimporter-screenshots-history")
    try! fm.createDirectory(at: historyDir, withIntermediateDirectories: true)
    let now = Date()
    let dest = "/Users/photographer/Pictures/SD Import"
    func entry(_ name: String, _ hoursAgo: Double, _ copied: Int, _ skipped: Int, _ ext: [String: Int],
               _ status: HistoryEntry.Status, _ action: HistoryEntry.SourceAction?) -> HistoryEntry {
        HistoryEntry(date: now.addingTimeInterval(-hoursAgo * 3600), sourceName: name, sourcePath: "/Volumes/" + name,
                     destinationPath: dest, template: "yyyy/yyyy-MM-dd", found: copied + skipped, target: copied, copied: copied,
                     failed: 0, remaining: 0, skipped: skipped, extensions: ext, status: status, deleted: action == .deleted ? copied + skipped : nil,
                     deletionOffered: true, sourceAction: action,
                     sourceActionDate: action == nil ? nil : now.addingTimeInterval(-hoursAgo * 3600 + 300), deleteFailed: nil)
    }
    let history = [
        entry("EOS_DIGITAL", 2, 342, 18, ["CR3": 168, "JPG": 168, "MP4": 6], .completed, .deleted),
        entry("SONY_A7", 26, 512, 0, ["ARW": 500, "MP4": 12], .completed, .kept),
        entry("EOS_DIGITAL", 74, 128, 40, ["CR3": 64, "JPG": 64], .completed, .deleted),
        entry("GOPRO", 170, 46, 0, ["MP4": 40, "JPG": 6], .completed, .kept),
    ]
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    try! encoder.encode(history).write(to: historyDir.appendingPathComponent("history.json"))
    let dupHistory = [
        DuplicateHistoryEntry(date: now.addingTimeInterval(-30 * 3600), folderPath: "/Users/photographer/Pictures/SD Import", status: .completed,
                              scannedFiles: 8_412, groups: 0, extraFiles: 0, wastedBytes: 0, unreadable: 0, trashed: nil),
        DuplicateHistoryEntry(date: now.addingTimeInterval(-200 * 3600), folderPath: demoRoot.path, status: .completed,
                              scannedFiles: 2_960, groups: 12, extraFiles: 15, wastedBytes: 642_000_000, unreadable: 0, trashed: 15),
    ]
    try! encoder.encode(dupHistory).write(to: historyDir.appendingPathComponent("duplicate-history.json"))
    HistoryStore<HistoryEntry>.directoryOverride = historyDir

    let state = AppState.shared
    let card = URL(fileURLWithPath: "/Volumes/EOS_DIGITAL")
    state.volumes = [card]
    state.source = card
    state.destination = URL(fileURLWithPath: dest)
    state.template = "yyyy/yyyy-MM-dd"
    let size = NSSize(width: 1080, height: 660)

    try! compose(render(ContentView(state: state), size: size), caption: captions[lang]![0], selectedTab: 0, name: "1-import")

    state.phase = .copying
    state.total = 360
    state.done = 214
    state.currentFile = "IMG_0214.CR3"
    try! compose(render(ContentView(state: state), size: size), caption: captions[lang]![1], selectedTab: 0, name: "2-copying")

    let dup = DuplicateState()
    dup.folder = demoRoot
    let found = try! DuplicateFinder.find(in: demoRoot) { _ in }
    dup.result = found
    dup.phase = .finished
    dup.outcome = .warning
    let extra = found.groups.reduce(0) { $0 + $1.files.count - 1 }
    let wasted = ByteCountFormatter.string(fromByteCount: found.groups.reduce(Int64(0)) { $0 + $1.wasted }, countStyle: .file)
    dup.resultTitle = String(localized: "\(found.groups.count) 組の重複が見つかりました")
    dup.message = String(localized: "余分なファイル \(extra) 個・余分な容量 \(wasted)（\(found.scannedFiles) ファイルを確認）")
    try! compose(render(DuplicateView(state: dup, importDestination: state.destination), size: size),
                 caption: captions[lang]![2], selectedTab: 1, name: "3-duplicates")

    var index: Int? = 0
    let binding = Binding<Int?>(get: { index }, set: { index = $0 })
    try! compose(render(DuplicateCompareView(state: dup, index: binding, root: demoRoot), size: NSSize(width: 1240, height: 780)),
                 caption: captions[lang]![3], selectedTab: 1, name: "4-compare")

    try? fm.removeItem(at: historyDir)
    print("\(lang): 4 枚")
}
