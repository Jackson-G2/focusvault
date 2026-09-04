import SwiftUI

enum Tideglass {
    static let canvas = Color(red: 0.027, green: 0.106, blue: 0.125)
    static let surface = Color(red: 0.055, green: 0.169, blue: 0.184)
    static let elevated = Color(red: 0.078, green: 0.231, blue: 0.231)
    static let ink = Color(red: 0.957, green: 0.941, blue: 0.910)
    static let muted = Color(red: 0.616, green: 0.718, blue: 0.694)
    static let signal = Color(red: 1.000, green: 0.722, blue: 0.416)
    static let seafoam = Color(red: 0.655, green: 0.851, blue: 0.706)
    static let coral = Color(red: 0.957, green: 0.518, blue: 0.416)
    static let line = Color(red: 0.725, green: 0.882, blue: 0.827).opacity(0.12)
}

struct GlassCard<Content: View>: View {
    private let cornerRadius: CGFloat
    private let tint: Color
    private let content: () -> Content

    init(
        cornerRadius: CGFloat = 24,
        tint: Color = Tideglass.surface,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.tint = tint
        self.content = content
    }

    @ViewBuilder
    var body: some View {
#if swift(>=6.0)
        if #available(macOS 26.0, *) {
            content()
                .glassEffect(.regular.tint(tint.opacity(0.18)), in: .rect(cornerRadius: cornerRadius))
        } else {
            fallback
        }
#else
        fallback
#endif
    }

    private var fallback: some View {
        content()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .foregroundColor(tint.opacity(0.20))
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .stroke(Tideglass.line, lineWidth: 1)
                    }
            }
    }
}

struct GlassButtonStyle: ButtonStyle {
    var tint: Color = Tideglass.signal
    var isProminent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(isProminent ? Tideglass.canvas : tint)
            .padding(.horizontal, isProminent ? 19 : 12)
            .padding(.vertical, isProminent ? 12 : 9)
            .frame(minHeight: isProminent ? 40 : 36)
            .contentShape(Capsule())
            .background {
#if swift(>=6.0)
                if #available(macOS 26.0, *) {
                    Color.clear
                        .glassEffect(
                            isProminent
                                ? .regular.tint(tint.opacity(0.92)).interactive()
                                : .regular.tint(tint.opacity(0.14)).interactive(),
                            in: .capsule
                        )
                } else {
                    fallback
                }
#else
                fallback
#endif
            }
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }

    private var fallback: some View {
        Capsule()
            .fill(isProminent ? tint : tint.opacity(0.12))
            .overlay {
                Capsule().strokeBorder(tint.opacity(isProminent ? 0.24 : 0.28), lineWidth: 1)
            }
    }
}

struct GlassPill: View {
    let title: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background {
#if swift(>=6.0)
                if #available(macOS 26.0, *) {
                    Color.clear.glassEffect(.regular.tint(tint.opacity(0.16)), in: .capsule)
                } else {
                    fallback
                }
#else
                fallback
#endif
            }
    }

    private var fallback: some View {
        Capsule()
            .fill(tint.opacity(0.12))
            .overlay {
                Capsule().strokeBorder(tint.opacity(0.28), lineWidth: 1)
            }
    }
}

struct GlassIcon: View {
    let systemName: String
    let tint: Color
    var size: CGFloat = 36

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.42, weight: .bold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background {
#if swift(>=6.0)
                if #available(macOS 26.0, *) {
                    Color.clear.glassEffect(.regular.tint(tint.opacity(0.16)), in: .circle)
                } else {
                    fallback
                }
#else
                fallback
#endif
            }
    }

    private var fallback: some View {
        Circle()
            .fill(tint.opacity(0.12))
            .overlay {
                Circle().strokeBorder(Tideglass.line, lineWidth: 1)
            }
    }
}

struct AppBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isDrifting = false

    var body: some View {
        let drift = reduceMotion ? 0.0 : (isDrifting ? 1.0 : 0.0)

        ZStack {
            Tideglass.canvas
            LinearGradient(
                colors: [
                    Tideglass.surface.opacity(0.58),
                    Tideglass.canvas.opacity(0.18),
                    Tideglass.elevated.opacity(0.30)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(Tideglass.seafoam.opacity(0.10))
                .frame(width: 420, height: 420)
                .blur(radius: 115)
                .offset(x: -300 + (drift * 18), y: 250 - (drift * 14))
            Circle()
                .fill(Tideglass.signal.opacity(0.10))
                .frame(width: 340, height: 340)
                .blur(radius: 100)
                .offset(x: 330 - (drift * 14), y: -250 + (drift * 18))
        }
        .ignoresSafeArea()
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 12).repeatForever(autoreverses: true)) {
                isDrifting = true
            }
        }
    }
}
