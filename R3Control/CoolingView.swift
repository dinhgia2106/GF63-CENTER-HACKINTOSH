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
                    subtitle: "Choose the balance between acoustics and responsiveness",
                    symbol: "speedometer",
                    tint: R3Theme.violet
                ) {
                    HStack(spacing: 12) {
                        ForEach(PerformanceProfile.allCases) { profile in
                            profileButton(profile)
                        }
                    }
                }

                HStack(alignment: .top, spacing: 16) {
                    GlassSection(
                        "Fan behavior",
                        subtitle: "Firmware governor",
                        symbol: "wind",
                        tint: R3Theme.cyan
                    ) {
                        Picker("Fan mode", selection: $model.coolingMode) {
                            ForEach(CoolingMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .disabled(!controlsEnabled)

                        Divider().opacity(0.5)

                        Toggle(isOn: $model.coolerBoost) {
                            HStack(spacing: 12) {
                                Image(systemName: "fan.badge.automatic")
                                    .font(.title3)
                                    .foregroundStyle(R3Theme.cyan)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Cooler Boost").font(.headline)
                                    Text("Maximum airflow with automatic rollback")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .toggleStyle(.switch)
                        .disabled(!controlsEnabled)
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

                GlassSection(
                    "Fan curve",
                    subtitle: "A firmware profile is required before custom points can be edited",
                    symbol: "point.topleft.down.curvedto.point.bottomright.up",
                    tint: R3Theme.accent
                ) {
                    HStack(spacing: 24) {
                        FanCurvePreview()
                            .frame(height: 132)

                        VStack(alignment: .leading, spacing: 10) {
                            Label("Validation required", systemImage: "lock.fill")
                                .font(.headline)
                            Text("R3EC unlocks this editor only after every temperature and PWM point has been verified for the detected firmware.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(width: 285, alignment: .leading)
                    }
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
                Text(controlsEnabled ? "Hardware controls are ready" : "Safe monitor mode")
                    .font(.headline)
                Text(controlsEnabled
                     ? "Only allowlisted commands are accepted. Firmware Auto remains the failure fallback."
                     : "Live monitoring stays active while all Embedded Controller writes are blocked.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            StatusPill(text: controlsEnabled ? "R3EC connected" : "Read only", tint: gateTint)
        }
        .padding(20)
        .r3Glass(cornerRadius: 24, tint: gateTint)
    }

    private func profileButton(_ profile: PerformanceProfile) -> some View {
        let isSelected = model.profile == profile
        return Button {
            guard controlsEnabled else { return }
            withAnimation(.snappy) { model.profile = profile }
        } label: {
            VStack(alignment: .leading, spacing: 15) {
                HStack {
                    Image(systemName: profileSymbol(profile))
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(isSelected ? .white : profileTint(profile))
                    Spacer()
                    Image(systemName: controlsEnabled ? (isSelected ? "checkmark.circle.fill" : "circle") : "lock.fill")
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
        .allowsHitTesting(controlsEnabled)
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
        case .eco: return "Cool & efficient"
        case .comfort: return "Balanced"
        case .sport: return "Responsive"
        case .turbo: return "Maximum"
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

private struct FanCurvePreview: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                VStack(spacing: 0) {
                    ForEach(0..<4, id: \.self) { _ in
                        Divider().opacity(0.14)
                        Spacer()
                    }
                }

                Path { path in
                    let points = [
                        CGPoint(x: 0.02, y: 0.82),
                        CGPoint(x: 0.25, y: 0.74),
                        CGPoint(x: 0.48, y: 0.58),
                        CGPoint(x: 0.70, y: 0.34),
                        CGPoint(x: 0.98, y: 0.10)
                    ]
                    guard let first = points.first else { return }
                    path.move(to: CGPoint(x: first.x * proxy.size.width, y: first.y * proxy.size.height))
                    for point in points.dropFirst() {
                        path.addLine(to: CGPoint(x: point.x * proxy.size.width, y: point.y * proxy.size.height))
                    }
                }
                .stroke(
                    LinearGradient(colors: [R3Theme.cyan, R3Theme.accent], startPoint: .leading, endPoint: .trailing),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                )
                .blur(radius: 0.15)
            }
        }
    }
}
