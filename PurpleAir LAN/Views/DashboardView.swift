// PurpleAir LAN/Views/DashboardView.swift
import SwiftUI

struct DashboardView: View {
    let hostname: String

    @StateObject private var purpleAirService = PurpleAirService()
    @State private var showingConfiguration = false
    @State private var refreshTimer: Timer?
    @State private var lastUpdateTime: Date?
    @State private var lastData: PurpleAirData?
    @State private var refreshFailed = false
    @State private var chromeVisible = true
    @State private var chromeFadeTask: Task<Void, Never>?
    @Environment(\.scenePhase) private var scenePhase

    private let pressureStore = PressureHistoryStore()

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topTrailing) {
                AmbientSceneView(
                    aqi: Double(lastData?.airQualityReading?.aqi ?? 25),
                    pm25: lastData?.airQualityReading?.correctedPM25 ?? 0,
                    latitude: lastData?.latitude,
                    longitude: lastData?.longitude
                )
                .overlay(Color.black.opacity(refreshFailed ? 0.1 : 0))

                ScrollView {
                    mainContent
                        .frame(minHeight: geo.size.height)
                }
                .refreshable { await refresh() }

                chrome
            }
        }
        .environment(\.colorScheme, .dark)
        .persistentSystemOverlays(.hidden)
        .toolbar(.hidden, for: .navigationBar)
        .contentShape(Rectangle())
        .onTapGesture { showChrome() }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            Task { await refresh() }
            startAutoRefresh()
            scheduleChromeFade()
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            stopAutoRefresh()
            chromeFadeTask?.cancel()
        }
        .onChange(of: scenePhase) { _, phase in
            UIApplication.shared.isIdleTimerDisabled = (phase == .active)
        }
        .sheet(isPresented: $showingConfiguration) {
            NavigationView {
                ConfigurationView()
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button("Cancel") { showingConfiguration = false }
                        }
                    }
            }
        }
    }

    // MARK: content

    @ViewBuilder private var mainContent: some View {
        if let data = lastData {
            loadedContent(data: data)
        } else if case .error(let message) = purpleAirService.state {
            errorContent(message: message)
        } else {
            loadingContent
        }
    }

    private func loadedContent(data: PurpleAirData) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 64)
            hero(data: data)
            Spacer(minLength: 24)
            cards(data: data)
            footerCaption(data: data)
                .padding(.top, 12)
                .padding(.bottom, 18)
        }
        .padding(.horizontal, 16)
    }

    private func hero(data: PurpleAirData) -> some View {
        VStack(spacing: 2) {
            if let place = data.place, !place.isEmpty {
                Text(place.uppercased())
                    .font(.system(size: 12, weight: .semibold))
                    .kerning(1.7)
                    .foregroundStyle(.white.opacity(0.62))
            }
            if let station = data.geo {
                Text(station)
                    .font(.system(size: 27))
            }
            if let reading = data.airQualityReading {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("\(reading.aqi)")
                        .font(.system(size: 112, weight: .thin))
                        .contentTransition(.numericText())
                    Text("AQI")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(.white.opacity(0.62))
                }
                .padding(.leading, 30) // optical centering against the unit label
                Text(reading.category.name)
                    .font(.system(size: 21, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.9))
            }
            if let temp = data.displayTemperatureF {
                HStack(spacing: 0) {
                    Text("\(Int(temp.rounded()))°")
                        .font(.system(size: 20, weight: .medium))
                    if let dew = data.displayDewPointF {
                        Text(" · Dew point \(Int(dew.rounded()))°")
                            .font(.system(size: 20))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                .padding(.top, 4)
            }
        }
        .foregroundStyle(.white)
    }

    private func cards(data: PurpleAirData) -> some View {
        VStack(spacing: 8) {
            if let reading = data.airQualityReading {
                PMCard(reading: reading)
            }
            HStack(alignment: .top, spacing: 8) {
                if let humidity = data.displayHumidityPct, let dew = data.displayDewPointF {
                    HumidityCard(humidityPct: humidity, dewPointF: dew)
                }
                if let pressure = data.pressure {
                    PressureCard(hPa: pressure, trend: pressureStore.trend)
                }
            }
        }
    }

    private func footerCaption(data: PurpleAirData) -> some View {
        Group {
            if refreshFailed {
                Text("Reconnecting… last updated \(lastUpdateTime.map { timeFormatter.string(from: $0) } ?? "—")")
                    .foregroundStyle(Color(red: 1, green: 0.72, blue: 0.3).opacity(0.8))
            } else {
                let agreement = data.airQualityReading?.channelsAgree == false
                    ? "sensor channels disagree" : "sensor channels agree"
                Text("Updated \(lastUpdateTime.map { timeFormatter.string(from: $0) } ?? "—") · \(agreement)")
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
        .font(.system(size: 11.5))
    }

    private var loadingContent: some View {
        VStack(spacing: 30) {
            WeatherSpinner()
            Text("Checking sensor…")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.8))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorContent(message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 52))
                .foregroundStyle(.white.opacity(0.7))
            Text("Connection Error")
                .font(.headline)
                .foregroundStyle(.white)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Try Again") { Task { await refresh() } }
                .buttonStyle(.borderedProminent)
                .tint(.white.opacity(0.25))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: chrome

    private var chrome: some View {
        HStack(spacing: 14) {
            Button { Task { await refresh() } } label: {
                Image(systemName: "arrow.clockwise")
            }
            .disabled(purpleAirService.isLoading)
            Button { showingConfiguration = true } label: {
                Image(systemName: "gearshape")
            }
        }
        .font(.system(size: 17, weight: .medium))
        .foregroundStyle(.white.opacity(0.9))
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(.top, 8)
        .padding(.trailing, 16)
        .opacity(chromeVisible ? 1 : 0)
    }

    private func showChrome() {
        withAnimation(.easeIn(duration: 0.25)) { chromeVisible = true }
        scheduleChromeFade()
    }

    private func scheduleChromeFade() {
        chromeFadeTask?.cancel()
        chromeFadeTask = Task {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 2)) { chromeVisible = false }
        }
    }

    // MARK: data

    private func refresh() async {
        guard !purpleAirService.isLoading else { return }
        await purpleAirService.fetchSensorData(from: hostname)
        switch purpleAirService.state {
        case .loaded(let data):
            withAnimation(.easeInOut(duration: 1)) {
                lastData = data
                refreshFailed = false
            }
            lastUpdateTime = Date()
            if let pressure = data.pressure {
                pressureStore.record(pressure)
            }
        case .error:
            // keep showing cached data; surface the failure in the footer
            if lastData != nil { refreshFailed = true }
        default:
            break
        }
    }

    private func startAutoRefresh() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { _ in
            Task { @MainActor in
                if !purpleAirService.isLoading {
                    await refresh()
                }
            }
        }
    }

    private func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }
}

#Preview {
    DashboardView(hostname: "purpleair.lan")
}
