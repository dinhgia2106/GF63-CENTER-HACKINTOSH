import SwiftUI
import WidgetKit

struct R3StatusEntry: TimelineEntry {
    let date: Date
    let snapshot: HardwareSnapshot
}

struct R3StatusProvider: TimelineProvider {
    func placeholder(in context: Context) -> R3StatusEntry {
        R3StatusEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (R3StatusEntry) -> Void) {
        completion(R3StatusEntry(date: .now, snapshot: SharedSnapshotStore.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<R3StatusEntry>) -> Void) {
        let entry = R3StatusEntry(date: .now, snapshot: SharedSnapshotStore.load())
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(60))))
    }
}

struct R3StatusWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: R3StatusEntry

    var body: some View {
        switch family {
        case .systemSmall: small
        default: medium
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "fan.fill").foregroundStyle(.red)
                Spacer()
                Text("R3").font(.caption.bold()).foregroundStyle(.secondary)
            }
            Spacer()
            Text(temperatureText)
                .font(.system(size: 39, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.7)
            Text("CPU • \(entry.snapshot.cpuLoad.percentText) load")
                .font(.caption)
                .foregroundStyle(.secondary)
            Gauge(value: min((entry.snapshot.cpuTemperature ?? 0) / 100, 1)) { EmptyView() }
                .gaugeStyle(.accessoryLinearCapacity)
                .tint(temperatureTint)
        }
        .containerBackground(for: .widget) { widgetBackground }
    }

    private var medium: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Label("R3 CONTROL", systemImage: "fan.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.red)
                Spacer()
                Text(temperatureText)
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                Text("MSI GF63 Series")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Divider()
            VStack(spacing: 12) {
                widgetMetric("CPU", entry.snapshot.cpuLoad.percentText, "cpu")
                widgetMetric("POWER", powerText, "bolt.fill")
                widgetMetric("FAN", fanText, "fan")
                widgetMetric("BAT", batteryText, "battery.75percent")
            }
        }
        .containerBackground(for: .widget) { widgetBackground }
    }

    private func widgetMetric(_ title: String, _ value: String, _ symbol: String) -> some View {
        HStack {
            Image(systemName: symbol).foregroundStyle(.secondary).frame(width: 18)
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.caption.bold().monospacedDigit())
        }
    }

    private var widgetBackground: some View {
        LinearGradient(
            colors: [Color(nsColor: .windowBackgroundColor), .red.opacity(0.10)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var temperatureText: String {
        entry.snapshot.cpuTemperature.map { "\(Int($0.rounded()))°C" } ?? "—"
    }

    private var powerText: String {
        entry.snapshot.cpuPackagePower.map { String(format: "%.1f W", $0) } ?? "—"
    }

    private var fanText: String {
        if let rpm = entry.snapshot.fanRPM { return "\(Int(rpm))" }
        if let percent = entry.snapshot.fanPercent { return "\(Int(percent))%" }
        return "N/A"
    }

    private var batteryText: String {
        entry.snapshot.batteryPercent?.percentText ?? "—"
    }

    private var temperatureTint: Color {
        guard let value = entry.snapshot.cpuTemperature else { return .secondary }
        if value >= 90 { return .red }
        if value >= 75 { return .orange }
        return .green
    }
}

struct R3StatusWidget: Widget {
    let kind = "R3StatusWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: R3StatusProvider()) { entry in
            R3StatusWidgetView(entry: entry)
        }
        .configurationDisplayName("R3 System Status")
        .description("CPU temperature, load, package power, fan and battery status for compatible GF63 systems.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct R3ControlWidgetBundle: WidgetBundle {
    var body: some Widget { R3StatusWidget() }
}
