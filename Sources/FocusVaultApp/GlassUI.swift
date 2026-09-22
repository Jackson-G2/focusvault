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
                    .allowsHitTesting(false)
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
                        .allowsHitTesting(false)
                } else {
                    fallback.allowsHitTesting(false)
                }
#else
                fallback.allowsHitTesting(false)
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

struct GlassPill<Icon: View>: View {
    let title: String
    let tint: Color
    let icon: Icon

    init(title: String, systemImage: String, tint: Color) where Icon == Image {
        self.title = title
        self.tint = tint
        self.icon = Image(systemName: systemImage)
    }

    init(title: String, lockState: VaultLockState, tint: Color) where Icon == VaultLockGlyph {
        self.title = title
        self.tint = tint
        self.icon = VaultLockGlyph(state: lockState, size: 12.5, tint: tint)
    }

    var body: some View {
        HStack(spacing: 6) {
            icon
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
        }
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

struct GlassIcon<Icon: View>: View {
    let tint: Color
    var size: CGFloat = 36
    let icon: Icon

    init(systemName: String, tint: Color, size: CGFloat = 36) where Icon == Image {
        self.tint = tint
        self.size = size
        self.icon = Image(systemName: systemName)
    }

    init(lockState: VaultLockState, tint: Color, size: CGFloat = 36) where Icon == VaultLockGlyph {
        self.tint = tint
        self.size = size
        self.icon = VaultLockGlyph(state: lockState, size: size * 0.44, tint: tint)
    }

    var body: some View {
        icon
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

enum VaultLockState {
    case locked
    case open
}

/// Custom high-detail lock glyph drawn on a 24x24 design grid.
/// Locked shows a closed shackle with a keyhole punched through the body;
/// Open swings the shackle up and away with a small spring so the state
/// change is legible at a glance. Replaces the backwards-reading SF Symbol
/// toggles with one consistent state-per-glyph lock.
struct VaultLockGlyph: View {
    var state: VaultLockState = .locked
    var size: CGFloat = 16
    var tint: Color?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var shapeStyle: AnyShapeStyle {
        if let tint {
            return AnyShapeStyle(tint)
        }
        return AnyShapeStyle(.foreground)
    }

    var body: some View {
        ZStack {
            VaultShackleShape()
                .stroke(style: StrokeStyle(
                    lineWidth: size * (2.5 / 24),
                    lineCap: .round,
                    lineJoin: .round
                ))
                .rotationEffect(
                    .degrees(state == .open ? -38 : 0),
                    anchor: UnitPoint(x: 16.4 / 24, y: 11.6 / 24)
                )

            VaultLockBodyShape()
                .fill(style: FillStyle(eoFill: true, antialiased: true))
        }
        .foregroundStyle(shapeStyle)
        .frame(width: size, height: size)
        .animation(
            reduceMotion
                ? .easeOut(duration: 0.18)
                : .spring(response: 0.4, dampingFraction: 0.72),
            value: state
        )
        .accessibilityHidden(true)
    }
}

private struct VaultLockBodyShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24

        var path = Path()
        path.addRoundedRect(
            in: CGRect(x: 4.2 * s, y: 10.2 * s, width: 15.6 * s, height: 10.8 * s),
            cornerSize: CGSize(width: 3.6 * s, height: 3.6 * s),
            style: .continuous
        )

        // Keyhole: circular bowl flowing into a flared slot, kept as one
        // continuous subpath so the even-odd fill punches it cleanly.
        path.move(to: CGPoint(x: 10.94 * s, y: 16.32 * s))
        path.addLine(to: CGPoint(x: 10.48 * s, y: 18.55 * s))
        path.addLine(to: CGPoint(x: 13.52 * s, y: 18.55 * s))
        path.addLine(to: CGPoint(x: 13.06 * s, y: 16.32 * s))
        // Sweep through the screen-top of the circle (270deg): decreasing
        // angles from 61.1 -> 0 -> -90 -> -180 -> -241.1, so clockwise:true.
        path.addArc(
            center: CGPoint(x: 12.0 * s, y: 14.4 * s),
            radius: 2.2 * s,
            startAngle: .degrees(61.1),
            endAngle: .degrees(-241.1),
            clockwise: true
        )
        path.closeSubpath()
        return path
    }
}

private struct VaultShackleShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24

        var path = Path()
        path.move(to: CGPoint(x: 7.6 * s, y: 11.6 * s))
        path.addLine(to: CGPoint(x: 7.6 * s, y: 7.3 * s))
        // Empirically verified via probe render: in SwiftUI Path.addArc,
        // 90deg is screen-down, 270deg screen-up, and clockwise:true sweeps
        // through DECREASING angles. So 180->0 with clockwise:false passes
        // through 270 = clean dome on top of the body.
        path.addArc(
            center: CGPoint(x: 12.0 * s, y: 7.3 * s),
            radius: 4.4 * s,
            startAngle: .degrees(180),
            endAngle: .degrees(0),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: 16.4 * s, y: 11.6 * s))
        return path
    }
}

struct VaultyMascot: View {
    let size: CGFloat
    let isProtected: Bool

    init(size: CGFloat = 34, isProtected: Bool = false) {
        self.size = size
        self.isProtected = isProtected
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28)
                .fill(isProtected ? Tideglass.seafoam : Tideglass.surface)
                .overlay {
                    RoundedRectangle(cornerRadius: size * 0.28)
                        .stroke(Tideglass.canvas, lineWidth: max(1, size * 0.08))
                }

            RoundedRectangle(cornerRadius: size * 0.18)
                .stroke(Tideglass.canvas, lineWidth: max(1, size * 0.06))
                .frame(width: size * 0.50, height: size * 0.54)

            Circle()
                .fill(Tideglass.canvas)
                .frame(width: size * 0.24, height: size * 0.24)
                .overlay {
                    Circle()
                        .stroke(Tideglass.signal, lineWidth: max(1, size * 0.05))
                }

            HStack(spacing: size * 0.16) {
                Circle()
                    .fill(Tideglass.canvas)
                    .frame(width: size * 0.10, height: size * 0.10)
                Circle()
                    .fill(Tideglass.canvas)
                    .frame(width: size * 0.10, height: size * 0.10)
            }
            .offset(y: -size * 0.25)

            Capsule()
                .stroke(Tideglass.canvas, lineWidth: max(1, size * 0.04))
                .frame(width: size * 0.18, height: size * 0.07)
                .offset(y: -size * 0.11)
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isProtected ? "Vaulty protected" : "Vaulty open")
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
