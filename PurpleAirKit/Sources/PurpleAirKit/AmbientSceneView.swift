import SwiftUI

/// The full-bleed living wallpaper: a slow-drifting mesh gradient whose
/// palette follows AQI band and sun position, haze motes whose density
/// follows PM2.5, and stars on clean nights.
public struct AmbientSceneView: View {
    let aqi: Double
    let pm25: Double
    let latitude: Double?
    let longitude: Double?

    public init(aqi: Double, pm25: Double, latitude: Double?, longitude: Double?) {
        self.aqi = aqi
        self.pm25 = pm25
        self.latitude = latitude
        self.longitude = longitude
    }

    private struct Mote {
        let x: Double, y: Double, radius: Double, speed: Double, phase: Double
    }

    private static let motes: [Mote] = Self.generateMotes()
    private static let stars: [(x: Double, y: Double, phase: Double, radius: Double)] = Self.generateStars()

    private static func generateMotes() -> [Mote] {
        var result: [Mote] = []
        for i in 0..<90 {
            let x = Double(i) * 137.508.truncatingRemainder(dividingBy: 100) / 100
            let y = (Double(i) * 61.803).truncatingRemainder(dividingBy: 100) / 100
            let radius = 24 + Double((i * 7919) % 46)
            let speed = 0.004 + Double(i % 7) * 0.0012
            let phase = Double(i) * 0.7
            result.append(Mote(x: x, y: y, radius: radius, speed: speed, phase: phase))
        }
        return result
    }

    private static func generateStars() -> [(x: Double, y: Double, phase: Double, radius: Double)] {
        var result: [(x: Double, y: Double, phase: Double, radius: Double)] = []
        for i in 0..<70 {
            let x = (Double(i) * 97.7).truncatingRemainder(dividingBy: 100) / 100
            let y = (Double(i) * 43.3).truncatingRemainder(dividingBy: 100) / 100 * 0.55
            let phase = Double(i) * 1.31
            let radius = i % 3 == 0 ? 1.5 : 0.9
            result.append((x, y, phase, radius))
        }
        return result
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let sun = SolarModel.factors(date: timeline.date, latitude: latitude, longitude: longitude)

            ZStack {
                MeshGradient(
                    width: 3,
                    height: 3,
                    points: meshPoints(t: t),
                    colors: ScenePalette.meshColors(aqi: aqi, daylight: sun.daylight, twilight: sun.twilight)
                )

                Canvas { context, size in
                    drawStars(context: context, size: size, t: t, daylight: sun.daylight)
                    drawHaze(context: context, size: size, t: t)
                }
            }
            .drawingGroup() // Metal-composited; never applied above the material cards
        }
        .ignoresSafeArea()
    }

    /// 3×3 grid: edges pinned, two interior points drift on slow sine paths.
    private func meshPoints(t: TimeInterval) -> [SIMD2<Float>] {
        let cx = Float(0.5 + 0.22 * sin(t / 17))
        let cy = Float(0.42 + 0.08 * cos(t / 23))
        let bx = Float(0.5 + 0.25 * cos(t / 29))
        return [
            [0, 0], [0.5, 0], [1, 0],
            [0, 0.45], [cx, cy], [1, 0.5],
            [0, 1], [bx, 1], [1, 1],
        ]
    }

    private func drawStars(context: GraphicsContext, size: CGSize, t: TimeInterval, daylight: Double) {
        guard daylight < 0.18, aqi <= 100 else { return }
        let visibility = 1 - daylight / 0.18
        for star in Self.stars {
            let twinkle = 0.5 + 0.5 * sin(t * 1.3 + star.phase)
            let opacity = (0.25 + 0.55 * twinkle) * visibility
            let r = star.radius * size.width / 400
            let rect = CGRect(
                x: star.x * size.width - r, y: star.y * size.height - r,
                width: r * 2, height: r * 2
            )
            context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(opacity)))
        }
    }

    private func drawHaze(context: GraphicsContext, size: CGSize, t: TimeInterval) {
        let density = min(max((pm25 - 5) / 150, 0), 1)
        let count = Int(density * Double(Self.motes.count))
        guard count > 0 else { return }
        // haze tone drifts warm as the air worsens
        let warmth = min(aqi / 200, 1)
        let tone = RGB(r: 0.78, g: 0.78, b: 0.8)
            .mixed(with: RGB(hex: 0xC86038), amount: warmth)

        for mote in Self.motes.prefix(count) {
            let x = ((mote.x + t * mote.speed).truncatingRemainder(dividingBy: 1.2) - 0.1) * size.width
            let y = (mote.y + 0.03 * sin(t / 9 + mote.phase)) * size.height
            let r = mote.radius * size.width / 400
            let alpha = (0.05 + 0.07 * density) * (0.6 + 0.4 * sin(t / 5 + mote.phase))
            let gradient = Gradient(stops: [
                .init(color: tone.color.opacity(alpha), location: 0),
                .init(color: .clear, location: 1),
            ])
            context.fill(
                Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                with: .radialGradient(gradient, center: CGPoint(x: x, y: y), startRadius: 0, endRadius: r)
            )
        }
    }
}

#Preview("Good day") {
    AmbientSceneView(aqi: 28, pm25: 5, latitude: 37.24, longitude: -122.0)
}

#Preview("Smoke event") {
    AmbientSceneView(aqi: 180, pm25: 100, latitude: 37.24, longitude: -122.0)
}
