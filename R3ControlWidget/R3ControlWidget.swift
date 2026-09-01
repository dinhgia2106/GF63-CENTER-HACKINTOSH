import SwiftUI
import WidgetKit

struct R3StatusEntry: TimelineEntry {
    let date: Date
    let snapshot: HardwareSnapshot?
}

struct R3StatusProvider: TimelineProvider {
    func placeholder(in context: Context) -> R3StatusEntry {
        R3StatusEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (R3StatusEntry) -> Void) {
        let snapshot = context.isPreview ? HardwareSnapshot.placeholder : SharedSnapshotStore.load()
        completion(R3StatusEntry(date: .now, snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<R3StatusEntry>) -> Void) {
        let now = Date.now
        let snapshot = SharedSnapshotStore.load()
        var entries = [R3StatusEntry(date: now, snapshot: snapshot)]

        if let snapshot {
            let staleDate = snapshot.timestamp.addingTimeInterval(120)
            if staleDate > now {
                entries.append(R3StatusEntry(date: staleDate, snapshot: snapshot))
            }
        }

        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(60))))
    }
}

struct R3StatusWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: R3StatusEntry

    var body: some View {
        Group {
            if let snapshot = entry.snapshot {
                switch family {
                case .systemSmall: small(snapshot)
                case .systemLarge: large(snapshot)
                default: medium(snapshot)
                }
            } else {
                unavailable
            }
        }
        .containerBackground(for: .widget) { widgetBackground }
        .widgetURL(URL(string: "r3control://overview"))
    }

    private func small(_ snapshot: HardwareSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Image(systemName: "fan.fill")
                    .foregroundStyle(temperatureTint(snapshot.cpuTemperature))
                Spacer()
                freshnessBadge(snapshot)
            }
            Spacer()
            Text(temperatureText(snapshot))
                .font(.system(size: 39, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.7)
                .monospacedDigit()
            Text("\(performanceText(snapshot)) • Fan \(coolingModeText(snapshot))")
                .font(.caption)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(.primary)
            Text("\(snapshot.cpuLoad.percentText) load • \(fanText(snapshot))")
                .font(.caption2)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .foregroundStyle(.secondary)
            Gauge(value: normalizedTemperature(snapshot.cpuTemperature)) { EmptyView() }
                .gaugeStyle(.accessoryLinearCapacity)
                .tint(temperatureTint(snapshot.cpuTemperature))
        }
    }

    private func medium(_ snapshot: HardwareSnapshot) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Label("R3 CONTROL", systemImage: "fan.fill")
                    .font(.caption.bold())
                    .foregroundStyle(temperatureTint(snapshot.cpuTemperature))
                Spacer()
                Text(temperatureText(snapshot))
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("CPU TEMPERATURE")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                updatedLabel(snapshot)
            }
            Divider()
            VStack(spacing: 8) {
                widgetMetric("PERF", performanceText(snapshot), "speedometer")
                widgetMetric("FAN", coolingModeText(snapshot), "fan")
                widgetMetric("CPU", snapshot.cpuLoad.percentText, "cpu")
                widgetMetric("POWER", powerText(snapshot), "bolt.fill")
                widgetMetric("BAT", batteryText(snapshot), batterySymbol(snapshot))
            }
        }
    }

    private func large(_ snapshot: HardwareSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("R3 CONTROL", systemImage: "fan.fill")
                    .font(.headline.bold())
                    .foregroundStyle(temperatureTint(snapshot.cpuTemperature))
                Spacer()
                freshnessBadge(snapshot)
            }

            HStack(alignment: .center, spacing: 18) {
                ZStack {
                    Gauge(value: normalizedTemperature(snapshot.cpuTemperature)) { EmptyView() }
                        .gaugeStyle(.accessoryCircularCapacity)
                        .tint(temperatureTint(snapshot.cpuTemperature))
                        .scaleEffect(1.9)
                    Text(temperatureText(snapshot))
                        .font(.system(.title2, design: .rounded).bold())
                        .monospacedDigit()
                }
                .frame(width: 112, height: 112)

                VStack(spacing: 11) {
                    widgetMetric("PERFORMANCE", performanceText(snapshot), "speedometer")
                    widgetMetric("FAN MODE", coolingModeText(snapshot), "fan")
                    widgetMetric("FAN SPEED", fanText(snapshot), "gauge.with.dots.needle.50percent")
                    widgetMetric("CPU LOAD", snapshot.cpuLoad.percentText, "cpu")
                    widgetMetric("PACKAGE", powerText(snapshot), "bolt.fill")
                }
            }

            Divider()

            VStack(spacing: 12) {
                utilizationRow("Memory", used: snapshot.memoryUsed, total: snapshot.memoryTotal, tint: .cyan)
                utilizationRow("Storage", used: snapshot.diskUsed, total: snapshot.diskTotal, tint: .purple)
            }

            Spacer(minLength: 0)

            HStack {
                Label(
                    controlText(snapshot),
                    systemImage: snapshot.controlAvailability.isWritable ? "checkmark.shield.fill" : "lock.shield.fill"
                )
                .lineLimit(1)
                Spacer()
                updatedLabel(snapshot)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }

    private func widgetMetric(_ title: String, _ value: String, _ symbol: String) -> some View {
        HStack {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption.bold().monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }

    private func utilizationRow(_ title: String, used: UInt64, total: UInt64, tint: Color) -> some View {
        let fraction = total > 0 ? min(max(Double(used) / Double(total), 0), 1) : 0
        return VStack(spacing: 5) {
            HStack {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(fraction.percentText)
                    .font(.caption.bold().monospacedDigit())
            }
            ProgressView(value: fraction)
                .tint(tint)
        }
    }

    private var unavailable: some View {
        VStack(spacing: 10) {
            Image(systemName: "fan.badge.questionmark")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.secondary)
            Text("Open R3 Control")
                .font(.headline)
            Text("Launch the app once to show live hardware data.")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var widgetBackground: some View {
        LinearGradient(
            colors: [Color(nsColor: .windowBackgroundColor), .red.opacity(0.10)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func temperatureText(_ snapshot: HardwareSnapshot) -> String {
        snapshot.cpuTemperature.map { "\(Int($0.rounded()))°C" } ?? "—"
    }

    private func powerText(_ snapshot: HardwareSnapshot) -> String {
        snapshot.cpuPackagePower.map { String(format: "%.1f W", $0) } ?? "—"
    }

    private func fanText(_ snapshot: HardwareSnapshot) -> String {
        if let rpm = snapshot.fanRPM { return "\(Int(rpm)) RPM" }
        if let percent = snapshot.fanPercent { return "\(Int(percent))%" }
        return "N/A"
    }

    private func batteryText(_ snapshot: HardwareSnapshot) -> String {
        guard snapshot.batteryIsConnected else { return "N/A" }
        return snapshot.batteryPercent?.percentText ?? "—"
    }

    private func performanceText(_ snapshot: HardwareSnapshot) -> String {
        snapshot.performanceProfile?.rawValue ?? "N/A"
    }

    private func coolingModeText(_ snapshot: HardwareSnapshot) -> String {
        snapshot.coolingMode?.rawValue ?? "N/A"
    }

    private func batterySymbol(_ snapshot: HardwareSnapshot) -> String {
        snapshot.batteryIsCharging ? "battery.100percent.bolt" : "battery.75percent"
    }

    private func normalizedTemperature(_ value: Double?) -> Double {
        min(max((value ?? 0) / 100, 0), 1)
    }

    private func temperatureTint(_ temperature: Double?) -> Color {
        guard let value = temperature else { return .secondary }
        if value >= 90 { return .red }
        if value >= 75 { return .orange }
        return .green
    }

    private func freshnessBadge(_ snapshot: HardwareSnapshot) -> some View {
        let isStale = entry.date.timeIntervalSince(snapshot.timestamp) >= 120
        return Text(isStale ? "STALE" : "LIVE")
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .foregroundStyle(isStale ? .orange : .green)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background((isStale ? Color.orange : .green).opacity(0.12), in: Capsule())
    }

    private func updatedLabel(_ snapshot: HardwareSnapshot) -> some View {
        Text(updatedText(snapshot))
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    private func updatedText(_ snapshot: HardwareSnapshot) -> String {
        let seconds = max(0, Int(entry.date.timeIntervalSince(snapshot.timestamp)))
        if seconds < 5 { return "Updated now" }
        if seconds < 60 { return "Updated \(seconds)s ago" }
        let minutes = seconds / 60
        if minutes < 60 { return "Updated \(minutes)m ago" }
        return "Updated \(minutes / 60)h ago"
    }

    private func controlText(_ snapshot: HardwareSnapshot) -> String {
        snapshot.controlAvailability.isWritable ? "Hardware controls ready" : "Monitor mode"
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
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

@main
struct R3ControlWidgetBundle: WidgetBundle {
    var body: some Widget { R3StatusWidget() }
}

#Preview(as: .systemSmall) {
    R3StatusWidget()
} timeline: {
    R3StatusEntry(date: .now, snapshot: .placeholder)
}

#Preview(as: .systemMedium) {
    R3StatusWidget()
} timeline: {
    R3StatusEntry(date: .now, snapshot: .placeholder)
}

#Preview(as: .systemLarge) {
    R3StatusWidget()
} timeline: {
    R3StatusEntry(date: .now, snapshot: .placeholder)
}
