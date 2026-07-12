import SwiftUI
import ServiceManagement
import AppKit
import PurpleAirKit

/// 340 pt living-wallpaper panel. Exists only while open — the scene's
/// TimelineView animates for free and tears down on close.
struct PanelView: View {
    @ObservedObject private var monitor = SensorMonitor.shared
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var editingHostname = false
    @State private var hostnameDraft = ""
    @State private var sceneVisible = false

    var body: some View {
        ZStack {
            Group {
                if sceneVisible {
                    AmbientSceneView(
                        aqi: monitor.phase == .home ? Double(monitor.lastData?.airQualityReading?.aqi ?? 25) : 25,
                        pm25: monitor.phase == .home ? (monitor.lastData?.airQualityReading?.correctedPM25 ?? 0) : 0,
                        latitude: monitor.lastData?.latitude,
                        longitude: monitor.lastData?.longitude
                    )
                } else {
                    Color(red: 0.03, green: 0.04, blue: 0.08) // hidden window: render nothing animated
                }
            }
            .overlay(Color.black.opacity(monitor.phase == .home ? 0 : 0.2))

            VStack(spacing: 0) {
                if monitor.phase == .home, let data = monitor.lastData {
                    homeContent(data: data)
                } else {
                    awayContent
                }
                footer
            }
        }
        .frame(width: 340, height: 440)
        .environment(\.colorScheme, .dark)
        .background(WindowVisibilityObserver { visible in
            sceneVisible = visible
            if visible { monitor.panelOpened() }   // re-fires on every reopen, unlike onAppear
        })
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    // MARK: home

    private func homeContent(data: PurpleAirData) -> some View {
        VStack(spacing: 2) {
            Spacer(minLength: 20)

            Text(stationCaption(data: data))
                .font(.system(size: 10.5, weight: .semibold))
                .kerning(1.5)
                .foregroundStyle(.white.opacity(0.62))

            if let reading = data.airQualityReading {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("\(reading.aqi)")
                        .font(.system(size: 64, weight: .thin))
                        .contentTransition(.numericText())
                    Text("AQI")
                        .font(.system(size: 15, weight: .light))
                        .foregroundStyle(.white.opacity(0.62))
                }
                .padding(.leading, 18) // optical centering against the unit
                Text(reading.category.name)
                    .font(.system(size: 15, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.9))
            }

            if let temp = data.displayTemperatureF {
                HStack(spacing: 0) {
                    Text("\(Int(temp.rounded()))°")
                        .font(.system(size: 13, weight: .medium))
                    if let dew = data.displayDewPointF {
                        Text(" · Dew point \(Int(dew.rounded()))°")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                .padding(.top, 2)
            }

            Spacer(minLength: 14)

            if let reading = data.airQualityReading {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(reading.correctedPM25, format: .number.precision(.fractionLength(1)))
                            .font(.system(size: 20, weight: .medium))
                            .monospacedDigit()
                        Text("µg/m³ · EPA corrected")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.62))
                    }
                    AQIScaleBar(aqi: reading.aqi)
                    Text(reading.category.healthGuidance)
                        .font(.system(size: 11))
                        .lineSpacing(2)
                        .foregroundStyle(.white.opacity(0.72))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 16)
            }

            Rectangle()
                .fill(.white.opacity(0.12))
                .frame(height: 0.5)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

            HStack(alignment: .top) {
                if let humidity = data.displayHumidityPct {
                    statColumn(
                        label: "HUMIDITY",
                        value: "\(Int(humidity.rounded())) %",
                        detail: AirQuality.comfortDescription(humidity: humidity)
                    )
                }
                Spacer()
                if let pressure = data.pressure {
                    statColumn(
                        label: "PRESSURE",
                        value: String(format: "%.1f hPa", pressure),
                        detail: nil,
                        trailingSymbol: monitor.pressureStore.trend?.symbolName ?? "minus"
                    )
                }
            }
            .padding(.horizontal, 24)

