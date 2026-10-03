import SwiftUI

// Glass belongs to the Xcode 26 / Swift 6.2+ SDK cohort, not Swift 6 language
// mode. SwiftPM still uses language mode 5 here. For an intentionally mixed
// modern-compiler/older-SDK build, define VAULTY_FORCE_MATERIAL explicitly.

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
    @Environment(\.vaultyMaterialSnapshot) private var materialSnapshot
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
#if compiler(>=6.2) && !VAULTY_FORCE_MATERIAL
        if #available(macOS 26.0, *), !materialSnapshot {
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
    @Environment(\.vaultyMaterialSnapshot) private var materialSnapshot
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
#if compiler(>=6.2) && !VAULTY_FORCE_MATERIAL
                // Native translucent tint is not a guaranteed opaque fill in
                // dark appearance. Primary actions require signal/canvas contrast;
                // keep their solid treatment while secondary actions use glass.
                if #available(macOS 26.0, *), !materialSnapshot, !isProminent {
                    Color.clear
                        .glassEffect(
                            .regular.tint(tint.opacity(0.14)).interactive(),
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
    @Environment(\.vaultyMaterialSnapshot) private var materialSnapshot
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
#if compiler(>=6.2) && !VAULTY_FORCE_MATERIAL
                if #available(macOS 26.0, *), !materialSnapshot {
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
    @Environment(\.vaultyMaterialSnapshot) private var materialSnapshot
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
#if compiler(>=6.2) && !VAULTY_FORCE_MATERIAL
                if #available(macOS 26.0, *), !materialSnapshot {
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
