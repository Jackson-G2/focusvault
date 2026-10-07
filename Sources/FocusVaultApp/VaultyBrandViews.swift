import SwiftUI

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
