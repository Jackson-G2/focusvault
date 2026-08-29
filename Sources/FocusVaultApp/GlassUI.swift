import SwiftUI

struct GlassCard<Content: View>: View {
    private let cornerRadius: CGFloat
    private let content: () -> Content

    init(
        cornerRadius: CGFloat = 26,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.content = content
    }

    @ViewBuilder
    var body: some View {
#if swift(>=6.0)
        if #available(macOS 26.0, *) {
            content()
                .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
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
                    .strokeBorder(.white.opacity(0.14), lineWidth: 1)
            }
    }
}

struct GlassButtonStyle: ButtonStyle {
    var tint: Color = .white
    var isProminent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(isProminent ? .black : tint)
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .contentShape(Capsule())
            .background {
#if swift(>=6.0)
                if #available(macOS 26.0, *) {
                    Color.clear
                        .glassEffect(
                            isProminent ? .regular.tint(.yellow).interactive() : .regular.interactive(),
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
            .fill(isProminent ? Color.yellow : Color.white.opacity(0.10))
            .overlay {
                Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 1)
            }
    }
}

struct GlassPill: View {
    let title: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background {
#if swift(>=6.0)
                if #available(macOS 26.0, *) {
                    Color.clear.glassEffect(.regular.tint(tint.opacity(0.18)), in: .capsule)
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
            .fill(tint.opacity(0.13))
            .overlay {
                Capsule().strokeBorder(tint.opacity(0.3), lineWidth: 1)
            }
    }
}

struct GlassIcon: View {
    let systemName: String
    let tint: Color

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(tint)
            .frame(width: 36, height: 36)
            .background {
#if swift(>=6.0)
                if #available(macOS 26.0, *) {
                    Color.clear.glassEffect(.regular.tint(tint.opacity(0.18)), in: .circle)
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
            .fill(tint.opacity(0.13))
            .overlay {
                Circle().strokeBorder(.white.opacity(0.15), lineWidth: 1)
            }
    }
}

struct GlassGroup<Content: View>: View {
    private let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    @ViewBuilder
    var body: some View {
#if swift(>=6.0)
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 16) {
                content()
            }
        } else {
            content()
        }
#else
        content()
#endif
    }
}

struct AppBackground: View {
    var body: some View {
        ZStack {
            Color(red: 0.035, green: 0.045, blue: 0.075)
            LinearGradient(
                colors: [
                    Color(red: 0.16, green: 0.10, blue: 0.28).opacity(0.72),
                    Color(red: 0.03, green: 0.15, blue: 0.24).opacity(0.58),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(Color.yellow.opacity(0.10))
                .frame(width: 380, height: 380)
                .blur(radius: 90)
                .offset(x: 330, y: -250)
            Circle()
                .fill(Color.cyan.opacity(0.11))
                .frame(width: 440, height: 440)
                .blur(radius: 110)
                .offset(x: -340, y: 260)
        }
        .ignoresSafeArea()
    }
}
