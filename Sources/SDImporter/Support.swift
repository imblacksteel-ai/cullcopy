// 「開発を支援する」（アプリ内課金のチップ）。App Store 版だけの機能で、GitHub 版はチップなしの完全無料
#if APPSTORE
import StoreKit
import SwiftUI

enum Support {
    @MainActor
    static func open() {
        TipStore.shared.isPresented = true
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// チップの選択肢（表示名と価格）。審査用スクリーンショットでは product なしで表示する
struct TipOption: Identifiable {
    let id: String
    let displayName: String
    let displayPrice: String
    var product: Product?
}

/// チップ（消耗型のアプリ内課金）。商品は App Store Connect に登録する（docs/appstore.md）
@MainActor
final class TipStore: ObservableObject {
    static let shared = TipStore()
    static let productIDs = [
        "com.imblacksteelai.sdimporter.tip.small",
        "com.imblacksteelai.sdimporter.tip.medium",
        "com.imblacksteelai.sdimporter.tip.large",
    ]

    enum State: Equatable {
        case idle
        case purchasing
        case thanks
        case failed(String)
    }

    @Published var isPresented = false
    @Published var options: [TipOption] = []
    @Published var loading = false
    @Published var state: State = .idle
    @Published var celebration = 0

    private var updates: Task<Void, Never>?

    private init() {
        // ほかの端末での購入や、承認待ちだった購入の完了を受け取って片付ける
        updates = Task {
            for await result in Transaction.updates {
                if case let .verified(transaction) = result {
                    await transaction.finish()
                }
            }
        }
    }

    func load() async {
        guard options.isEmpty else { return }
        loading = true
        let products = ((try? await Product.products(for: Self.productIDs)) ?? []).sorted { $0.price < $1.price }
        options = products.map { TipOption(id: $0.id, displayName: $0.displayName, displayPrice: $0.displayPrice, product: $0) }
        loading = false
    }

    func buy(_ option: TipOption) async {
        guard let product = option.product else { return }
        state = .purchasing
        do {
            switch try await product.purchase() {
            case let .success(.verified(transaction)):
                await transaction.finish()
                state = .thanks
                celebration += 1
                Sounds.finish(.success)
            case .success(.unverified):
                state = .failed(String(localized: "購入を確認できませんでした。"))
            case .pending:
                state = .idle   // 承認待ち（ファミリー共有の承認など）。完了は Transaction.updates で受け取る
            case .userCancelled:
                state = .idle
            @unknown default:
                state = .idle
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

/// チップを選ぶ画面
struct TipJarView: View {
    @ObservedObject var store: TipStore
    @Environment(\.dismiss) private var dismiss

    private let icons = ["cup.and.saucer.fill", "birthday.cake.fill", "gift.fill"]
    private let tints: [Color] = [.orange, .pink, .purple]

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: store.state == .thanks ? "heart.circle.fill" : "heart.fill")
                .font(.system(size: 48))
                .foregroundStyle(.pink)
                .symbolEffect(.bounce, value: store.celebration)

            if store.state == .thanks {
                Text("ありがとうございます！").font(.title.weight(.bold))
                Text("いただいたチップは、これからの開発に使わせていただきます。")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            } else {
                Text("開発を支援する").font(.title.weight(.bold))
                Text("CullCopy は無料で使えます。気に入っていただけたら、チップで応援してもらえるとうれしいです。")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if store.loading {
                    ProgressView().padding()
                } else if store.options.isEmpty {
                    Text("いまはチップを読み込めません。ネットワークを確認して、あとでもう一度お試しください。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                } else {
                    HStack(spacing: 14) {
                        ForEach(Array(store.options.enumerated()), id: \.element.id) { index, option in
                            Button {
                                Task { await store.buy(option) }
                            } label: {
                                VStack(spacing: 6) {
                                    Image(systemName: icons[min(index, icons.count - 1)]).font(.title)
                                    Text(option.displayName).font(.headline).lineLimit(1)
                                    Text(option.displayPrice).font(.title3.weight(.heavy).monospacedDigit())
                                }
                                .frame(width: 130, height: 110)
                            }
                            .buttonStyle(BigButtonStyle(tint: tints[min(index, tints.count - 1)]))
                            .disabled(store.state == .purchasing)
                        }
                    }
                }

                if case let .failed(message) = store.state {
                    Text(message).font(.callout).foregroundStyle(.red)
                }
            }

            Button(store.state == .thanks ? "閉じる" : "あとで") {
                if store.state == .thanks { store.state = .idle }
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
            .controlSize(.large)
        }
        .padding(28)
        .frame(width: 520)
        .overlay { ConfettiView(trigger: store.celebration) }
        .task { await store.load() }
    }
}

#endif
