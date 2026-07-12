import SwiftUI

struct ContentView: View {
    // Store the sensor hostname in UserDefaults for persistence
    @AppStorage("sensorHostname") private var sensorHostname = ""
    
    var body: some View {
        NavigationView {
            if sensorHostname.isEmpty {
                // Show configuration view if no hostname is set
                ConfigurationView()
            } else {
                // Show dashboard with sensor data
                DashboardView(hostname: sensorHostname)
                    .id(sensorHostname)
            }
        }
        .navigationViewStyle(StackNavigationViewStyle()) // Prevents split view on iPad
    }
}