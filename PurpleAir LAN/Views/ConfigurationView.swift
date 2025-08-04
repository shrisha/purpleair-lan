import SwiftUI

struct ConfigurationView: View {
    // Store hostname in UserDefaults for persistence
    @AppStorage("sensorHostname") private var sensorHostname = ""
    
    // Local state for the text field
    @State private var hostnameInput = ""
    
    // Service for testing connection
    @StateObject private var purpleAirService = PurpleAirService()
    
    // UI state
    @State private var showingTestResult = false
    @State private var testResultMessage = ""
    @State private var testResultIsSuccess = false
    
    var body: some View {
        VStack(spacing: 30) {
            // Header section
            VStack(spacing: 16) {
                // App icon placeholder - using weather symbol
                Image(systemName: "cloud.sun.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(
                        .linearGradient(
                            colors: [.blue, .cyan],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                VStack(spacing: 8) {
                    Text("PurpleAir LAN")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("Monitor your local PurpleAir sensor")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            
            // Configuration section
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Sensor Configuration")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Text("Enter the hostname or IP address of your PurpleAir sensor:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    // Hostname input field
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("purple.air or 192.168.1.100", text: $hostnameInput)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                            .onSubmit {
                                if !hostnameInput.isEmpty {
                                    testConnection()
                                }
                            }
                        
                        // Validation hint
                        if !hostnameInput.isEmpty && !isValidHostname(hostnameInput) {
                            Text("Please enter a valid hostname or IP address")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                }
                
                // Action buttons
                VStack(spacing: 12) {
                    // Test connection button
                    Button(action: testConnection) {
                        HStack {
                            if purpleAirService.isLoading {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Image(systemName: "network")
                            }
                            Text(purpleAirService.isLoading ? "Testing..." : "Test Connection")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            hostnameInput.isEmpty || !isValidHostname(hostnameInput) ? 
                            Color.gray : Color.blue
                        )
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    .disabled(hostnameInput.isEmpty || !isValidHostname(hostnameInput) || purpleAirService.isLoading)
                    
                    // Save and continue button
                    Button(action: saveConfiguration) {
                        HStack {
                            Image(systemName: "checkmark.circle")
                            Text("Save & Continue")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            testResultIsSuccess ? 
                            Color.green : Color.gray.opacity(0.3)
                        )
                        .foregroundColor(testResultIsSuccess ? .white : .gray)
                        .cornerRadius(10)
                    }
                    .disabled(!testResultIsSuccess)
                }
            }
            
            Spacer()
            
            // Help section
            VStack(spacing: 8) {
                Text("Need Help?")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text("Make sure your device is connected to the same network as your PurpleAir sensor.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(24)
        .navigationTitle("Setup")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Connection Test", isPresented: $showingTestResult) {
            Button("OK") { }
        } message: {
            Text(testResultMessage)
        }
        .onAppear {
            // Pre-fill with saved hostname if available
            hostnameInput = sensorHostname
        }
    }
}

// MARK: - Private Methods
private extension ConfigurationView {
    /// Test connection to the sensor
    func testConnection() {
        Task {
            await purpleAirService.fetchSensorData(from: hostnameInput)
            
            // Handle the result
            switch purpleAirService.state {
            case .loaded(let data):
                testResultIsSuccess = true
                testResultMessage = "✅ Connection successful!\n\nSensor: \(data.geo ?? "Unknown")\nLocation: \(data.place ?? "Unknown")"
                
            case .error(let error):
                testResultIsSuccess = false
                testResultMessage = "❌ Connection failed:\n\n\(error)"
                
            default:
                break
            }
            
            showingTestResult = true
        }
    }
    
    /// Save the configuration and proceed to dashboard
    func saveConfiguration() {
        sensorHostname = hostnameInput.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Validate hostname format
    func isValidHostname(_ hostname: String) -> Bool {
        let trimmed = hostname.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Check if empty
        guard !trimmed.isEmpty else { return false }
        
        // Simple validation - check if it looks like an IP or hostname
        let ipPattern = #"^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$"#
        let hostnamePattern = #"^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$|^[a-zA-Z0-9-]+$"#
        
        let ipRegex = try? NSRegularExpression(pattern: ipPattern)
        let hostnameRegex = try? NSRegularExpression(pattern: hostnamePattern)
        
        let range = NSRange(location: 0, length: trimmed.utf16.count)
        
        let isIP = ipRegex?.firstMatch(in: trimmed, options: [], range: range) != nil
        let isHostname = hostnameRegex?.firstMatch(in: trimmed, options: [], range: range) != nil
        
        return isIP || isHostname
    }
}

// MARK: - Preview
#Preview {
    NavigationView {
        ConfigurationView()
    }
}