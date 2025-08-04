import SwiftUI

@main
struct PurpleAirLANApp: App {
    // UserDefaults key for storing the sensor hostname/IP
    @AppStorage("sensorHostname") private var sensorHostname = ""
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.light) // Light mode for better visibility of data tiles
        }
    }
}