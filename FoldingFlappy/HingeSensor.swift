import SwiftUI

/// Turns the hinge angle of an iPhone Duo into flap events.
///
/// A flap is one wing stroke: you close the phone by at least `strokeAngle`
/// degrees. Before the next flap, you must open it again by at least
/// `rearmAngle` degrees. This hysteresis stops sensor noise from making
/// extra flaps.
struct HingeFlapDetector {
    /// How far (degrees) you must close the phone to flap.
    var strokeAngle = 20.0
    /// How far (degrees) you must open the phone again before the next flap.
    var rearmAngle = 12.0

    /// The last hinge angle in degrees. 0 is closed, 180 is flat.
    private(set) var angle: Double?

    private var isArmed = true
    /// Most open angle since the last re-arm, or most closed angle since the last flap.
    private var extreme = 0.0

    /// Registers a new hinge angle.
    /// - Returns: `true` when the change completes a closing stroke.
    mutating func register(angle degrees: Double) -> Bool {
        guard angle != nil else {
            angle = degrees
            extreme = degrees
            return false
        }
        angle = degrees

        if isArmed {
            extreme = max(extreme, degrees)
            if extreme - degrees >= strokeAngle {
                isArmed = false
                extreme = degrees
                return true
            }
        } else {
            extreme = min(extreme, degrees)
            if degrees - extreme >= rearmAngle {
                isArmed = true
                extreme = degrees
            }
        }
        return false
    }

    /// Forgets the hinge, for example when the system stops sending updates.
    mutating func reset() {
        angle = nil
        isArmed = true
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
