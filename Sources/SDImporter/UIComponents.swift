import AppKit
import SwiftUI

/// 処理結果の種類（結果カードの色とアイコンに使う）
enum Outcome: Equatable {
    case success
    case warning
    case info
    case cancelled

    var color: Color {
        switch self {
        case .success: return .green
        case .warning: return .orange
        case .info: return .blue
        case .cancelled: return .gray
        }
    }

    var symbol: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        case .cancelled: return "stop.circle.fill"
        }
    }
}

enum Sounds {
    static func start() { NSSound(named: "Pop")?.play() }
    static func finish(_ outcome: Outcome) {
        NSSound(named: outcome == .success ? "Glass" : (outcome == .warning ? "Basso" : "Tink"))?.play()
    }
}

// MARK: - 大きな操作ボタン

/// 開始・キャンセルなどの主要ボタン。横幅いっぱい・大きめ・アイコン付き
struct BigActionButton: View {
    let title: String
    let systemImage: String
    var tint: Color = .accentColor
    var shortcut: KeyboardShortcut?
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.title2.weight(.bold))
                .frame(maxWidth: .infinity, minHeight: 56)
        }
        .buttonStyle(BigButtonStyle(tint: tint, hovering: hovering))
        .onHover { hovering = $0 }
        .keyboardShortcut(shortcut)
    }
}

/// ウィンドウが後ろにあっても色が消えない、大きなボタンの見た目
struct BigButtonStyle: ButtonStyle {
    let tint: Color
    var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return configuration.label
            .foregroundStyle(.white)
            .background(
                shape.fill(LinearGradient(colors: [tint.opacity(0.85), tint], startPoint: .top, endPoint: .bottom))
            )
            .overlay(shape.strokeBorder(.white.opacity(hovering ? 0.35 : 0.15), lineWidth: 1))
            .contentShape(shape)
            .shadow(color: tint.opacity(isEnabled ? (hovering ? 0.55 : 0.3) : 0), radius: hovering ? 14 : 8, y: 4)
            .scaleEffect(configuration.isPressed ? 0.97 : (hovering && isEnabled ? 1.012 : 1))
            .brightness(configuration.isPressed ? -0.08 : 0)
            .saturation(isEnabled ? 1 : 0.2)
            .opacity(isEnabled ? 1 : 0.45)
            .animation(.spring(duration: 0.25), value: hovering)
            .animation(.spring(duration: 0.15), value: configuration.isPressed)
    }
}

/// 色付きの進捗バー（ウィンドウが後ろにあっても色が消えない）
struct ColorProgressBar: View {
    let value: Double
    let total: Double
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            let fraction = total > 0 ? min(max(value / total, 0), 1) : 0
            ZStack(alignment: .leading) {
                Capsule().fill(tint.opacity(0.18))
                Capsule()
                    .fill(LinearGradient(colors: [tint.opacity(0.7), tint], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(geo.size.width * fraction, fraction > 0 ? 10 : 0))
                    .shadow(color: tint.opacity(0.5), radius: 4)
            }
        }
        .frame(height: 10)
        .animation(.easeOut(duration: 0.3), value: value)
    }
}

// MARK: - 進捗カード

/// 処理中に表示する大きな進捗表示。total が nil なら件数不明（くるくる）
struct ProgressCard: View {
    let title: String
    let systemImage: String
    var done: Int = 0
    var total: Int?
    var detail: String = ""
    var tint: Color = .accentColor

