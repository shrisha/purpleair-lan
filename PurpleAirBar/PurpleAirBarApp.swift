import SwiftUI
import PurpleAirKit

@main
struct PurpleAirBarApp: App {
    init() {
        SensorMonitor.shared.start()
    }

    var body: some Scene {
        MenuBarExtra {
            PanelView()
        } label: {
            MenuBarLabel()
        }
        .menuBarExtraStyle(.window)
    }
}
