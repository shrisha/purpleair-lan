import SwiftUI
import PurpleAirKit

@main
struct PurpleAirBarApp: App {
    init() {
        SensorMonitor.shared.start()
    }

    var body: some Scene {
        MenuBarExtra {
            Text("Panel arrives in the next task")
                .padding()
        } label: {
            MenuBarLabel()
        }
        .menuBarExtraStyle(.window)
    }
}
