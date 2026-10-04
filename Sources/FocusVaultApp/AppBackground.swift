import SwiftUI

/// The quiet room is static at rest. Continuous decorative drift repeatedly
/// invalidated the entire blurred background while no task was running.
/// Active clocks/editing/games retain their own meaningful, reduced-motion-aware
/// animation; the idle dashboard no longer schedules a perpetual display loop.
struct AppBackground: View {
    var body: some View {
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
                .offset(x: -300, y: 250)
            Circle()
                .fill(Tideglass.signal.opacity(0.10))
                .frame(width: 340, height: 340)
                .blur(radius: 100)
                .offset(x: 330, y: -250)
        }
        .ignoresSafeArea()
    }
}
