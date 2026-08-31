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
                    subtitle: "Saved app preset only; MSI Shift writes remain blocked until validated",
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
                        Picker("Fan mode", selection: Binding(
                            get: { model.coolingMode },
                            set: {
                                model.setCoolingMode($0)
                                monitor.applyCooling(model.configuration)
                            }
                        )) {
                            ForEach(CoolingMode.allCases.filter { $0 != .silent }) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)

                        if model.coolingMode == .basic {
                            HStack(spacing: 12) {
                                Image(systemName: "fan.fill")
                                    .foregroundStyle(R3Theme.cyan)
                                Text("Fixed speed")
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

                        Divider().opacity(0.5)

                        Toggle(isOn: Binding(
                            get: { model.coolerBoost },
                            set: {
                                model.setCoolerBoost($0)
                                monitor.setCoolerBoost($0)
                            }
                        )) {
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
                    subtitle: model.coolingMode == .advanced
                        ? "Adjust a monotonic curve; adjacent points stay within safe ordering"
                        : "Choose Advanced mode to edit the saved custom curve",
                    symbol: "point.topleft.down.curvedto.point.bottomright.up",
                    tint: R3Theme.accent
                ) {
                    HStack(alignment: .top, spacing: 24) {
                        VStack(alignment: .leading, spacing: 12) {
                            FanCurvePreview(points: model.fanCurve)
                                .frame(height: 168)
                            HStack {
                                Label("Temperature", systemImage: "thermometer.medium")
                                Spacer()
                                Label("Fan output", systemImage: "fan.fill")
                            }
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }

                        FanCurveEditor(
                            points: model.fanCurve,
                            isEnabled: model.coolingMode == .advanced,
                            onChange: {
                                model.setFanSpeed($0, at: $1)
                                monitor.scheduleCooling(model.configuration)
                            }
                        )
                        .frame(width: 330)
                    }

                    HStack {
                        Label(
                            controlsEnabled ? "Curve is ready for the validated bridge" : "Saved locally; hardware remains on firmware control",
                            systemImage: controlsEnabled ? "checkmark.shield.fill" : "externaldrive.badge.exclamationmark"
                        )
                        .foregroundStyle(.secondary)
                        Spacer()
                        Button("Reset curve") {
                            model.resetFanCurve()
                            monitor.applyCooling(model.configuration)
                        }
                            .disabled(model.coolingMode != .advanced)
                    }
                    .font(.caption)
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
                        model.setCoolerBoost(false)
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
    let points: [FanCurvePoint]

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
                    guard let first = points.first, let last = points.last else { return }
                    let temperatureSpan = max(last.temperature - first.temperature, 1)
                    func position(_ point: FanCurvePoint) -> CGPoint {
                        let x = Double(point.temperature - first.temperature) / Double(temperatureSpan)
                        let y = 1 - (Double(point.percent) / 100)
                        return CGPoint(x: x * proxy.size.width, y: y * proxy.size.height)
                    }
                    path.move(to: position(first))
                    for point in points.dropFirst() {
                        path.addLine(to: position(point))
                    }
                }
                .stroke(
                    LinearGradient(colors: [R3Theme.cyan, R3Theme.accent], startPoint: .leading, endPoint: .trailing),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                )
                .blur(radius: 0.15)

                ForEach(points) { point in
                    let firstTemperature = points.first?.temperature ?? point.temperature
                    let lastTemperature = points.last?.temperature ?? point.temperature + 1
                    let span = max(lastTemperature - firstTemperature, 1)
                    Circle()
                        .fill(R3Theme.accent)
                        .overlay(Circle().stroke(.white.opacity(0.8), lineWidth: 1.5))
                        .frame(width: 9, height: 9)
                        .position(
                            x: Double(point.temperature - firstTemperature) / Double(span) * proxy.size.width,
                            y: (1 - Double(point.percent) / 100) * proxy.size.height
                        )
                }
            }
        }
    }
}

private struct FanCurveEditor: View {
    let points: [FanCurvePoint]
    let isEnabled: Bool
    let onChange: (Int, Int) -> Void

    var body: some View {
        VStack(spacing: 9) {
            ForEach(Array(points.enumerated()), id: \.element.id) { index, point in
                HStack(spacing: 10) {
                    Text("\(point.temperature)°")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 34, alignment: .trailing)
                    Slider(
                        value: Binding(
                            get: { Double(points[index].percent) },
                            set: { onChange(Int($0.rounded()), index) }
                        ),
                        in: 35...100,
                        step: 1
                    )
                    Text("\(point.percent)%")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .frame(width: 38, alignment: .trailing)
                }
            }
        }
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
    }
}
