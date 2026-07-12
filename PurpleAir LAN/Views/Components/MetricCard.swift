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
