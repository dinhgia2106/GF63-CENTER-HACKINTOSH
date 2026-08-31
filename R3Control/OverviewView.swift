import Charts
import SwiftUI

struct OverviewView: View {
    @EnvironmentObject private var monitor: HardwareMonitor

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeader(
                    eyebrow: "R3 Control",
                    title: "Your GF63 at a glance",
                    subtitle: "A quiet, live view of the hardware that matters.",
                    symbol: "waveform.path.ecg",
                    trailingText: "Live"
                )

                temperatureHero

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 205), spacing: 14)], spacing: 14) {
                    MetricCard(
                        title: "Memory in use",
                        value: monitor.snapshot.memoryUsed.storageText,
                        detail: "\(memoryFreeText) available",
                        symbol: "memorychip.fill",
                        tint: R3Theme.violet
                    )
                    MetricCard(
                        title: "System disk",
                        value: diskFreeText,
                        detail: "free of \(monitor.snapshot.diskTotal.storageText)",
                        symbol: "internaldrive.fill",
                        tint: R3Theme.cyan
                    )
                    MetricCard(
                        title: "Cooling telemetry",
                        value: coolingValue,
                        detail: monitor.snapshot.fanRPM == nil ? "Waiting for a compatible fan sensor" : "Primary fan speed",
                        symbol: "fan.fill",
                        tint: .mint
                    )
                }

                temperatureChart
                systemIdentity
            }
            .padding(.horizontal, 30)
            .padding(.top, 26)
            .padding(.bottom, 36)
        }
        .scrollIndicators(.hidden)
        .navigationTitle("Overview")
    }

    private var temperatureHero: some View {
        HStack(spacing: 28) {
            VStack(alignment: .leading, spacing: 8) {
                Label("CPU PACKAGE", systemImage: "thermometer.medium")
                    .font(.caption2.weight(.bold))
                    .tracking(1.3)
                    .foregroundStyle(temperatureTint)

                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(monitor.snapshot.cpuTemperature.map { "\(Int($0.rounded()))" } ?? "—")
                        .font(.system(size: 72, weight: .semibold, design: .rounded))
                        .contentTransition(.numericText())
                    Text("°C")
                        .font(.title2.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                Text(temperatureMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 220, alignment: .leading)

            ZStack {
                RingProgress(
                    value: min((monitor.snapshot.cpuTemperature ?? 0) / 100, 1),
                    tint: temperatureTint,
                    lineWidth: 12
                )
                Image(systemName: "cpu.fill")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(temperatureTint)
            }
            .frame(width: 112, height: 112)

            Divider().frame(height: 106)

            HStack(spacing: 32) {
                heroMetric("CPU load", monitor.snapshot.cpuLoad.percentText, "gauge.with.dots.needle.67percent")
                heroMetric(
                    "Package power",
                    monitor.snapshot.cpuPackagePower.map { String(format: "%.1f W", $0) } ?? "N/A",
                    "bolt.fill"
                )
                heroMetric("Topology", SystemIdentity.cpuTopology, "square.grid.3x3.fill")
            }
            .frame(maxWidth: .infinity)
        }
        .padding(26)
        .r3Glass(cornerRadius: 30, tint: temperatureTint)
        .animation(.smooth(duration: 0.45), value: monitor.snapshot.cpuTemperature)
    }

    private func heroMetric(_ title: String, _ value: String, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(R3Theme.cyan)
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .contentTransition(.numericText())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var temperatureChart: some View {
        GlassSection(
            "Thermal history",
            subtitle: "The last three minutes, sampled every two seconds",
            symbol: "chart.xyaxis.line",
            tint: R3Theme.accent
        ) {
            Chart(monitor.history.suffix(90), id: \.timestamp) { point in
                if let temperature = point.cpuTemperature {
                    AreaMark(
                        x: .value("Time", point.timestamp),
                        yStart: .value("Base", 30),
                        yEnd: .value("Temperature", temperature)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [R3Theme.accent.opacity(0.30), R3Theme.accent.opacity(0.015)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    LineMark(
                        x: .value("Time", point.timestamp),
                        y: .value("Temperature", temperature)
                    )
                    .interpolationMethod(.catmullRom)
                    .lineStyle(.init(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    .foregroundStyle(R3Theme.accent)
                }
            }
            .chartYScale(domain: 30...105)
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(position: .leading, values: [40, 60, 80, 100]) { value in
                    AxisGridLine().foregroundStyle(.secondary.opacity(0.12))
                    AxisValueLabel {
                        if let temperature = value.as(Int.self) {
                            Text("\(temperature)°")
                        }
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .frame(height: 218)
        }
    }

    private var systemIdentity: some View {
        HStack(spacing: 0) {
            identityItem("Operating system", "\(SystemIdentity.osSummary) • \(SystemIdentity.architecture)", "macbook")
            Divider().frame(height: 36).padding(.horizontal, 20)
            identityItem("Processor", SystemIdentity.cpuName, "cpu")
            Divider().frame(height: 36).padding(.horizontal, 20)
            identityItem("Last update", monitor.snapshot.timestamp.formatted(date: .omitted, time: .standard), "clock.fill")
        }
        .padding(20)
        .r3Glass(cornerRadius: 22)
    }

    private func identityItem(_ title: String, _ value: String, _ symbol: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption2).foregroundStyle(.tertiary)
                Text(value).font(.caption.weight(.medium)).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var coolingValue: String {
        if let rpm = monitor.snapshot.fanRPM { return "\(Int(rpm)) RPM" }
        if let percent = monitor.snapshot.fanPercent { return "\(Int(percent))%" }
        return "Unavailable"
    }

    private var diskFreeText: String {
        guard monitor.snapshot.diskTotal >= monitor.snapshot.diskUsed else { return "N/A" }
        return (monitor.snapshot.diskTotal - monitor.snapshot.diskUsed).storageText
    }

    private var memoryFreeText: String {
        guard monitor.snapshot.memoryTotal >= monitor.snapshot.memoryUsed else { return "N/A" }
        return (monitor.snapshot.memoryTotal - monitor.snapshot.memoryUsed).storageText
    }

    private var temperatureTint: Color {
        guard let value = monitor.snapshot.cpuTemperature else { return .secondary }
        if value >= 90 { return .red }
        if value >= 75 { return R3Theme.warning }
        return R3Theme.good
    }

    private var temperatureMessage: String {
        guard let value = monitor.snapshot.cpuTemperature else { return "Temperature sensor is unavailable" }
        if value >= 90 { return "Very hot — firmware protection remains active" }
        if value >= 75 { return "Warm, but still within the expected range" }
        return "Thermals look comfortable"
    }
}
