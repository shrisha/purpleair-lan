import SwiftUI
import AppKit
import PurpleAirKit

/// The always-visible part. Reachable: pre-tinted EPA-colored dot + AQI number
/// (SwiftUI menu bar labels force template rendering, so color must arrive as a
/// non-template NSImage). Unreachable: dim template ghost so Quit stays reachable.
struct MenuBarLabel: View {
    @ObservedObject private var monitor = SensorMonitor.shared

    var body: some View {
        if monitor.phase == .home, let reading = monitor.lastData?.airQualityReading {
            HStack(spacing: 4) {
                Image(nsImage: StatusDot.image(for: reading.category))
                Text("\(reading.aqi)")
                    .monospacedDigit()
            }
        } else {
            Image(nsImage: StatusDot.ghost)
        }
    }
}

enum StatusDot {
    private static var cache: [AQICategory: NSImage] = [:]

    /// 9 pt circle filled with the EPA category color, hairline dark ring for
    /// contrast on Tahoe's transparent menu bar. Non-template on purpose.
    static func image(for category: AQICategory) -> NSImage {
        if let cached = cache[category] { return cached }
        let image = NSImage(size: NSSize(width: 9, height: 9), flipped: false) { rect in
            let inset = rect.insetBy(dx: 0.5, dy: 0.5)
            NSColor(category.epaColor).setFill()
            NSBezierPath(ovalIn: inset).fill()
            NSColor.black.withAlphaComponent(0.25).setStroke()
            let ring = NSBezierPath(ovalIn: inset)
            ring.lineWidth = 0.5
            ring.stroke()
            return true
        }
        image.isTemplate = false
        cache[category] = image
        return image
    }

    /// Dim template glyph: template + alpha keeps the system's automatic
    /// black/white flipping while reading as "asleep".
    static let ghost: NSImage = {
        let symbol = NSImage(systemSymbolName: "aqi.medium", accessibilityDescription: "PurpleAir sensor unreachable")!
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 13, weight: .regular))!
        let image = NSImage(size: symbol.size, flipped: false) { rect in
            symbol.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 0.45)
            return true
        }
        image.isTemplate = true
        return image
    }()
}