            Spacer(minLength: 10)
        }
        .foregroundStyle(.white)
    }

    private func stationCaption(data: PurpleAirData) -> String {
        [data.place?.uppercased(), data.geo?.uppercased()]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    private func statColumn(label: String, value: String, detail: String?, trailingSymbol: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .kerning(0.8)
                .foregroundStyle(.white.opacity(0.62))
            HStack(spacing: 4) {
                Text(value)
                    .font(.system(size: 13, weight: .medium))
                    .monospacedDigit()
                if let trailingSymbol {
                    Image(systemName: trailingSymbol)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
            if let detail {
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }

    // MARK: away

    private var awayContent: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "aqi.medium")
                .font(.system(size: 34))
                .foregroundStyle(.white.opacity(0.5))
            Text("Looking for your PurpleAir")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
            Text("It appears automatically when this Mac can reach \(monitor.hostname).")
                .font(.system(size: 11.5))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            if let last = monitor.lastUpdate, let aqi = monitor.lastData?.airQualityReading?.aqi {
                Text("Last seen \(last.formatted(date: .omitted, time: .shortened)) · AQI \(aqi)")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.45))
            }
            Spacer()
        }
    }

    // MARK: footer

    private var footer: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(.white.opacity(0.12))
                .frame(height: 0.5)
            HStack(spacing: 10) {
                if editingHostname {
                    TextField("hostname or IP", text: $hostnameDraft)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11))
                        .onSubmit(saveHostname)
                    Button("Save", action: saveHostname)
                        .font(.system(size: 11))
                    Button("Cancel") { editingHostname = false }
                        .font(.system(size: 11))
                } else {
                    Text(footerCaption)
                        .font(.system(size: 10.5))
                        .foregroundStyle(footerColor)
                        .lineLimit(1)
                    Spacer()
                    Button {
                        if let url = URL(string: "http://\(monitor.hostname)/") {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        Image(systemName: "safari")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.7))
                    .help("Open the sensor's page")

                    Menu {
                        Toggle("Launch at Login", isOn: $launchAtLogin)
                        Button("Change Sensor Address…") {
                            hostnameDraft = monitor.hostname
                            editingHostname = true
                        }
                        Divider()
                        Button("Quit PurpleAir Bar") { NSApp.terminate(nil) }
                            .keyboardShortcut("q")
                    } label: {
                        Image(systemName: "gearshape.fill")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .foregroundStyle(.white.opacity(0.7))
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 30)
        }
        .onChange(of: launchAtLogin) { _, enabled in
            do {
                if enabled { try SMAppService.mainApp.register() }
                else { try SMAppService.mainApp.unregister() }
            } catch {
                launchAtLogin = SMAppService.mainApp.status == .enabled
            }
        }
    }

    private var footerCaption: String {
        let time = monitor.lastUpdate?.formatted(date: .omitted, time: .shortened) ?? "—"
        switch (monitor.phase, monitor.isStale) {
        case (.home, true):
            return "Reconnecting… last updated \(time)"
        case (.home, false):
            let agreement = monitor.lastData?.airQualityReading?.channelsAgree == false
                ? "sensor channels disagree" : "sensor channels agree"
            return "Updated \(time) · \(agreement)"
        default:
            return "Sensor unreachable"
        }
    }

    private var footerColor: Color {
        monitor.phase == .home && monitor.isStale
            ? Color(red: 1, green: 0.72, blue: 0.3).opacity(0.8)
            : .white.opacity(0.45)
    }

    private func saveHostname() {
        let trimmed = hostnameDraft
            .replacingOccurrences(of: "http://", with: "")
            .replacingOccurrences(of: "https://", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        monitor.hostname = trimmed
        editingHostname = false
        monitor.hostnameDidChange()
    }
}

/// MenuBarExtra's window is hidden, not destroyed, when the panel closes —
/// report its occlusion so the scene can stop rendering entirely.
private struct WindowVisibilityObserver: NSViewRepresentable {
    let onChange: (Bool) -> Void

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ nsView: TrackingView, context: Context) {
        nsView.onChange = onChange
    }

    final class TrackingView: NSView {
        var onChange: ((Bool) -> Void)?
        private var observation: NSObjectProtocol?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let observation { NotificationCenter.default.removeObserver(observation) }
            observation = nil
            guard let window else {
                onChange?(false)
                return
            }
            onChange?(window.occlusionState.contains(.visible))
            observation = NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification,
                object: window,
                queue: .main
            ) { [weak self] note in
                guard let window = note.object as? NSWindow else { return }
                self?.onChange?(window.occlusionState.contains(.visible))
            }
        }

        deinit {
            if let observation { NotificationCenter.default.removeObserver(observation) }
        }
    }
}
