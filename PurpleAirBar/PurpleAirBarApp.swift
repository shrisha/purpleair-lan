import SwiftUI
import PurpleAirKit

@main
struct PurpleAirBarApp: App {
    var body: some Scene {
        MenuBarExtra {
            Text("PurpleAir Bar — placeholder")
                .padding()
        } label: {
            Image(systemName: "aqi.medium")
        }
        .menuBarExtraStyle(.window)
    }
}