    var body: some View {
        HStack(spacing: 18) {
            Image(systemName: systemImage)
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(tint)
                .symbolEffect(.variableColor.iterative.reversing, options: .repeating)
                .frame(width: 56)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title).font(.title3.weight(.semibold))
                    Spacer()
                    if let total, total > 0 {
                        Text("\(Int((Double(done) / Double(total) * 100).rounded()))%")
                            .font(.system(size: 30, weight: .heavy, design: .rounded).monospacedDigit())
                            .foregroundStyle(tint)
                            .contentTransition(.numericText())
                            .animation(.snappy, value: done)
                    }
                }
                if let total, total > 0 {
                    ColorProgressBar(value: Double(done), total: Double(total), tint: tint)
                } else {
                    ProgressView().progressViewStyle(.linear).tint(tint)
                }
                if !detail.isEmpty {
                    Text(detail)
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(tint.opacity(0.35), lineWidth: 1))
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

// MARK: - 結果カード

/// 完了時に表示する、色付き・アイコンが弾む結果表示
struct ResultCard<Extra: View>: View {
    let outcome: Outcome
    let title: String
    var message: String = ""
    @ViewBuilder var extra: () -> Extra

    @State private var bounce = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                Image(systemName: outcome.symbol)
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(.white, outcome.color)
                    .symbolRenderingMode(.palette)
                    .symbolEffect(.bounce.up.byLayer, value: bounce)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.title2.weight(.bold))
                    if !message.isEmpty {
                        Text(message)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            extra()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(outcome.color.opacity(0.13), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(outcome.color.opacity(0.45), lineWidth: 1.5))
        .transition(.scale(scale: 0.85).combined(with: .opacity))
        .onAppear {
            // 表示された直後に2回弾ませる
            bounce += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { bounce += 1 }
        }
    }
}

extension ResultCard where Extra == EmptyView {
    init(outcome: Outcome, title: String, message: String = "") {
        self.init(outcome: outcome, title: title, message: message) { EmptyView() }
    }
}

// MARK: - 紙吹雪

/// trigger が変わるたびに、画面上から紙吹雪を降らせる（クリックは下に通す）
struct ConfettiView: View {
    let trigger: Int

    private struct Piece {
        var x: CGFloat
        var delay: Double
        var speed: CGFloat
        var drift: CGFloat
        var wobble: Double
        var spin: Double
        var size: CGFloat
        var color: Color
        var circle: Bool
    }

    @State private var pieces: [Piece] = []
    @State private var startDate: Date?
    @State private var token = 0

    private static let colors: [Color] = [.red, .orange, .yellow, .green, .mint, .blue, .purple, .pink]
    private static let duration: Double = 3.5

    var body: some View {
        TimelineView(.animation(paused: startDate == nil)) { timeline in
            Canvas { context, size in
                guard let startDate else { return }
                let t = timeline.date.timeIntervalSince(startDate)
                for p in pieces {
                    let local = t - p.delay
                    guard local > 0 else { continue }
                    let y = -20 + p.speed * CGFloat(local) + 220 * CGFloat(local * local)
                    guard y < size.height + 30 else { continue }
                    let x = p.x * size.width + sin(local * p.wobble) * p.drift
                    let fade = min(1, max(0, (Self.duration - t) / 0.8))
                    var c = context
                    c.opacity = fade
                    c.translateBy(x: x, y: y)
                    c.rotate(by: .radians(local * p.spin))
                    let rect = CGRect(x: -p.size / 2, y: -p.size / 4, width: p.size, height: p.circle ? p.size : p.size / 2)
                    c.fill(p.circle ? Path(ellipseIn: rect) : Path(rect), with: .color(p.color))
                }
            }
        }
        .allowsHitTesting(false)
        .onChange(of: trigger) { launch() }
    }

    private func launch() {
        pieces = (0..<180).map { _ in
            Piece(x: .random(in: 0...1), delay: .random(in: 0...0.6), speed: .random(in: 80...260),
                  drift: .random(in: 10...50), wobble: .random(in: 2...6), spin: .random(in: -8...8),
                  size: .random(in: 7...13), color: Self.colors.randomElement()!, circle: Bool.random())
        }
        startDate = Date()
        token += 1
        let current = token
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.duration) {
            guard current == token else { return }
            startDate = nil
            pieces = []
        }
    }
}
