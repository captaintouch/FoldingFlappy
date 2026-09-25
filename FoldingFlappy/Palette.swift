import SwiftUI

/// A color with components that can be mixed, for smooth day and night blends.
struct RGB {
    var r: Double
    var g: Double
    var b: Double

    static let white = RGB(r: 1, g: 1, b: 1)
    static let black = RGB(r: 0, g: 0, b: 0)

    init(r: Double, g: Double, b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }

    init(_ hex: UInt32) {
        r = Double((hex >> 16) & 0xFF) / 255
        g = Double((hex >> 8) & 0xFF) / 255
        b = Double(hex & 0xFF) / 255
    }

    func mix(_ other: RGB, _ t: Double) -> RGB {
        RGB(r: r + (other.r - r) * t, g: g + (other.g - g) * t, b: b + (other.b - b) * t)
    }

    func lighter(_ amount: Double) -> RGB { mix(.white, amount) }
    func darker(_ amount: Double) -> RGB { mix(.black, amount) }

    var color: Color { Color(red: r, green: g, blue: b) }
    func withOpacity(_ opacity: Double) -> Color { Color(red: r, green: g, blue: b, opacity: opacity) }
}

/// All colors of the scenery at one moment of the day.
struct SkyPalette {
    var top: RGB
    var horizon: RGB
    var farMountain: RGB
    var nearMountain: RGB
    var hill: RGB
    var bush: RGB
    var cloud: RGB
    /// Color that is laid over the foreground (pipes, ground, bird).
    var tint: RGB
    var tintAmount: Double
    var stars: Double

    func mix(_ o: SkyPalette, _ t: Double) -> SkyPalette {
        SkyPalette(
            top: top.mix(o.top, t),
            horizon: horizon.mix(o.horizon, t),
            farMountain: farMountain.mix(o.farMountain, t),
            nearMountain: nearMountain.mix(o.nearMountain, t),
            hill: hill.mix(o.hill, t),
            bush: bush.mix(o.bush, t),
            cloud: cloud.mix(o.cloud, t),
            tint: tint.mix(o.tint, t),
            tintAmount: tintAmount + (o.tintAmount - tintAmount) * t,
            stars: stars + (o.stars - stars) * t
        )
    }

    static let morning = SkyPalette(
        top: RGB(0x5FB4E8), horizon: RGB(0xFFD9A8),
        farMountain: RGB(0x8FA9C9), nearMountain: RGB(0x6E8FB0),
        hill: RGB(0x7CC46A), bush: RGB(0x3E9E4A), cloud: RGB(0xFFFFFF),
        tint: RGB(0xFFB070), tintAmount: 0.08, stars: 0
    )

    static let day = SkyPalette(
        top: RGB(0x3A9BE0), horizon: RGB(0xC4E9FF),
        farMountain: RGB(0x9DB8D6), nearMountain: RGB(0x7C9CC0),
        hill: RGB(0x78C85A), bush: RGB(0x3FA34D), cloud: RGB(0xFFFFFF),
        tint: RGB(0xFFFFFF), tintAmount: 0, stars: 0
    )

    static let sunset = SkyPalette(
        top: RGB(0x4A5AA8), horizon: RGB(0xFF9E5E),
        farMountain: RGB(0x9C7FA8), nearMountain: RGB(0x7A6391),
        hill: RGB(0x5F8A4E), bush: RGB(0x2F6B3A), cloud: RGB(0xFFD2B8),
        tint: RGB(0xFF8040), tintAmount: 0.18, stars: 0.1
    )

    static let night = SkyPalette(
        top: RGB(0x0B1030), horizon: RGB(0x2A3570),
        farMountain: RGB(0x2A3462), nearMountain: RGB(0x1F2850),
        hill: RGB(0x1E3A3A), bush: RGB(0x12302A), cloud: RGB(0x5A6490),
        tint: RGB(0x1A2A6C), tintAmount: 0.42, stars: 1
    )

    static let dawn = SkyPalette(
        top: RGB(0x3E4C8A), horizon: RGB(0xFFA8A0),
        farMountain: RGB(0x7D7FA8), nearMountain: RGB(0x5E6590),
        hill: RGB(0x4F7A55), bush: RGB(0x2A5A38), cloud: RGB(0xFFC8D0),
        tint: RGB(0xFF90A0), tintAmount: 0.15, stars: 0.2
    )

    private static let keyframes: [(Double, SkyPalette)] = [
        (0.00, morning),
        (0.12, day),
        (0.42, day),
        (0.52, sunset),
        (0.62, night),
        (0.86, night),
        (0.95, dawn),
        (1.00, morning),
    ]

    /// The palette for a time of day from 0 to 1.
    static func at(_ progress: Double) -> SkyPalette {
        let p = min(max(progress, 0), 1)
        for i in 1..<keyframes.count where p <= keyframes[i].0 {
            let (t0, a) = keyframes[i - 1]
            let (t1, b) = keyframes[i]
            let t = (p - t0) / (t1 - t0)
            return a.mix(b, t * t * (3 - 2 * t))
        }
        return morning
    }
}
