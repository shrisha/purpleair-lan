# PurpleAir LAN

A native iOS app for monitoring a PurpleAir sensor on your network, providing real-time air quality data without requiring internet connectivity.

## Features

- **Local Network Monitoring**: Connect directly to PurpleAir sensors on your local network
- **Real-time Data**: Monitor temperature, humidity, pressure, and air quality index (AQI)
- **Auto-refresh**: Sensor data updates automatically every 30 seconds
- **Visual Indicators**: Color-coded tiles for quick understanding of environmental conditions
- **Persistent Configuration**: Save your sensor hostname/IP for quick access
- **Pull-to-refresh**: Manual refresh with pull gesture
- **Error Handling**: Clear error messages and retry options

## Screenshots

The app features a clean, modern interface with:
- **Setup Screen**: Easy sensor configuration with connection testing
- **Dashboard**: Real-time environmental data in an intuitive grid layout
- **Status Indicators**: Connection status and last update timestamps

## Requirements

- iOS 15.0+
- Xcode 14.0+
- Swift 5.7+
- PurpleAir sensor on your local network

## Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/yourusername/PurpleAir-LAN.git
   cd PurpleAir-LAN
   ```

2. Open `PurpleAir LAN.xcodeproj` in Xcode

3. Build and run the project on your iOS device or simulator

## Configuration

### Finding Your PurpleAir Sensor

1. Ensure your iOS device is connected to the same Wi-Fi network as your PurpleAir sensor
2. Find your sensor's local IP address:
   - Check your router's admin panel for connected devices
   - Look for devices named "PurpleAir" or similar
   - Common IP formats: `192.168.1.xxx` or `10.0.0.xxx`

### Setting Up the App

1. Launch the app
2. Enter your sensor's hostname or IP address (e.g., `192.168.1.100` or `purple.air`)
3. Tap "Test Connection" to verify connectivity
4. Tap "Save & Continue" to proceed to the dashboard

## Data Display

The app displays four key environmental metrics:

- **Temperature**: Current temperature in Fahrenheit with color coding
- **Humidity**: Relative humidity percentage with comfort indicators
- **Pressure**: Atmospheric pressure in millibars
- **Air Quality**: AQI value with EPA standard color coding and quality descriptions

### AQI Quality Levels

- **0-50 (Green)**: Good
- **51-100 (Yellow)**: Moderate
- **101-150 (Orange)**: Unhealthy for Sensitive Groups
- **151-200 (Red)**: Unhealthy
- **201-300 (Purple)**: Very Unhealthy
- **301+ (Maroon)**: Hazardous

## Architecture

The app follows the MVVM pattern with SwiftUI:

### Core Components

- **ContentView**: Main navigation controller
- **ConfigurationView**: Sensor setup and connection testing
- **DashboardView**: Real-time data display
- **PurpleAirService**: Network service for API communication
- **PurpleAirData**: Data model with display formatting

### Key Features

- **@AppStorage**: Persistent sensor configuration
- **Async/Await**: Modern networking with proper error handling
- **Timer-based Refresh**: Automatic data updates
- **State Management**: Reactive UI updates with SwiftUI

## API Integration

The app communicates with PurpleAir sensors using their local JSON API:

```
http://[sensor-ip]/json?live=true
```

### Response Format

The sensor returns JSON data including:
- Environmental readings (temperature, humidity, pressure)
- Air quality measurements (PM2.5, AQI)
- Sensor metadata (location, version, connectivity)

## Troubleshooting

### Common Issues

**"Cannot find sensor at this address"**
- Verify the IP address or hostname is correct
- Ensure your device is on the same network as the sensor
- Check that the sensor is powered on and connected to Wi-Fi

**"Connection timed out"**
- Sensor may be busy or unresponsive
- Try again after a few seconds
- Verify network connectivity

**"Data parsing error"**
- Sensor may be returning unexpected data format
- Try refreshing the connection
- Ensure you're connecting to a PurpleAir sensor

### Network Requirements

- Both your iOS device and PurpleAir sensor must be on the same local network
- No internet connection required for monitoring (local network only)
- Router must allow communication between devices (check AP isolation settings)

## Development

### Project Structure

```
PurpleAir LAN/
├── PurpleAirLANApp.swift          # App entry point
├── ContentView.swift              # Main navigation
├── Views/
│   ├── ConfigurationView.swift    # Sensor setup
│   ├── DashboardView.swift        # Data display
│   └── Components/
│       ├── DataTile.swift         # Individual data tiles
│       └── WeatherSpinner.swift   # Loading animation
├── Models/
│   └── PurpleAirData.swift        # Data model
└── Services/
    └── PurpleAirService.swift     # Network service
```

### Building

1. Open the project in Xcode
2. Select your target device or simulator
3. Press `Cmd+R` to build and run

### Testing

- Use the connection test feature in the app
- Verify sensor connectivity before deploying
- Test with different network conditions

## Privacy

This app:
- Only connects to sensors on your local network
- Does not send data to external servers
- Stores only the sensor hostname/IP locally on your device
- Does not collect or transmit personal information

## License

This project is open source. See the LICENSE file for details.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## Support

For issues or questions:
- Check the troubleshooting section above
- Review PurpleAir sensor documentation
- Ensure proper network configuration

---

**Note**: This app is designed for local network monitoring only. It does not replace the official PurpleAir app for internet-based monitoring or sensor management.
