import AppKit
import SwiftUI

/// 機能ごとのオリジナルアイコン（取り込み・重複チェック・選んでコピー）。単色の線画で、色は foregroundStyle に従う
enum Feature: Hashable {
    case importer
    case duplicates
    case pick
}

struct FeatureGlyph: View {
    let feature: Feature
    var size: CGFloat = 16

    var body: some View {
        Canvas { context, canvas in
            let s = min(canvas.width, canvas.height)
            let line = max(1.2, s * 0.085)
            let style = StrokeStyle(lineWidth: line, lineCap: .round, lineJoin: .round)
            switch feature {
            case .importer: drawImporter(&context, s, style)
            case .duplicates: drawDuplicates(&context, s, style)
            case .pick: drawPick(&context, s, style)
            }
        }
        .frame(width: size, height: size)
    }

    /// SDカード（右上が欠けた形）＋端子＋下向きの矢印
    private func drawImporter(_ c: inout GraphicsContext, _ s: CGFloat, _ style: StrokeStyle) {
        let l = s * 0.18, r = s * 0.82, t = s * 0.06, b = s * 0.94, notch = s * 0.22, rad = s * 0.08
        var card = Path()
        card.move(to: CGPoint(x: l + rad, y: t))
        card.addLine(to: CGPoint(x: r - notch, y: t))
        card.addLine(to: CGPoint(x: r, y: t + notch))
        card.addLine(to: CGPoint(x: r, y: b - rad))
        card.addQuadCurve(to: CGPoint(x: r - rad, y: b), control: CGPoint(x: r, y: b))
        card.addLine(to: CGPoint(x: l + rad, y: b))
        card.addQuadCurve(to: CGPoint(x: l, y: b - rad), control: CGPoint(x: l, y: b))
        card.addLine(to: CGPoint(x: l, y: t + rad))
        card.addQuadCurve(to: CGPoint(x: l + rad, y: t), control: CGPoint(x: l, y: t))
        card.closeSubpath()
        c.stroke(card, with: .foreground, style: style)
        // 端子
        var pins = Path()
        for i in 0..<3 {
            let x = s * (0.32 + Double(i) * 0.11)
            pins.move(to: CGPoint(x: x, y: s * 0.17))
            pins.addLine(to: CGPoint(x: x, y: s * 0.30))
        }
        c.stroke(pins, with: .foreground, style: style)
        // 下向きの矢印
        var arrow = Path()
        arrow.move(to: CGPoint(x: s * 0.5, y: s * 0.44))
        arrow.addLine(to: CGPoint(x: s * 0.5, y: s * 0.80))
        arrow.move(to: CGPoint(x: s * 0.36, y: s * 0.67))
        arrow.addLine(to: CGPoint(x: s * 0.5, y: s * 0.81))
        arrow.addLine(to: CGPoint(x: s * 0.64, y: s * 0.67))
        c.stroke(arrow, with: .foreground, style: style)
    }

    /// 重なった2枚の写真＋「＝」
    private func drawDuplicates(_ c: inout GraphicsContext, _ s: CGFloat, _ style: StrokeStyle) {
        let back = Path(roundedRect: CGRect(x: s * 0.06, y: s * 0.10, width: s * 0.58, height: s * 0.52), cornerRadius: s * 0.08)
        c.stroke(back, with: .foreground, style: style)
        let frontRect = CGRect(x: s * 0.34, y: s * 0.38, width: s * 0.60, height: s * 0.54)
        // 前の写真は、後ろの線を消してから描く
        c.blendMode = .clear
        c.fill(Path(roundedRect: frontRect.insetBy(dx: -style.lineWidth, dy: -style.lineWidth), cornerRadius: s * 0.1), with: .foreground)
        c.blendMode = .normal
        c.stroke(Path(roundedRect: frontRect, cornerRadius: s * 0.08), with: .foreground, style: style)
        var equal = Path()
        equal.move(to: CGPoint(x: s * 0.50, y: s * 0.58))
        equal.addLine(to: CGPoint(x: s * 0.78, y: s * 0.58))
        equal.move(to: CGPoint(x: s * 0.50, y: s * 0.72))
        equal.addLine(to: CGPoint(x: s * 0.78, y: s * 0.72))
        c.stroke(equal, with: .foreground, style: style)
    }

    /// 写真（山と太陽）＋右下のチェック
    private func drawPick(_ c: inout GraphicsContext, _ s: CGFloat, _ style: StrokeStyle) {
        let photo = Path(roundedRect: CGRect(x: s * 0.06, y: s * 0.12, width: s * 0.72, height: s * 0.62), cornerRadius: s * 0.08)
        c.stroke(photo, with: .foreground, style: style)
        var mountain = Path()
        mountain.move(to: CGPoint(x: s * 0.14, y: s * 0.64))
        mountain.addLine(to: CGPoint(x: s * 0.34, y: s * 0.42))
        mountain.addLine(to: CGPoint(x: s * 0.48, y: s * 0.56))
        mountain.addLine(to: CGPoint(x: s * 0.58, y: s * 0.48))
        mountain.addLine(to: CGPoint(x: s * 0.70, y: s * 0.62))
        c.stroke(mountain, with: .foreground, style: style)
        c.fill(Path(ellipseIn: CGRect(x: s * 0.52, y: s * 0.22, width: s * 0.12, height: s * 0.12)), with: .foreground)
        // チェックの丸（写真の線を消してから）
        let badge = CGRect(x: s * 0.52, y: s * 0.52, width: s * 0.44, height: s * 0.44)
        c.blendMode = .clear
        c.fill(Path(ellipseIn: badge.insetBy(dx: -style.lineWidth, dy: -style.lineWidth)), with: .foreground)
        c.blendMode = .normal
        c.fill(Path(ellipseIn: badge), with: .foreground)
        var check = Path()
        check.move(to: CGPoint(x: badge.minX + badge.width * 0.26, y: badge.midY + badge.height * 0.02))
        check.addLine(to: CGPoint(x: badge.minX + badge.width * 0.44, y: badge.midY + badge.height * 0.20))
        check.addLine(to: CGPoint(x: badge.minX + badge.width * 0.76, y: badge.midY - badge.height * 0.18))
        c.blendMode = .clear
        c.stroke(check, with: .foreground, style: StrokeStyle(lineWidth: style.lineWidth * 1.1, lineCap: .round, lineJoin: .round))
        c.blendMode = .normal
    }
}

// MARK: - メニューバー用の画像

/// メニューバーの表示を1枚の画像にする（メニューバーは文字に埋め込んだアイコンを描かないため）。
/// テンプレート画像なので、メニューバーの明るさに合わせて自動で白黒が切り替わる
@MainActor
enum MenuBarImage {
    struct Segment {
        let feature: Feature
        let text: String
    }

    static func make(_ segments: [Segment]) -> NSImage {
        let view = HStack(spacing: 12) {
            if segments.isEmpty {
                FeatureGlyph(feature: .importer, size: 16)
            }
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                HStack(spacing: 4) {
                    FeatureGlyph(feature: segment.feature, size: 16)
                    Text(segment.text)
                        .font(.system(size: 13, weight: .medium).monospacedDigit())
                        .fixedSize()
                }
            }
        }
        .foregroundStyle(.black)
        .padding(.vertical, 1)

        let renderer = ImageRenderer(content: view)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        let image = renderer.nsImage ?? NSImage(systemSymbolName: "sdcard", accessibilityDescription: nil)!
        image.isTemplate = true
        return image
    }
}
