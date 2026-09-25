import SwiftUI

struct GameView: View {
    @State private var world = GameWorld()
    @State private var hingeDetector = HingeFlapDetector()
    @State private var foldSensor = FoldSensor()
    @State private var flapCount = 0
    @State private var inactiveSince: Date?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation) { timeline in
                Canvas { context, size in
                    world.advance(to: timeline.date, viewport: size)
                    GameRenderer.draw(world, in: &context, size: size)
                }
            }
            .onChange(of: proxy.size, initial: true) { _, newSize in
                // Fallback for a Duo without hinge data (iOS 27.0): a fold or
                // unfold changes the scene size.
                if foldSensor.register(size: newSize), !hasHinge {
                    flap()
                }
            }
        }
        // A sky-colored background, so the screen is never white, also
        // before the first frame.
        .background(Color(red: 0.23, green: 0.61, blue: 0.88))
        .ignoresSafeArea()
        // The main input: Apple's hinge API. A closing stroke is a flap.
        .onHingeAngleChange { degrees in
            guard let degrees else {
                hingeDetector.reset()
                world.hingeAngle = nil
                return
            }
            world.hingeAngle = degrees
            if hingeDetector.register(angle: degrees) {
                flap()
            }
        }
        .contentShape(Rectangle())
        // Tap to flap on devices that do not fold (and in the Simulator).
        .onTapGesture { flap() }
        .onChange(of: scenePhase) { _, newPhase in
            // On a Duo that switches the display off when you close it, the
            // scene goes inactive while closed. A short close and open is a flap.
            switch newPhase {
            case .active:
                if !hasHinge, let since = inactiveSince, Date.now.timeIntervalSince(since) < 2 {
                    flap()
                }
                inactiveSince = nil
            case .inactive, .background:
                if inactiveSince == nil {
                    inactiveSince = .now
                }
            @unknown default:
                break
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: flapCount)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
    }

    private var hasHinge: Bool { hingeDetector.angle != nil }

    private func flap() {
        if world.flap() {
            flapCount += 1
        }
    }
}

#Preview {
    GameView()
}
