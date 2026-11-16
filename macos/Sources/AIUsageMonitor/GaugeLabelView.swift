import SwiftUI

/// Colors mirror `ui/icons.py`: green at ≥50% remaining, amber 20–49%,
/// red below 20%, gray when no live data is available.
enum GaugePalette {
    static func color(for state: String) -> Color {
        switch state {
        case "normal": Color(red: 0x22 / 255, green: 0xA4 / 255, blue: 0x47 / 255)
        case "warning": Color(red: 0xE0 / 255, green: 0x9B / 255, blue: 0x16 / 255)
        case "critical": Color(red: 0xD4 / 255, green: 0x37 / 255, blue: 0x32 / 255)
        default: Color(white: 0.45)
        }
    }

    static func cgColor(for state: String) -> CGColor {
        switch state {
        case "normal": CGColor(red: 0x22 / 255, green: 0xA4 / 255, blue: 0x47 / 255, alpha: 1)
        case "warning": CGColor(red: 0xE0 / 255, green: 0x9B / 255, blue: 0x16 / 255, alpha: 1)
        case "critical": CGColor(red: 0xD4 / 255, green: 0x37 / 255, blue: 0x32 / 255, alpha: 1)
        default: CGColor(red: 0.45, green: 0.45, blue: 0.45, alpha: 1)
        }
    }
}

/// The compact menu-bar gauge: a colored ring showing the lowest live
/// remaining percentage, plus a text readout.
struct GaugeLabelView: View {
    let state: String
    let remaining: Double?

    var body: some View {
        HStack(spacing: 3) {
            // SwiftUI shape strokes render monochrome in the menu bar on
            // recent macOS versions; a non-template NSImage keeps its
            // colors, so the ring is drawn through GaugeIconRenderer.
            Image(nsImage: GaugeIconRenderer.image(state: state, remaining: remaining))
                .frame(width: 16, height: 16)
            Text(percentText)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .monospacedDigit()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var percentText: String {
        if let remaining {
            "\(Int(remaining.rounded()))%"
        } else {
            "—"
        }
    }

    private var accessibilityText: String {
        if let remaining {
            "AI Usage Monitor: \(Int(remaining.rounded())) percent remaining"
        } else {
            "AI Usage Monitor: no live usage data"
        }
    }
}
