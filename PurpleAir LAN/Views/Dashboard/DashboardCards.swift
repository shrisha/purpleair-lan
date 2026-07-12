import SwiftUI
import PurpleAirKit

/// Full-width card: corrected PM2.5, EPA scale bar, health guidance.
struct PMCard: View {
    let reading: AQIReading

    var body: some View {
        MetricCard(
            icon: "aqi.medium",
            title: "PARTICULATE MATTER PM2.5",
            footnote: reading.category.healthGuidance
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(reading.correctedPM25, format: .number.precision(.fractionLength(1)))
                        .font(.system(size: 30, weight: .medium))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text("µg/m³ · EPA corrected")
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.62))
                }
                AQIScaleBar(aqi: reading.aqi)
            }
            .foregroundStyle(.white)
        }
    }
}

/// Square card: corrected humidity + comfort word + dew point footnote.
struct HumidityCard: View {
    let humidityPct: Double
    let dewPointF: Double

    var body: some View {
        MetricCard(
            icon: "humidity.fill",
            title: "HUMIDITY",
            footnote: "The dew point is \(Int(dewPointF.rounded()))° right now."
        ) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(Int(humidityPct.rounded()))")
                        .font(.system(size: 30, weight: .medium))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text("%")
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.62))
                }
                Text(AirQuality.comfortDescription(humidity: humidityPct))
                    .font(.system(size: 18, weight: .semibold))
            }
            .foregroundStyle(.white)
        }
    }
}

/// Square card: arc gauge with trend glyph, station pressure, trend footnote.
struct PressureCard: View {
    let hPa: Double
    let trend: PressureTrend?

    private var gaugeFraction: Double {
        switch trend {
        case .falling: 0.32
        case .rising: 0.68
        default: 0.5
        }
    }

    var body: some View {
        MetricCard(
            icon: "gauge.with.needle",
            title: "PRESSURE",
            footnote: trend?.footnote ?? "Gathering pressure history…"
        ) {
            VStack(spacing: 4) {
                PressureGauge(fraction: gaugeFraction, symbolName: trend?.symbolName ?? "minus")
                    .frame(width: 88, height: 56)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(hPa, format: .number.precision(.fractionLength(1)))
                        .font(.system(size: 22, weight: .medium))
                        .monospacedDigit()
                    Text("hPa")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.62))
                }
            }
            .frame(maxWidth: .infinity)
            .foregroundStyle(.white)
        }
    }
}

/// 270° arc gauge, Weather-style: hairline track, bright progress, end dot.
struct PressureGauge: View {
    let fraction: Double // 0…1 along the arc
    let symbolName: String

    var body: some View {
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height * 0.62)
            let radius = min(geo.size.width, geo.size.height * 1.4) / 2 - 4
            ZStack {
                arc(to: 1, center: center, radius: radius)
                    .stroke(.white.opacity(0.22), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                arc(to: fraction, center: center, radius: radius)
                    .stroke(.white.opacity(0.92), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                Circle()
                    .fill(.white)
                    .frame(width: 8, height: 8)
                    .position(endPoint(fraction: fraction, center: center, radius: radius))
                Image(systemName: symbolName)
                    .font(.system(size: 15, weight: .bold))
                    .position(center)
            }
        }
    }

    private func angle(for f: Double) -> Angle { .degrees(135 + 270 * f) }

    private func arc(to f: Double, center: CGPoint, radius: CGFloat) -> Path {
        Path { p in
            p.addArc(center: center, radius: radius,
                     startAngle: angle(for: 0), endAngle: angle(for: f), clockwise: false)
        }
    }

    private func endPoint(fraction: Double, center: CGPoint, radius: CGFloat) -> CGPoint {
        let a = angle(for: fraction).radians
        return CGPoint(x: center.x + radius * cos(a), y: center.y + radius * sin(a))
    }
}

#Preview("Cards on dark") {
    ZStack {
        Color(red: 0.1, green: 0.2, blue: 0.4).ignoresSafeArea()
        VStack(spacing: 8) {
            PMCard(reading: AQIReading(aqi: 28, category: .good, correctedPM25: 5.1, channelsAgree: true))
            HStack(alignment: .top, spacing: 8) {
                HumidityCard(humidityPct: 45, dewPointF: 53)
                PressureCard(hPa: 994.6, trend: .steady)
            }
        }
        .padding(16)
    }
    .environment(\.colorScheme, .dark)
}
