import AVFoundation
import Combine
import SwiftUI
import UIKit

/// Cold-launch intro, matching Android's launch splash: muted intro video, brand card and tap to skip.
/// Calls `onDismiss` once when the video ends or fails, on a tap, or after 8 s.
struct LaunchSplashView: View {
    let language: AppLanguage
    let dismissing: Bool
    let onDismiss: () -> Void

    @StateObject private var playback = SplashPlayback()
    @State private var cardPhase: CardPhase = .hidden

    private enum CardPhase {
        case hidden
        case overshoot
        case settled
    }

    private static let timeout: TimeInterval = 8

    init(language: AppLanguage, dismissing: Bool, onDismiss: @escaping () -> Void) {
        self.language = language
        self.dismissing = dismissing
        self.onDismiss = onDismiss
    }

    var body: some View {
        ZStack {
            Color(hex: "140800")
                .ignoresSafeArea()

            if let player = playback.player {
                SplashVideoView(player: player)
                    .ignoresSafeArea()
            }

            VStack(spacing: 0) {
                LinearGradient(
                    colors: [Color(hex: "08111A").opacity(0.90), Color(hex: "06001A").opacity(0.07)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 220)
                Spacer(minLength: 0)
                LinearGradient(
                    colors: [Color(hex: "06001A").opacity(0.07), Color(hex: "08111A").opacity(0.95)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 260)
            }
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 8) {
                Text("SMART SENSOR BALL")
                    .font(.system(size: 16, weight: .bold))
                    .tracking(1.3)
                    .foregroundStyle(Color(hex: "FFF8E8"))
                Text(language.localized(
                    "智能拳击球训练",
                    "Smart sensor ball Training",
                    fr: "Entraînement Smart sensor ball",
                    th: "การฝึก Smart sensor ball"
                ))
                .font(.system(size: 13))
                .foregroundStyle(Color(hex: "CAA26A"))
            }
            .padding(.horizontal, 26)
            .padding(.top, 42)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            brandCard

            Text(language.localized("轻触跳过", "Tap to skip", fr: "Touchez pour passer", th: "แตะเพื่อข้าม"))
                .font(.system(size: 12))
                .foregroundStyle(Color(hex: "B88A54"))
                .padding(.bottom, 34)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .opacity(dismissing ? 0 : 1)
        .animation(.easeOut(duration: 0.32), value: dismissing)
        .contentShape(Rectangle())
        .onTapGesture(perform: onDismiss)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .onAppear {
            playback.start(onFinished: onDismiss)
            withAnimation(.easeOut(duration: 0.56).delay(0.18)) {
                cardPhase = .overshoot
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.74) {
                withAnimation(.easeInOut(duration: 0.22)) {
                    cardPhase = .settled
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.timeout) {
                onDismiss()
            }
        }
        .onChange(of: dismissing) { isDismissing in
            if isDismissing {
                playback.stop()
            }
        }
        .onDisappear {
            playback.stop()
        }
    }

    /// Android's brand card. Its gradient is written as #FFF6E2FF / #FFD88AFF, which Android parses as #AARRGGBB,
    /// so it renders lavender to purple; the same colors are used here.
    private var brandCard: some View {
        VStack(spacing: 10) {
            Image("glowpeak_logo_mark")
                .resizable()
                .scaledToFit()
                .frame(width: 220)
            Text("GLOWPEAK")
                .font(.system(size: 15, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(Color(hex: "2D1400"))
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 18)
        .background(
            LinearGradient(colors: [Color(hex: "F6E2FF"), Color(hex: "D88AFF")], startPoint: .top, endPoint: .bottom),
            in: RoundedRectangle(cornerRadius: 32)
        )
        .overlay(RoundedRectangle(cornerRadius: 32).stroke(Color(hex: "FBFFFF").opacity(0.91), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.35), radius: 8, y: 4)
        .padding(.horizontal, 24)
        .opacity(cardOpacity)
        .scaleEffect(cardScale)
        .rotation3DEffect(.degrees(cardRotation), axis: (x: 1, y: 0, z: 0))
        .offset(y: cardOffset)
        .animation(.easeOut(duration: 0.36), value: dismissing)
    }

    private var cardOpacity: Double {
        if dismissing { return 0 }
        return cardPhase == .hidden ? 0 : 1
    }

    private var cardScale: CGFloat {
        if dismissing { return 0.86 }
        switch cardPhase {
        case .hidden: return 0.78
        case .overshoot: return 1.04
        case .settled: return 1
        }
    }

    private var cardRotation: Double {
        if dismissing { return -8 }
        return cardPhase == .hidden ? 8 : 0
    }

    private var cardOffset: CGFloat {
        if dismissing { return -24 }
        return cardPhase == .hidden ? 32 : 0
    }
}

/// Owns the muted intro player. It never touches the audio session, so the app's
/// .playback + .mixWithOthers setup keeps the user's music playing.
@MainActor
private final class SplashPlayback: ObservableObject {
    let player: AVPlayer?
    private var observers: [NSObjectProtocol] = []
    private var statusObservation: NSKeyValueObservation?

    init() {
        let url = Bundle.main.url(forResource: "app_launch_intro", withExtension: "mp4", subdirectory: "Video")
            ?? Bundle.main.url(forResource: "app_launch_intro", withExtension: "mp4")
        if let url {
            let player = AVPlayer(playerItem: AVPlayerItem(url: url))
            player.isMuted = true
            player.actionAtItemEnd = .pause
            player.preventsDisplaySleepDuringVideoPlayback = false
            self.player = player
        } else {
            player = nil
        }
    }

    func start(onFinished: @escaping () -> Void) {
        guard let player, let item = player.currentItem else {
            onFinished()
            return
        }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { _ in
            onFinished()
        })
        observers.append(center.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main) { _ in
            onFinished()
        })
        statusObservation = item.observe(\.status, options: [.new]) { observedItem, _ in
            if observedItem.status == .failed {
                DispatchQueue.main.async {
                    onFinished()
                }
            }
        }
        player.play()
    }

    func stop() {
        player?.pause()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        statusObservation = nil
    }
}

/// Aspect-fill video layer without playback controls (SwiftUI's VideoPlayer always shows them).
private struct SplashVideoView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PlayerLayerView, context: Context) {}

    final class PlayerLayerView: UIView {
        override class var layerClass: AnyClass {
            AVPlayerLayer.self
        }

        var playerLayer: AVPlayerLayer {
            // layerClass guarantees the backing layer type.
            layer as! AVPlayerLayer
        }
    }
}
