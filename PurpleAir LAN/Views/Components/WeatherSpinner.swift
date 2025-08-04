import SwiftUI

/// A weather-themed loading animation for sensor data fetching
struct WeatherSpinner: View {
    // Animation states
    @State private var isRotating = false
    @State private var isFloating = false
    @State private var cloudOpacity = 0.6
    
    var body: some View {
        ZStack {
            // Background gradient circle
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: [
                            Color.blue.opacity(0.1),
                            Color.cyan.opacity(0.05)
                        ]),
                        center: .center,
                        startRadius: 20,
                        endRadius: 100
                    )
                )
                .frame(width: 160, height: 160)
                .scaleEffect(isFloating ? 1.05 : 0.95)
                .animation(
                    .easeInOut(duration: 2.0).repeatForever(autoreverses: true),
                    value: isFloating
                )
            
            // Weather elements
            VStack(spacing: 8) {
                // Cloud with rotating elements inside
                ZStack {
                    // Main cloud shape
                    Image(systemName: "cloud.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.blue.opacity(cloudOpacity))
                        .offset(y: isFloating ? -3 : 3)
                        .animation(
                            .easeInOut(duration: 3.0).repeatForever(autoreverses: true),
                            value: isFloating
                        )
                    
                    // Rotating sensor elements inside cloud
                    ZStack {
                        // Thermometer
                        Image(systemName: "thermometer")
                            .font(.system(size: 12))
                            .foregroundColor(.red.opacity(0.8))
                            .offset(x: 8, y: -2)
                        
                        // Humidity drop
                        Image(systemName: "drop.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.blue.opacity(0.8))
                            .offset(x: -8, y: 2)
                        
                        // Wind indicator
                        Image(systemName: "wind")
                            .font(.system(size: 10))
                            .foregroundColor(.gray.opacity(0.8))
                            .offset(x: 2, y: 8)
                    }
                    .rotationEffect(.degrees(isRotating ? 360 : 0))
                    .animation(
                        .linear(duration: 4.0).repeatForever(autoreverses: false),
                        value: isRotating
                    )
                }
                
                // Scanning effect - animated dots
                HStack(spacing: 4) {
                    ForEach(0..<3) { index in
                        Circle()
                            .fill(Color.blue.opacity(0.7))
                            .frame(width: 6, height: 6)
                            .scaleEffect(isFloating ? 1.0 : 0.5)
                            .animation(
                                .easeInOut(duration: 0.6)
                                .repeatForever(autoreverses: true)
                                .delay(Double(index) * 0.2),
                                value: isFloating
                            )
                    }
                }
                .padding(.top, 8)
                
                // Data waves - representing sensor communication
                VStack(spacing: 2) {
                    ForEach(0..<3) { index in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color.cyan.opacity(0.3),
                                        Color.blue.opacity(0.6)
                                    ]),
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(
                                width: isRotating ? CGFloat(20 + index * 10) : CGFloat(30 - index * 5),
                                height: 2
                            )
                            .animation(
                                .easeInOut(duration: 1.5)
                                .repeatForever(autoreverses: true)
                                .delay(Double(index) * 0.3),
                                value: isRotating
                            )
                    }
                }
                .padding(.top, 12)
            }
        }
        .onAppear {
            startAnimations()
        }
    }
}

// MARK: - Private Methods
private extension WeatherSpinner {
    /// Start all animations when the view appears
    func startAnimations() {
        withAnimation {
            isRotating = true
            isFloating = true
        }
        
        // Animate cloud opacity for breathing effect
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
            withAnimation(.easeInOut(duration: 2.0)) {
                cloudOpacity = Double.random(in: 0.4...0.8)
            }
        }
    }
}

// MARK: - Alternative Weather Spinner Styles
extension WeatherSpinner {
    /// A simpler version with just cloud and rotation
    static var simple: some View {
        WeatherSpinnerSimple()
    }
    
    /// A compact version for smaller spaces
    static var compact: some View {
        WeatherSpinnerCompact()
    }
}

/// Simplified weather spinner for smaller contexts
struct WeatherSpinnerSimple: View {
    @State private var isRotating = false
    
    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Image(systemName: "cloud")
                    .font(.system(size: 32))
                    .foregroundColor(.blue.opacity(0.6))
                
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 16))
                    .foregroundColor(.cyan)
                    .rotationEffect(.degrees(isRotating ? 360 : 0))
                    .animation(
                        .linear(duration: 2.0).repeatForever(autoreverses: false),
                        value: isRotating
                    )
            }
        }
        .onAppear {
            isRotating = true
        }
    }
}

/// Compact weather spinner for tight spaces
struct WeatherSpinnerCompact: View {
    @State private var isAnimating = false
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "cloud.fill")
                .font(.system(size: 16))
                .foregroundColor(.blue.opacity(0.7))
                .scaleEffect(isAnimating ? 1.1 : 0.9)
                .animation(
                    .easeInOut(duration: 1.0).repeatForever(autoreverses: true),
                    value: isAnimating
                )
            
            ForEach(0..<3) { index in
                Circle()
                    .fill(Color.blue.opacity(0.5))
                    .frame(width: 4, height: 4)
                    .scaleEffect(isAnimating ? 1.0 : 0.3)
                    .animation(
                        .easeInOut(duration: 0.8)
                        .repeatForever(autoreverses: true)
                        .delay(Double(index) * 0.2),
                        value: isAnimating
                    )
            }
        }
        .onAppear {
            isAnimating = true
        }
    }
}

// MARK: - Preview
#Preview("Weather Spinner Variations") {
    VStack(spacing: 40) {
        VStack {
            WeatherSpinner()
            Text("Full Weather Spinner")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        
        VStack {
            WeatherSpinner.simple
            Text("Simple Spinner")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        
        VStack {
            WeatherSpinner.compact
            Text("Compact Spinner")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    .padding()
}