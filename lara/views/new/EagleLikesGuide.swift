import SwiftUI

/// A short guide shown once inside Eagle (after the welcome): how likes work and what the people
/// counter in the header means. Skip closes it at any step; it is not shown again either way.
struct EagleLikesGuide: View {
    static let seenKey = "eagle.guide.likesOnline.seen"

    let onClose: () -> Void

    @State private var step = 0
    @State private var appeared = false
    @State private var demoLiked = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let lastStep = 1

    var body: some View {
        ZStack {
            Color.black.opacity(appeared ? 0.62 : 0)
                .ignoresSafeArea()
                .accessibilityHidden(true)

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button(LaraL10n.text(en: "Skip", es: "Saltar"), action: close)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(.horizontal, 14)
                        .frame(height: 34)
                        .background(.ultraThinMaterial, in: Capsule())
                        .environment(\.colorScheme, .dark)
                }
                .padding(.horizontal, 20)

                Spacer()

                card
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 24)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.3)) { appeared = true }
            playLikeDemo()
        }
    }

    private var card: some View {
        VStack(spacing: 20) {
            ZStack {
                if step == 0 {
                    likesDemo.transition(.opacity)
                } else {
                    onlineDemo.transition(.opacity)
                }
            }
            .frame(height: 190)
            .frame(maxWidth: .infinity)
            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 20, style: .continuous))

            VStack(spacing: 8) {
                Text(step == 0
                     ? LaraL10n.text(en: "Like what you love", es: "Dale like a lo que te guste")
                     : LaraL10n.text(en: "People on Eagle now", es: "Gente usando Eagle ahora"))
                    .font(.title3.weight(.bold))
                    .multilineTextAlignment(.center)
                Text(step == 0
                     ? LaraL10n.text(
                        en: "Tap the heart on any wallpaper, passcode, dock or island. The most liked come first, and number one wears the HOT tag.",
                        es: "Toca el corazón en cualquier fondo, passcode, dock o isla. Los que más likes tienen salen primero, y el número uno lleva la etiqueta HOT.")
                     : LaraL10n.text(
                        en: "At the top, under Settings, you see how many people have Eagle open. Red when fewer than 5, green from 5.",
                        es: "Arriba, debajo de Ajustes, ves cuántas personas tienen Eagle abierto. En rojo si son menos de 5, en verde desde 5."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .id(step)
            .transition(.opacity)

            HStack(spacing: 6) {
                ForEach(0...lastStep, id: \.self) { index in
                    Capsule()
                        .fill(Color.white.opacity(index == step ? 0.9 : 0.25))
                        .frame(width: index == step ? 18 : 6, height: 6)
                }
            }
            .animation(.easeOut(duration: 0.25), value: step)
            .accessibilityHidden(true)

            Button(action: next) {
                Text(step == lastStep
                     ? LaraL10n.text(en: "Got it", es: "Entendido")
                     : LaraL10n.text(en: "Next", es: "Siguiente"))
            }
            .buttonStyle(EagleApplyButtonStyle())
        }
        .padding(20)
        .background(Color(white: 0.08), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        }
        .environment(\.colorScheme, .dark)
    }

    /// A wallpaper in a phone with the HOT tag and a heart that fills by itself (and can be tapped).
    private var likesDemo: some View {
        let preview = "https://raw.githubusercontent.com/leonardob8777-bit/Eagle-Gallery/main/previews/wallpapers/hora-dorada.png"
        return EagleDeviceFrame {
            LaraRemoteMediaPreview(url: URL(string: preview), animated: false,
                                   contentMode: .fill, showsRetry: false)
        }
        .frame(height: 166)
        .overlay(alignment: .topLeading) {
            EagleHotBadge().offset(x: -14, y: 10)
        }
        .overlay(alignment: .bottomTrailing) {
            Button { demoLiked.toggle() } label: {
                HStack(spacing: 5) {
                    Image(systemName: demoLiked ? "heart.fill" : "heart")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(demoLiked ? Color.pink : .white)
                        .eagleSymbolPop(demoLiked)
                    Text(demoLiked ? 128 : 127, format: .number)
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                }
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay { Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 1) }
            }
            .buttonStyle(EaglePressableStyle(kind: .swatch))
            .offset(x: 30, y: -12)
            .animation(.easeOut(duration: 0.2), value: demoLiked)
        }
        .accessibilityHidden(true)
    }

    /// The header counter as it looks with few and with many people.
    private var onlineDemo: some View {
        HStack(spacing: 28) {
            VStack(spacing: 10) {
                EagleOnlineBadge(sample: 3)
                Text(LaraL10n.text(en: "Under 5", es: "Menos de 5"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            VStack(spacing: 10) {
                EagleOnlineBadge(sample: 24)
                Text(LaraL10n.text(en: "5 or more", es: "5 o más"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityHidden(true)
    }

    private func playLikeDemo() {
        guard !reduceMotion else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            if step == 0 { demoLiked = true }
        }
    }

    private func next() {
        guard step < lastStep else { return close() }
        withAnimation(.easeInOut(duration: 0.3)) { step += 1 }
    }

    private func close() {
        UserDefaults.standard.set(true, forKey: Self.seenKey)
        withAnimation(.easeIn(duration: 0.22)) { appeared = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { onClose() }
    }
}
