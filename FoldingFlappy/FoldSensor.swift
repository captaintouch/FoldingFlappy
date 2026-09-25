import CoreGraphics
import Foundation

/// Fallback that turns folding and unfolding of an iPhone Duo into flap
/// events when the hinge API sends no data (see `HingeSensor.swift`).
///
/// It looks at how much space the scene
/// gets. When you close or open the Duo, the app moves between the cover
/// display and the large inner display (or the scene is resized), so the
/// available area changes a lot. A rotation only swaps width and height and
/// keeps the area, so the sensor ignores it.
struct FoldSensor {
    enum Posture {
        case folded
        case unfolded
    }

    /// The posture after the last fold or unfold that the sensor saw.
    private(set) var posture: Posture?

    /// Minimum relative change in area that counts as a fold or unfold.
    var areaThreshold = 0.25

    /// Minimum time between two flap events.
    var debounce: TimeInterval = 0.12

    private var baselineArea: Double = 0
    private var lastEvent: Date = .distantPast

    /// Registers a new scene size.
    /// - Returns: `true` when the change is a fold or an unfold.
    mutating func register(size: CGSize, at date: Date = .now) -> Bool {
        let area = Double(size.width * size.height)
        guard area > 0 else { return false }
        guard baselineArea > 0 else {
            baselineArea = area
            return false
        }

        // The baseline only moves on a real posture change. An animated resize
        // that comes in small steps thus still triggers exactly one event.
        let ratio = area / baselineArea
        guard abs(ratio - 1) > areaThreshold else { return false }
        baselineArea = area
        posture = ratio > 1 ? .unfolded : .folded

        guard date.timeIntervalSince(lastEvent) > debounce else { return false }
        lastEvent = date
        return true
    }
}
