import WidgetKit
import SwiftUI

@main
struct UsageWidgetBundle: WidgetBundle {
    var body: some Widget {
        UsageGaugeWidget()
        CommandCodeGaugeWidget()
        CodexGaugeWidget()
        OpenCodeGaugeWidget()
        UsageProvidersWidget()
    }
}

#Preview("Gauge", as: .systemSmall) {
    UsageGaugeWidget()
} timelineProvider: {
    SnapshotTimelineProvider()
}

#Preview("Providers", as: .systemMedium) {
    UsageProvidersWidget()
} timelineProvider: {
    SnapshotTimelineProvider()
}
