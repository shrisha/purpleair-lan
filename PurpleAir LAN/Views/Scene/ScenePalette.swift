// PurpleAir LAN/Views/Scene/ScenePalette.swift
import SwiftUI

/// Linear-RGB triple used for palette math (SwiftUI Color is opaque).
struct RGB: Equatable {
    let r: Double
    let g: Double
    let b: Double

    init(r: Double, g: Double, b: Double) {
        self.r = r; self.g = g; self.b = b
    }

    init(hex: UInt32) {
        r = Double((hex >> 16) & 0xFF) / 255
        g = Double((hex >> 8) & 0xFF) / 255
        b = Double(hex & 0xFF) / 255
    }

    func mixed(with other: RGB, amount: Double) -> RGB {
        let t = min(max(amount, 0), 1)
        if t == 0 { return self }
        if t == 1 { return other }
        return RGB(r: r + (other.r - r) * t, g: g + (other.g - g) * t, b: b + (other.b - b) * t)
    }

    var color: Color { Color(red: r, green: g, blue: b) }
}

/// The wallpaper's palette: continuous in AQI (anchored at band midpoints),
/// blended day/night by the solar factors, warmed at the horizon in twilight.
enum ScenePalette {
    /// Day anchors [top, upper, lower, horizon] per EPA band.
    private static let day: [[RGB]] = [
        [RGB(hex: 0x123A8C), RGB(hex: 0x2E63C4), RGB(hex: 0x5E93DB), RGB(hex: 0xA8CDEE)], // Good — serene sky
        [RGB(hex: 0x2B4A7E), RGB(hex: 0x5F7BA6), RGB(hex: 0xC99C55), RGB(hex: 0xEECB7F)], // Moderate — golden haze
        [RGB(hex: 0x3A3550), RGB(hex: 0x77573F), RGB(hex: 0xC07A3A), RGB(hex: 0xE8A860)], // USG — amber haze
        [RGB(hex: 0x2E2230), RGB(hex: 0x6E3A2E), RGB(hex: 0xA34A2A), RGB(hex: 0xC86038)], // Unhealthy — smoky brown
        [RGB(hex: 0x1E1428), RGB(hex: 0x4A2244), RGB(hex: 0x7A3060), RGB(hex: 0x94425F)], // V. Unhealthy — maroon dusk
        [RGB(hex: 0x0E0A0E), RGB(hex: 0x2A1016), RGB(hex: 0x4A1220), RGB(hex: 0x641824)], // Hazardous — oxblood
    ]

    /// Night anchors, same shape.
    private static let night: [[RGB]] = [
        [RGB(hex: 0x05070F), RGB(hex: 0x0B1026), RGB(hex: 0x141D3E), RGB(hex: 0x1B2A52)],
        [RGB(hex: 0x070810), RGB(hex: 0x12142A), RGB(hex: 0x242040), RGB(hex: 0x3A3050)],
        [RGB(hex: 0x0A080E), RGB(hex: 0x181022), RGB(hex: 0x2C1A2A), RGB(hex: 0x402438)],
        [RGB(hex: 0x0A0609), RGB(hex: 0x1A0D14), RGB(hex: 0x301420), RGB(hex: 0x421A28)],
        [RGB(hex: 0x080510), RGB(hex: 0x150A1E), RGB(hex: 0x26102E), RGB(hex: 0x331640)],
        [RGB(hex: 0x060406), RGB(hex: 0x12060A), RGB(hex: 0x200A12), RGB(hex: 0x2C0E18)],
    ]

    /// Twilight horizon warmth.
    private static let duskTint = RGB(hex: 0xFF7A3C)

    /// AQI values at which each band's palette applies exactly.
    private static let bandMidpoints: [Double] = [25, 75, 125, 175, 250, 400]

    static func anchors(aqi: Double, daylight: Double, twilight: Double) -> [RGB] {
        // continuous band position from AQI
        let (lower, upper, t) = bandBlend(aqi: aqi)
        return (0..<4).map { i in
            let dayColor = day[lower][i].mixed(with: day[upper][i], amount: t)
            let nightColor = night[lower][i].mixed(with: night[upper][i], amount: t)
            var color = nightColor.mixed(with: dayColor, amount: daylight)
            if i >= 2 { // warm the lower sky / horizon at dawn & dusk
                color = color.mixed(with: duskTint, amount: twilight * (i == 3 ? 0.45 : 0.22))
            }
            return color
        }
    }

    /// Row-major 3×3 colors for MeshGradient: top row, mid row, horizon row.
    static func meshColors(aqi: Double, daylight: Double, twilight: Double) -> [Color] {
        let p = anchors(aqi: aqi, daylight: daylight, twilight: twilight)
        return [
            p[0].color, p[0].mixed(with: p[1], amount: 0.3).color, p[0].color,
            p[1].color, p[1].mixed(with: p[2], amount: 0.5).color, p[1].color,
            p[2].color, p[3].color, p[2].color, // brightest glow bottom-center
        ]
    }

    private static func bandBlend(aqi: Double) -> (lower: Int, upper: Int, t: Double) {
        let clamped = min(max(aqi, bandMidpoints.first!), bandMidpoints.last!)
        for i in 0..<(bandMidpoints.count - 1) where clamped <= bandMidpoints[i + 1] {
            let span = bandMidpoints[i + 1] - bandMidpoints[i]
            return (i, i + 1, (clamped - bandMidpoints[i]) / span)
        }
        return (bandMidpoints.count - 1, bandMidpoints.count - 1, 0)
    }
}
