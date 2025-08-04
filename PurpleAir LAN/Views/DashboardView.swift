import SwiftUI

struct DashboardView: View {
    let hostname: String
    
    // Service for fetching sensor data
    @StateObject private var purpleAirService = PurpleAirService()
    
    // UserDefaults for resetting configuration
    @AppStorage("sensorHostname") private var sensorHostname = ""
    
    // Timer for auto-refresh
    @State private var refreshTimer: Timer?
    
    // Last update tracking
    @State private var lastUpdateTime = Date()
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Status header
                    statusHeader
                    
                    // Main content based on state
                    switch purpleAirService.state {
                    case .idle, .loading:
                        loadingView
                        
                    case .loaded(let data):
                        dataGridView(data: data)
                        
                    case .error(let error):
                        errorView(error: error)
                    }
                    
                    Spacer(minLength: 20)
                }
                .padding()
            }
            .navigationTitle("PurpleAir LAN")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    // Refresh button
                    Button(action: fetchData) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(purpleAirService.isLoading)
                    
                    // Settings button
                    Button(action: resetConfiguration) {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .refreshable {
                await purpleAirService.fetchSensorData(from: hostname)
                lastUpdateTime = Date()
            }
        }
        .onAppear {
            fetchData()
            startAutoRefresh()
        }
        .onDisappear {
            stopAutoRefresh()
        }
    }
}

// MARK: - View Components
private extension DashboardView {
    /// Status header showing connection info and last update
    var statusHeader: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .foregroundColor(.green)
                Text("Connected to \(hostname)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
            }
            
            if case .loaded = purpleAirService.state {
                HStack {
                    Text("Last updated: \(lastUpdateTime, formatter: timeFormatter)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
        }
        .padding(.horizontal)
    }
    
    /// Loading view with weather-themed animation
    var loadingView: some View {
        VStack(spacing: 30) {
            WeatherSpinner()
            
            Text("Checking sensor...")
                .font(.headline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 300)
    }
    
    /// Data grid showing the four main sensor values
    func dataGridView(data: PurpleAirData) -> some View {
        LazyVGrid(columns: gridColumns, spacing: 16) {
            // Temperature tile
            DataTile(
                title: "Temperature",
                value: data.temperatureDisplay,
                icon: "thermometer",
                backgroundColor: temperatureColor(data.currentTempF),
                iconColor: .white
            )
            
            // Humidity tile
            DataTile(
                title: "Humidity",
                value: data.humidityDisplay,
                icon: "humidity",
                backgroundColor: humidityColor(data.currentHumidity),
                iconColor: .white
            )
            
            // Pressure tile
            DataTile(
                title: "Pressure",
                value: data.pressureDisplay,
                icon: "barometer",
                backgroundColor: .indigo,
                iconColor: .white
            )
            
            // AQI tile with dynamic background color
            DataTile(
                title: "Air Quality",
                value: data.aqiDisplay,
                subtitle: data.aqiQualityDescription,
                icon: "lungs",
                backgroundColor: data.aqiBackgroundColor,
                iconColor: .white
            )
        }
        .padding(.horizontal)
    }
    
    /// Error view with retry option
    func errorView(error: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 60))
                .foregroundColor(.orange)
            
            Text("Connection Error")
                .font(.headline)
            
            Text(error)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button("Try Again") {
                fetchData()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, minHeight: 300)
    }
    
    /// Grid columns configuration
    var gridColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 16),
            GridItem(.flexible(), spacing: 16)
        ]
    }
}

// MARK: - Helper Methods
private extension DashboardView {
    /// Fetch sensor data
    func fetchData() {
        Task {
            await purpleAirService.fetchSensorData(from: hostname)
            if case .loaded = purpleAirService.state {
                lastUpdateTime = Date()
            }
        }
    }
    
    /// Reset configuration to go back to setup
    func resetConfiguration() {
        sensorHostname = ""
    }
    
    /// Start auto-refresh timer (every 30 seconds)
    func startAutoRefresh() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { _ in
            // Only refresh if not currently loading and not in error state
            if !purpleAirService.isLoading && purpleAirService.hasData {
                fetchData()
            }
        }
    }
    
    /// Stop auto-refresh timer
    func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
    
    /// Get color for temperature based on value
    func temperatureColor(_ temp: Double?) -> Color {
        guard let temp = temp else { return .gray }
        
        switch temp {
        case ..<32:
            return .blue // Freezing
        case 32..<50:
            return .cyan // Cold
        case 50..<70:
            return .green // Cool
        case 70..<85:
            return .orange // Warm
        default:
            return .red // Hot
        }
    }
    
    /// Get color for humidity based on value
    func humidityColor(_ humidity: Double?) -> Color {
        guard let humidity = humidity else { return .gray }
        
        switch humidity {
        case ..<30:
            return .orange // Dry
        case 30..<60:
            return .green // Comfortable
        default:
            return .blue // Humid
        }
    }
    
    /// Time formatter for last update display
    var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }
}

// MARK: - Preview
#Preview {
    DashboardView(hostname: "purple.air")
}