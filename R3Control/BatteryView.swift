import SwiftUI

struct BatteryView: View {
    @EnvironmentObject private var monitor: HardwareMonitor

    private let chargePresets = [60, 80, 100]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeader(
                    eyebrow: "Power",
                    title: "Battery",
                    subtitle: "Charge state plus system-reported battery estimates.",
                    symbol: "battery.75percent"
                )

                if monitor.snapshot.batteryPercent != nil {
                    batterySummary
                    chargeLimitSection
                } else {
                    unavailableCard
                }

                if let issue = telemetryIssue {
                    warningCard(issue)
                }

                if let notice = monitor.batteryTelemetryNotice {
                    sourceCard(notice)
                }

            }
            .padding(.horizontal, 30)
            .padding(.top, 26)
            .padding(.bottom, 36)
        }
        .scrollIndicators(.hidden)
        .navigationTitle("Battery")
    }

    private var chargeLimitSection: some View {
        GlassSection(
            "Charge limit",
            subtitle: "Choose how full the battery is kept while connected to power",
            symbol: "battery.100percent.bolt",
            tint: R3Theme.good
        ) {
            HStack(spacing: 12) {
                ForEach(chargePresets, id: \.self) { limit in
                    chargePresetButton(limit)
                }
            }

            if monitor.chargeLimitSupported {
                if let activeLimit = monitor.chargeLimit {
                    Label(
                        "EC active: stop at \(activeLimit)% · resume below \(max(activeLimit - 10, 0))%",
                        systemImage: "checkmark.shield.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(R3Theme.good)
                } else {
                    Label(
                        "Charge threshold is not initialized. Select a preset to enable it.",
                        systemImage: "exclamationmark.shield.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(R3Theme.warning)
                }
            } else {
                Label(
                    "Charge control is unavailable because the bridge or firmware did not publish a verified threshold.",
                    systemImage: "lock.shield.fill"
                )
                .font(.caption)
                .foregroundStyle(R3Theme.warning)
            }

            Text("Lower limits reduce time spent at a high state of charge. If the battery is already above the selected limit, it will stop charging but will not be discharged by the app.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func chargePresetButton(_ limit: Int) -> some View {
        let isActive = monitor.chargeLimit == limit
        return Button {
            monitor.setChargeLimit(limit)
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: chargePresetSymbol(limit))
                        .font(.system(size: 18, weight: .semibold))
                    Spacer()
                    Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                        .font(.caption)
                }
                Text("\(limit)%")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .monospacedDigit()
                VStack(alignment: .leading, spacing: 2) {
                    Text(chargePresetTitle(limit)).font(.callout.weight(.semibold))
                    Text("Recharge below \(limit - 10)%")
                        .font(.caption2)
                        .foregroundStyle(isActive ? .white.opacity(0.74) : .secondary)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 126, alignment: .leading)
            .foregroundStyle(isActive ? .white : .primary)
            .background(
                isActive ? chargePresetTint(limit).gradient : Color.clear.gradient,
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(isActive ? .white.opacity(0.18) : .primary.opacity(0.07), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(!chargeControlsEnabled)
        .opacity(chargeControlsEnabled ? 1 : 0.58)
    }

    private var chargeControlsEnabled: Bool {
        monitor.chargeLimitSupported && telemetryIssue == nil
    }

    private func chargePresetTitle(_ limit: Int) -> String {
        switch limit {
        case 60: return "Battery care"
        case 80: return "Balanced"
        default: return "Full capacity"
        }
    }

    private func chargePresetSymbol(_ limit: Int) -> String {
        switch limit {
        case 60: return "leaf.fill"
        case 80: return "scalemass.fill"
        default: return "suitcase.rolling.fill"
        }
    }

    private func chargePresetTint(_ limit: Int) -> Color {
        switch limit {
        case 60: return R3Theme.good
        case 80: return R3Theme.cyan
        default: return R3Theme.violet
        }
    }

    private var batterySummary: some View {
        HStack(spacing: 28) {
            ZStack {
                RingProgress(value: monitor.snapshot.batteryPercent ?? 0, tint: batteryTint, lineWidth: 15)
                VStack(spacing: 4) {
                    Image(systemName: monitor.snapshot.batteryIsCharging ? "bolt.fill" : "battery.75percent")
                        .font(.title3)
                        .foregroundStyle(batteryTint)
                    Text(monitor.snapshot.batteryPercent?.percentText ?? "—")
                        .font(.system(size: 42, weight: .semibold, design: .rounded))
                        .contentTransition(.numericText())
                    Text(powerStateText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 190, height: 190)

            VStack(alignment: .leading, spacing: 10) {
                Text(batteryHeadline)
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                Text(batteryNarrative)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                StatusPill(text: powerStateText, tint: batteryTint)
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider().frame(height: 150)

            VStack(spacing: 12) {
                compactMetric("Health estimate", healthText, "heart.fill", healthTint)
                compactMetric("Cycles reported", cycleText, "arrow.triangle.2.circlepath", R3Theme.cyan)
            }
            .frame(width: 230)
        }
        .padding(26)
        .r3Glass(cornerRadius: 30, tint: batteryTint)
        .animation(.smooth(duration: 0.45), value: monitor.snapshot.batteryPercent)
    }

    private func compactMetric(_ title: String, _ value: String, _ symbol: String, _ tint: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(13)
        .r3Glass(cornerRadius: 16, tint: tint)
    }

    private var unavailableCard: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle().fill(.secondary.opacity(0.08))
                Image(systemName: "battery.slash")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 78, height: 78)
            Text("Battery telemetry unavailable")
                .font(.title2.bold())
            Text("macOS did not return a portable power source. Cooling and system monitoring remain fully available.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .r3Glass(cornerRadius: 30)
    }

    private func warningCard(_ issue: String) -> some View {
        HStack(alignment: .top, spacing: 15) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundStyle(R3Theme.warning)
            VStack(alignment: .leading, spacing: 5) {
                Text("Battery telemetry needs attention").font(.headline)
                Text(issue).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(20)
        .r3Glass(cornerRadius: 22, tint: R3Theme.warning)
    }

    private func sourceCard(_ notice: String) -> some View {
        HStack(alignment: .top, spacing: 15) {
            Image(systemName: "info.circle.fill")
                .font(.title2)
                .foregroundStyle(R3Theme.cyan)
            VStack(alignment: .leading, spacing: 5) {
                Text(monitor.batteryTelemetryIsDirect ? "Direct firmware telemetry" : "Battery estimates are not stable")
                    .font(.headline)
                Text(notice).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(20)
        .r3Glass(cornerRadius: 22, tint: R3Theme.cyan)
    }

    private var telemetryIssue: String? {
        guard let percent = monitor.snapshot.batteryPercent else { return nil }
        guard percent.isFinite, (0...1).contains(percent) else {
            return "macOS returned an invalid battery percentage. Charge controls have been disabled."
        }
        if percent <= 0.02, monitor.snapshot.batteryIsConnected, !monitor.snapshot.batteryIsCharging {
            return "The battery reports a critically low charge while external power is connected and charging is inactive. Verify the reading before enabling charge controls."
        }
        if let health = monitor.snapshot.batteryHealthPercent,
           (!health.isFinite || !(0...1).contains(health)) {
            return "macOS returned an invalid battery-health value. Charge controls have been disabled."
        }
        return nil
    }

    private var powerStateText: String {
        if monitor.snapshot.batteryIsCharging { return "Charging" }
        if monitor.snapshot.batteryIsConnected { return "External power" }
        return "On battery"
    }

    private var batteryHeadline: String {
        guard let value = monitor.snapshot.batteryPercent else { return "Battery status unknown" }
        if value <= 0.15 { return "Running low" }
        if value <= 0.50 { return "Ready for a while" }
        return "Plenty of charge"
    }

    private var batteryNarrative: String {
        if monitor.snapshot.batteryIsCharging { return "Your battery is receiving power. Live telemetry will update as the charge level changes." }
        if monitor.snapshot.batteryIsConnected { return "External power is connected. Charging state is reported directly by macOS." }
        return "The system is currently running on battery power."
    }

    private var batteryTint: Color {
        guard let value = monitor.snapshot.batteryPercent else { return .secondary }
        if value < 0.15 { return .red }
        if value < 0.35 { return R3Theme.warning }
        return R3Theme.good
    }

    private var healthTint: Color {
        guard let health = monitor.snapshot.batteryHealthPercent else { return .secondary }
        return health < 0.7 ? R3Theme.warning : R3Theme.good
    }

    private var healthText: String {
        monitor.snapshot.batteryHealthPercent.map { "~\($0.percentText)" } ?? "N/A"
    }

    private var cycleText: String {
        monitor.snapshot.batteryCycleCount.map {
            monitor.batteryTelemetryIsDirect ? String($0) : "~\($0)"
        } ?? "N/A"
    }
}
