import SwiftUI

/// Turns the hinge angle of an iPhone Duo into flap events.
///
/// A flap is one fold stroke in either direction: you close or open the
/// phone by at least `strokeAngle` degrees. After a flap, the next flap comes
/// when you move the hinge back the other way by `strokeAngle` degrees. If
/// you keep moving in the same direction, there is no new flap. This stops
/// sensor noise and one long movement from making extra flaps.
struct HingeFlapDetector {
    /// How far (degrees) you must move the hinge to flap.
    var strokeAngle = 8.0

    /// The last hinge angle in degrees. 0 is closed, 180 is flat.
    private(set) var angle: Double?

    /// Direction of the last flap: 1 is opening, -1 is closing, 0 is none yet.
    private var direction = 0.0
    /// The angle where the current stroke started, or the furthest angle
    /// in the direction of the last flap.
    private var anchor = 0.0

    /// Registers a new hinge angle.
    /// - Returns: `true` when the change completes a fold stroke.
    mutating func register(angle degrees: Double) -> Bool {
        guard angle != nil else {
            angle = degrees
            anchor = degrees
            return false
        }
        angle = degrees

        let delta = degrees - anchor
        if direction != 0, delta * direction > 0 {
            // Still moving the same way as the last flap: follow it.
            anchor = degrees
            return false
        }
        guard abs(delta) >= strokeAngle else { return false }
        direction = delta > 0 ? 1 : -1
        anchor = degrees
        return true
    }

    /// Forgets the hinge, for example when the system stops sending updates.
    mutating func reset() {
        angle = nil
        direction = 0
    }
}

extension View {
    /// Sends the hinge angle in degrees to `action`, or `nil` when this view
    /// gets no hinge data. Uses Apple's `onHingeChange` (iOS 27.1 and later).
    /// On earlier systems, the modifier has no effect.
    func onHingeAngleChange(_ action: @escaping (Double?) -> Void) -> some View {
        modifier(HingeAngleModifier(action: action))
    }
}

private struct HingeAngleModifier: ViewModifier {
    let action: (Double?) -> Void

    func body(content: Content) -> some View {
        if #available(iOS 27.1, *) {
            content.onHingeChange { _, newContext in
                action(newContext.hinge?.angle.degrees)
            }
        } else {
            content
        }
    }
}
