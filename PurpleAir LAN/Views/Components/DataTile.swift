import SwiftUI

/// A reusable tile component for displaying sensor data
struct DataTile: View {
    let title: String
    let value: String
    let subtitle: String?
    let icon: String
    let backgroundColor: Color
    let iconColor: Color
    
    // Animation state for value changes
    @State private var isAnimating = false
    
    /// Initialize with required parameters
    init(
        title: String,
        value: String,
        subtitle: String? = nil,
        icon: String,
        backgroundColor: Color,
        iconColor: Color = .white
    ) {
        self.title = title
        self.value = value
        self.subtitle = subtitle
        self.icon = icon
        self.backgroundColor = backgroundColor
        self.iconColor = iconColor
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with icon and title
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(iconColor.opacity(0.9))
                
                Spacer()
                
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(iconColor.opacity(0.9))
                    .multilineTextAlignment(.trailing)
            }
            .padding(.top, 16)
            .padding(.horizontal, 16)
            
            Spacer()
            
            // Main value display
            VStack(spacing: 4) {
                Text(value)
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(iconColor)
                    .multilineTextAlignment(.center)
                    .scaleEffect(isAnimating ? 1.05 : 1.0)
                    .animation(.easeInOut(duration: 0.3), value: isAnimating)
                
                // Optional subtitle
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(iconColor.opacity(0.8))
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 16)
            
            Spacer()
        }
        .frame(height: 120)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(backgroundColor)
                .shadow(color: backgroundColor.opacity(0.3), radius: 8, x: 0, y: 4)
        )
        .onChange(of: value) { oldValue, newValue in
            // Animate when value changes
            if oldValue != newValue {
                triggerValueChangeAnimation()
            }
        }
    }
}

// MARK: - Private Methods
private extension DataTile {
    /// Trigger animation when value changes
    func triggerValueChangeAnimation() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isAnimating = true
        }
        
        // Reset animation state after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation(.easeInOut(duration: 0.2)) {
                isAnimating = false
            }
        }
    }
}

// MARK: - Tile Variants
extension DataTile {
    /// Create a temperature tile with appropriate styling
    static func temperature(value: String, temp: Double?) -> DataTile {
        let color: Color
        if let temp = temp {
            switch temp {
            case ..<32:
                color = .blue
            case 32..<50:
                color = .cyan
            case 50..<70:
                color = .green
            case 70..<85:
                color = .orange
            default:
                color = .red
            }
        } else {
            color = .gray
        }
        
        return DataTile(
            title: "Temperature",
            value: value,
            icon: "thermometer",
            backgroundColor: color,
            iconColor: .white
        )
    }
    
    /// Create a humidity tile with appropriate styling
    static func humidity(value: String, humidity: Double?) -> DataTile {
        let color: Color
        if let humidity = humidity {
            switch humidity {
            case ..<30:
                color = .orange
            case 30..<60:
                color = .green
            default:
                color = .blue
            }
        } else {
            color = .gray
        }
        
        return DataTile(
            title: "Humidity",
            value: value,
            icon: "humidity",
            backgroundColor: color,
            iconColor: .white
        )
    }
    
    /// Create a pressure tile with standard styling
    static func pressure(value: String) -> DataTile {
        return DataTile(
            title: "Pressure",
            value: value,
            icon: "barometer",
            backgroundColor: .indigo,
            iconColor: .white
        )
    }
    
    /// Create an AQI tile with dynamic background color
    static func airQuality(value: String, qualityDescription: String, backgroundColor: Color) -> DataTile {
        return DataTile(
            title: "Air Quality",
            value: value,
            subtitle: qualityDescription,
            icon: "lungs",
            backgroundColor: backgroundColor,
            iconColor: .white
        )
    }
}

// MARK: - Preview
#Preview("Temperature Tile") {
    VStack(spacing: 20) {
        HStack(spacing: 16) {
            DataTile.temperature(value: "72°F", temp: 72)
            DataTile.humidity(value: "45%", humidity: 45)
        }
        
        HStack(spacing: 16) {
            DataTile.pressure(value: "1013.2 mb")
            DataTile.airQuality(
                value: "25 AQI",
                qualityDescription: "Good",
                backgroundColor: Color.green
            )
        }
    }
    .padding()
}