import Foundation
import Combine

// MARK: - API Service States
enum APIState {
    case idle
    case loading
    case loaded(PurpleAirData)
    case error(String)
}

// MARK: - PurpleAir API Service
@MainActor
class PurpleAirService: ObservableObject {
    // Published state for SwiftUI binding
    @Published var state: APIState = .idle
    
    // URLSession for network requests
    private let urlSession: URLSession
    
    // JSON decoder configured for PurpleAir API
    private let decoder: JSONDecoder
    
    // Initialize service with optional custom URLSession (useful for testing)
    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
        
        // Configure JSON decoder
        self.decoder = JSONDecoder()
        // PurpleAir API doesn't use standard date formats, so we handle dates as strings
    }
    
    /// Fetch sensor data from the specified hostname
    /// - Parameter hostname: The IP address or hostname of the PurpleAir sensor
    func fetchSensorData(from hostname: String) async {
        // Update state to loading
        state = .loading
        
        // Validate and construct the URL
        guard let url = constructAPIURL(hostname: hostname) else {
            state = .error("Invalid hostname or IP address")
            return
        }
        
        // Debug: Print the URL being used
        print("🌐 Attempting to fetch from URL: \(url.absoluteString)")
        
        do {
            // Make the network request
            let (data, response) = try await urlSession.data(from: url)
            
            // Validate HTTP response
            guard let httpResponse = response as? HTTPURLResponse else {
                state = .error("Invalid response from sensor")
                return
            }
            
            // Check for successful status code
            guard 200...299 ~= httpResponse.statusCode else {
                state = .error("Sensor responded with status code: \(httpResponse.statusCode)")
                return
            }
            
            // Decode the JSON response
            let sensorData = try decoder.decode(PurpleAirData.self, from: data)
            
            // Update state with successful data
            state = .loaded(sensorData)
            
        } catch let decodingError as DecodingError {
            // Handle JSON decoding errors
            let errorMessage = handleDecodingError(decodingError)
            state = .error("Data parsing error: \(errorMessage)")
            
        } catch {
            // Debug: Print the actual error
            print("❌ Network error for \(url.absoluteString): \(error)")
            
            // Handle network errors
            if let urlError = error as? URLError {
                print("❌ URLError code: \(urlError.code.rawValue), description: \(urlError.localizedDescription)")
                state = .error(handleURLError(urlError))
            } else {
                state = .error("Network error: \(error.localizedDescription)")
            }
        }
    }
    
    /// Refresh the current sensor data (convenience method)
    func refresh() async {
        // Only refresh if we have previously loaded data
        if case .loaded = state {
            // Extract hostname from current state and fetch again
            // For now, we'll need to pass the hostname again
            // In a future version, we could store the hostname
        }
    }
}

// MARK: - Private Helper Methods
private extension PurpleAirService {
    /// Construct the API URL from hostname
    func constructAPIURL(hostname: String) -> URL? {
        // Clean the hostname (remove any protocol prefixes)
        let cleanHostname = hostname
            .replacingOccurrences(of: "http://", with: "")
            .replacingOccurrences(of: "https://", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Validate that we have a non-empty hostname
        guard !cleanHostname.isEmpty else { return nil }
        
        // Firmware's 2-minute average — the right smoothing for an ambient display
        let urlString = "http://\(cleanHostname)/json"
        return URL(string: urlString)
    }
    
    /// Handle URLError with user-friendly messages
    func handleURLError(_ error: URLError) -> String {
        switch error.code {
        case .notConnectedToInternet:
            return "No internet connection"
        case .cannotFindHost:
            return "Cannot find sensor at this address"
        case .timedOut:
            return "Connection timed out"
        case .cannotConnectToHost:
            return "Cannot connect to sensor"
        case .networkConnectionLost:
            return "Network connection lost"
        default:
            return "Connection error: \(error.localizedDescription)"
        }
    }
    
    /// Handle JSON decoding errors with helpful messages
    func handleDecodingError(_ error: DecodingError) -> String {
        switch error {
        case .keyNotFound(let key, _):
            return "Missing expected data field: \(key.stringValue)"
        case .typeMismatch(let type, let context):
            return "Data format error for field: \(context.codingPath.last?.stringValue ?? "unknown")"
        case .valueNotFound(let type, let context):
            return "Missing value for: \(context.codingPath.last?.stringValue ?? "unknown field")"
        case .dataCorrupted(let context):
            return "Corrupted data: \(context.debugDescription)"
        @unknown default:
            return "Unknown data parsing error"
        }
    }
}

// MARK: - Convenience Methods
extension PurpleAirService {
    /// Check if we have valid sensor data
    var hasData: Bool {
        if case .loaded = state {
            return true
        }
        return false
    }
    
    /// Get current sensor data if available
    var currentData: PurpleAirData? {
        if case .loaded(let data) = state {
            return data
        }
        return nil
    }
    
    /// Check if currently loading
    var isLoading: Bool {
        if case .loading = state {
            return true
        }
        return false
    }
    
    /// Get current error message if in error state
    var errorMessage: String? {
        if case .error(let message) = state {
            return message
        }
        return nil
    }
}