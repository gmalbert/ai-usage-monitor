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
}

/// The compact menu-bar gauge: a ring showing the lowest live remaining
/// percentage, plus a text readout.
struct GaugeLabelView: View {
    let state: String
    let remaining: Double?

    var body: some View {
        HStack(spacing: 3) {
            gauge
                .frame(width: 15, height: 15)
            Text(percentText)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .monospacedDigit()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var gauge: some View {
        ZStack {
            Circle()
                .stroke(.quaternary, lineWidth: 2.4)
            if let remaining {
                Circle()
                    .trim(from: 0, to: max(0.01, remaining / 100))
                    .stroke(GaugePalette.color(for: state), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            } else {
                Circle()
                    .stroke(GaugePalette.color(for: state), style: StrokeStyle(lineWidth: 2.4, lineCap: .round, dash: [2, 2]))
            }
        }
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
