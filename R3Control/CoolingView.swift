import SwiftUI

struct CoolingView: View {
    @EnvironmentObject private var monitor: HardwareMonitor
    @EnvironmentObject private var model: AppModel

    private var controlsEnabled: Bool { monitor.snapshot.controlAvailability.isWritable }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeader(
                    eyebrow: "Thermal control",
                    title: "Cooling & performance",
                    subtitle: "Tune behavior without giving up firmware safety.",
                    symbol: "fan.fill"
                )

                safetyBanner

                GlassSection(
                    "Performance profile",
                    subtitle: "Hardware-backed MSI performance policy with EC read-back",
                    symbol: "speedometer",
                    tint: R3Theme.violet
                ) {
                    HStack(spacing: 12) {
                        ForEach(PerformanceProfile.allCases) { profile in
                            profileButton(profile)
                        }
                    }
                    if let active = monitor.activePerformanceProfile {
                        Label("EC active: \(active.rawValue)", systemImage: "checkmark.shield.fill")
                            .font(.caption)
                            .foregroundStyle(R3Theme.good)
                    }
                }

                HStack(alignment: .top, spacing: 16) {
                    GlassSection(
                        "Fan behavior",
                        subtitle: "Auto, quiet, maximum airflow or a fixed custom speed",
                        symbol: "wind",
                        tint: R3Theme.cyan
                    ) {
                        Picker("Fan mode", selection: Binding(
                            get: { model.coolingMode },
                            set: {
                                model.setCoolingMode($0)
                                monitor.applyCooling(model.configuration)
                            }
                        )) {
                            ForEach(CoolingMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)

                        if model.coolingMode == .custom {
                            HStack(spacing: 12) {
                                Image(systemName: "fan.fill")
                                    .foregroundStyle(R3Theme.cyan)
                                Text("Fan speed")
                                    .font(.callout.weight(.medium))
                                Slider(
                                    value: Binding(
                                        get: { Double(model.manualFanPercent) },
                                        set: {
                                            model.setManualFanSpeed(Int($0.rounded()))
                                            monitor.scheduleCooling(model.configuration)
                                        }
                                    ),
                                    in: 35...100,
                                    step: 1
                                )
                                Text("\(model.manualFanPercent)%")
                                    .font(.callout.monospacedDigit().weight(.semibold))
                                    .frame(width: 42, alignment: .trailing)
                            }
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }

                    GlassSection(
                        "Live cooling",
                        subtitle: "Available telemetry",
                        symbol: "fan.fill",
                        tint: .mint
                    ) {
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Text(fanValue)
                                .font(.system(size: 38, weight: .semibold, design: .rounded))
                                .contentTransition(.numericText())
                            Text(fanUnit)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                        Text(fanDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 245)
                }

                if let message = monitor.lastControlMessage {
                    Label(message, systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(R3Theme.good)
                }
                if let error = monitor.lastError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(R3Theme.warning)
                }
            }
            .padding(.horizontal, 30)
            .padding(.top, 26)
            .padding(.bottom, 36)
        }
        .scrollIndicators(.hidden)
        .navigationTitle("Cooling")
    }

    private var safetyBanner: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle().fill(gateTint.opacity(0.14))
                Image(systemName: controlsEnabled ? "checkmark.shield.fill" : "lock.shield.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(gateTint)
            }
            .frame(width: 54, height: 54)

            VStack(alignment: .leading, spacing: 4) {
                Text(controlsEnabled ? "Hardware controls are ready" : "Configuration mode")
                    .font(.headline)
                Text(controlsEnabled
                     ? "Only allowlisted commands are accepted. Firmware Auto remains the failure fallback."
                     : "You can edit and save profiles now. Embedded Controller writes remain blocked until a validated R3EC bridge is connected.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if controlsEnabled {
                VStack(alignment: .trailing, spacing: 8) {
                    Button("Apply saved controls") {
                        monitor.applySavedConfiguration(model.configuration)
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Restore Firmware Auto") {
                        model.setCoolingMode(.auto)
                        monitor.restoreFirmwareAuto()
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
            } else {
                StatusPill(text: "Saved locally", tint: gateTint)
            }
        }
        .padding(20)
        .r3Glass(cornerRadius: 24, tint: gateTint)
    }

    private func profileButton(_ profile: PerformanceProfile) -> some View {
        let isSelected = model.profile == profile
        return Button {
            withAnimation(.snappy) { model.selectProfile(profile) }
            monitor.setPerformanceProfile(profile)
        } label: {
            VStack(alignment: .leading, spacing: 15) {
                HStack {
                    Image(systemName: profileSymbol(profile))
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(isSelected ? .white : profileTint(profile))
                    Spacer()
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.caption)
                        .foregroundStyle(isSelected ? .white.opacity(0.9) : .secondary)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(profile.rawValue).font(.headline)
                    Text(profileHint(profile)).font(.caption).foregroundStyle(isSelected ? .white.opacity(0.72) : .secondary)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 118, alignment: .leading)
            .foregroundStyle(isSelected ? .white : .primary)
            .background(
                isSelected ? profileTint(profile).gradient : Color.clear.gradient,
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(isSelected ? .white.opacity(0.18) : .primary.opacity(0.07), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private var gateTint: Color { controlsEnabled ? R3Theme.good : R3Theme.warning }

    private var fanValue: String {
        if let rpm = monitor.snapshot.fanRPM { return "\(Int(rpm))" }
        if let percent = monitor.snapshot.fanPercent { return "\(Int(percent))" }
        return "—"
    }

    private var fanUnit: String {
        if monitor.snapshot.fanRPM != nil { return "RPM" }
        if monitor.snapshot.fanPercent != nil { return "%" }
        return ""
    }

    private var fanDescription: String {
        monitor.snapshot.fanRPM == nil && monitor.snapshot.fanPercent == nil
            ? "No compatible fan sensor is currently published."
            : "Primary cooling channel"
    }

    private func profileSymbol(_ profile: PerformanceProfile) -> String {
        switch profile {
        case .eco: return "leaf.fill"
        case .comfort: return "circle.lefthalf.filled"
        case .sport: return "speedometer"
        case .turbo: return "bolt.fill"
        }
    }

    private func profileHint(_ profile: PerformanceProfile) -> String {
        switch profile {
        case .eco: return "Lowest power & heat"
        case .comfort: return "Balanced daily use"
        case .sport: return "Higher performance"
        case .turbo: return "Maximum performance"
        }
    }

    private func profileTint(_ profile: PerformanceProfile) -> Color {
        switch profile {
        case .eco: return R3Theme.good
        case .comfort: return R3Theme.cyan
        case .sport: return R3Theme.violet
        case .turbo: return R3Theme.accent
        }
    }
}
