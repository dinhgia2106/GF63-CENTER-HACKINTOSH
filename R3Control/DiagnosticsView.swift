import SwiftUI

struct DiagnosticsView: View {
    @EnvironmentObject private var monitor: HardwareMonitor
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeader(
                    eyebrow: "System health",
                    title: "Diagnostics",
                    subtitle: "Understand what is available without exposing unique machine identity.",
                    symbol: "stethoscope"
                )

                healthSummary

                HStack(alignment: .top, spacing: 16) {
                    diagnosticGroup(
                        "Platform",
                        subtitle: "Detected at runtime",
                        symbol: "macbook",
                        tint: R3Theme.cyan
                    ) {
                        row("Product family", SystemIdentity.productFamily, "laptopcomputer", .secondary)
                        row("SMBIOS", SystemIdentity.modelIdentifier, "rectangle.and.text.magnifyingglass", .secondary)
                        row("Processor", SystemIdentity.cpuName, "cpu", R3Theme.cyan)
                        row("Topology", SystemIdentity.cpuTopology, "square.grid.3x3.fill", .secondary)
                        row("System", SystemIdentity.osSummary, "apple.logo", .secondary)
                    }

                    diagnosticGroup(
                        "Sensors",
                        subtitle: "Live capability map",
                        symbol: "sensor.fill",
                        tint: R3Theme.violet
                    ) {
                        availabilityRow("AppleSMC", monitor.snapshot.cpuTemperature != nil)
                        availabilityRow("CPU temperature", monitor.snapshot.cpuTemperature != nil)
                        availabilityRow("Package power", monitor.snapshot.cpuPackagePower != nil)
                        availabilityRow("Fan telemetry", monitor.snapshot.fanRPM != nil || monitor.snapshot.fanPercent != nil)
                        availabilityRow("Battery", monitor.snapshot.batteryPercent != nil)
                        row("EC firmware", monitor.snapshot.ecFirmware ?? "R3EC not loaded", "memorychip", gateTint)
                    }
                }

                diagnosticGroup(
                    "Hardware control boundary",
                    subtitle: "Safety takes precedence over unsupported writes",
                    symbol: "lock.shield.fill",
                    tint: gateTint
                ) {
                    HStack(spacing: 14) {
                        controlTile("Saved profile", model.profile.rawValue, "speedometer", R3Theme.violet)
                        controlTile(
                            "Saved fan mode",
                            model.coolingMode == .basic ? "Basic · \(model.manualFanPercent)%" : model.coolingMode.rawValue,
                            "switch.2",
                            R3Theme.cyan
                        )
                        controlTile("EC writes", monitor.snapshot.controlAvailability.isWritable ? "Allowlisted" : "Blocked", "memorychip", gateTint)
                        controlTile("Failure mode", "Firmware Auto", "arrow.uturn.backward.circle", R3Theme.cyan)
                    }

                    Text(monitor.snapshot.controlAvailability.isWritable
                         ? "The displayed configuration is sent through R3EC and accepted only after EC read-back verification."
                         : "Saved controls are preferences only; the current hardware state is still owned by system firmware.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 10) {
                    Image(systemName: "hand.raised.fill")
                        .foregroundStyle(R3Theme.good)
                    Text("Snapshots and widgets exclude serial numbers, MAC addresses and other unique identifiers.")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
            }
            .padding(.horizontal, 30)
            .padding(.top, 26)
            .padding(.bottom, 36)
        }
        .scrollIndicators(.hidden)
        .navigationTitle("Diagnostics")
    }

    private var healthSummary: some View {
        HStack(spacing: 18) {
            ZStack {
                Circle().fill(gateTint.opacity(0.13))
                Circle().stroke(gateTint.opacity(0.28), lineWidth: 1)
                Image(systemName: monitor.snapshot.controlAvailability.isWritable ? "checkmark.shield.fill" : "shield.lefthalf.filled")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(gateTint)
            }
            .frame(width: 68, height: 68)

            VStack(alignment: .leading, spacing: 4) {
                Text("The system is protected")
                    .font(.title2.bold())
                Text(monitor.snapshot.controlAvailability.isWritable
                     ? "R3EC matched a validated profile and keeps Firmware Auto as its fallback."
                     : "Monitoring is active. Unsupported Embedded Controller writes remain blocked.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(sensorCountText)
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                Text("live capabilities")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(22)
        .r3Glass(cornerRadius: 26, tint: gateTint)
    }

    private func diagnosticGroup<Content: View>(
        _ title: String,
        subtitle: String,
        symbol: String,
        tint: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 11) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 34, height: 34)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(subtitle).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
            }
            content()
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .r3Glass(cornerRadius: 24, tint: tint)
    }

    private func row(_ name: String, _ value: String, _ symbol: String, _ tint: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.caption)
                .foregroundStyle(tint)
                .frame(width: 20)
            Text(name)
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .font(.callout.weight(.medium))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.vertical, 5)
    }

    private func availabilityRow(_ name: String, _ available: Bool) -> some View {
        let tint = available ? R3Theme.good : Color.secondary
        return HStack(spacing: 10) {
            Circle()
                .fill(tint)
                .frame(width: 7, height: 7)
                .shadow(color: available ? tint.opacity(0.65) : .clear, radius: 4)
            Text(name).font(.callout)
            Spacer()
            Text(available ? "Available" : "Not published")
                .font(.caption.weight(.medium))
                .foregroundStyle(tint)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(tint.opacity(0.09), in: Capsule())
        }
        .padding(.vertical, 5)
    }

    private func controlTile(_ title: String, _ value: String, _ symbol: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
            Text(value)
                .font(.callout.weight(.semibold))
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 100, alignment: .leading)
        .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var gateTint: Color {
        monitor.snapshot.controlAvailability.isWritable ? R3Theme.good : R3Theme.warning
    }

    private var sensorCountText: String {
        var count = 0
        if monitor.snapshot.cpuTemperature != nil { count += 1 }
        if monitor.snapshot.cpuPackagePower != nil { count += 1 }
        if monitor.snapshot.fanRPM != nil || monitor.snapshot.fanPercent != nil { count += 1 }
        if monitor.snapshot.batteryPercent != nil { count += 1 }
        return "\(count) / 4"
    }
}
