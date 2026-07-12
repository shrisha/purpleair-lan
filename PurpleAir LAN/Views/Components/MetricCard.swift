import SwiftUI

/// Weather-app style frosted tile: uppercase header, content, footnote.
struct MetricCard<Content: View>: View {
    let icon: String
    let title: String
    var footnote: String?
    @ViewBuilder let content: () -> Content

    init(icon: String, title: String, footnote: String? = nil,
         @ViewBuilder content: @escaping () -> Content) {
        self.icon = icon
        self.title = title
        self.footnote = footnote
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .symbolRenderingMode(.hierarchical)
                Text(title)
                    .kerning(0.8)
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white.opacity(0.62))
            .padding(.bottom, 8)

            content()

            if let footnote {
                Spacer(minLength: 10)
                Text(footnote)
                    .font(.system(size: 12.5))
                    .lineSpacing(2)
                    .foregroundStyle(.white.opacity(0.72))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(.white.opacity(0.14), lineWidth: 0.5)
        )
    }
}

/// The EPA AQI color track with a dot at the current value (UV-index idiom).
struct AQIScaleBar: View {
    let aqi: Int

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

    var body: some View {
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
