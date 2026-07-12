import SwiftUI

/// The EPA AQI color track with a dot at the current value (UV-index idiom).
public struct AQIScaleBar: View {
    let aqi: Int

    public init(aqi: Int) { self.aqi = aqi }

    private static let stops: [Gradient.Stop] = [
        .init(color: Color(red: 0, green: 228 / 255, blue: 0), location: 0),
        .init(color: Color(red: 0, green: 228 / 255, blue: 0), location: 0.08),
        .init(color: Color(red: 1, green: 1, blue: 0), location: 0.12),
        .init(color: Color(red: 1, green: 1, blue: 0), location: 0.18),
        .init(color: Color(red: 1, green: 126 / 255, blue: 0), location: 0.24),
        .init(color: Color(red: 1, green: 126 / 255, blue: 0), location: 0.28),
        .init(color: Color(red: 1, green: 0, blue: 0), location: 0.34),
        .init(color: Color(red: 1, green: 0, blue: 0), location: 0.38),
        .init(color: Color(red: 143 / 255, green: 63 / 255, blue: 151 / 255), location: 0.50),
        .init(color: Color(red: 143 / 255, green: 63 / 255, blue: 151 / 255), location: 0.58),
        .init(color: Color(red: 126 / 255, green: 0, blue: 35 / 255), location: 0.78),
        .init(color: Color(red: 126 / 255, green: 0, blue: 35 / 255), location: 1),
    ]

    public var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(LinearGradient(stops: Self.stops, startPoint: .leading, endPoint: .trailing))
                    .frame(height: 5)
                Circle()
                    .fill(.white)
                    .frame(width: 9, height: 9)
                    .overlay(Circle().strokeBorder(.black.opacity(0.4), lineWidth: 1.5).padding(-2.5))
                    .offset(x: geo.size.width * min(Double(aqi) / 500, 1) - 4.5)
                    .animation(.easeInOut(duration: 0.4), value: aqi)
            }
            .frame(height: geo.size.height)
        }
        .frame(height: 9)
    }
}
