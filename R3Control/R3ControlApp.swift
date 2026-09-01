import SwiftUI

@main
struct R3ControlApp: App {
    @StateObject private var monitor = HardwareMonitor()
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("R3 Control", id: "dashboard") {
            MainView()
                .environmentObject(monitor)
                .environmentObject(model)
                .frame(minWidth: 1020, minHeight: 680)
                .onAppear { monitor.start() }
        }
        .defaultSize(width: 1180, height: 780)
        .windowStyle(.hiddenTitleBar)

        MenuBarExtra {
            MenuBarPanel()
                .environmentObject(monitor)
                .environmentObject(model)
        } label: {
            if let temperature = monitor.snapshot.cpuTemperature {
                Label("\(Int(temperature.rounded()))°", systemImage: "fan.fill")
            } else {
                Image(systemName: "fan.fill")
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(model)
        }
    }
}

struct MainView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var monitor: HardwareMonitor

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 230, ideal: 250, max: 280)
        } detail: {
            ZStack {
                AmbientBackground()
                selectedPage
            }
        }
        .navigationSplitViewStyle(.balanced)
        .tint(R3Theme.accent)
    }

    private var sidebar: some View {
        ZStack {
            LinearGradient(
                colors: [R3Theme.accent.opacity(0.07), R3Theme.cyan.opacity(0.025), .clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 18) {
                brand

                VStack(spacing: 7) {
                    ForEach(AppModel.Section.allCases) { section in
                        navigationButton(section)
                    }
                }
                .padding(.horizontal, 12)

                Spacer()
                statusFooter
            }
            .padding(.vertical, 14)
        }
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private var selectedPage: some View {
        switch model.selection ?? .overview {
        case .overview: OverviewView()
        case .cooling: CoolingView()
        case .battery: BatteryView()
        case .diagnostics: DiagnosticsView()
        }
    }

    private var brand: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 48, height: 48)
                .shadow(color: R3Theme.accent.opacity(0.18), radius: 12, y: 5)
            VStack(alignment: .leading, spacing: 2) {
                Text("R3 Control")
                    .font(.system(.headline, design: .rounded).weight(.bold))
                Text("GF63 Control Center")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func navigationButton(_ section: AppModel.Section) -> some View {
        let isSelected = (model.selection ?? .overview) == section
        return Button {
            withAnimation(.snappy(duration: 0.24)) {
                model.selection = section
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: section.symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 24)
                    .foregroundStyle(isSelected ? R3Theme.accent : .secondary)
                Text(section.rawValue)
                    .font(.callout.weight(isSelected ? .semibold : .medium))
                Spacer()
                if isSelected {
                    Circle()
                        .fill(R3Theme.accent)
                        .frame(width: 6, height: 6)
                        .shadow(color: R3Theme.accent, radius: 5)
                }
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 13)
            .padding(.vertical, 11)
            .background(
                isSelected ? R3Theme.accent.opacity(0.11) : .clear,
                in: RoundedRectangle(cornerRadius: 13, style: .continuous)
            )
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(R3Theme.accent.opacity(0.16), lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var statusFooter: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Hardware bridge")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(monitor.snapshot.controlAvailability.isWritable ? "Controls ready" : "Monitor mode")
                        .font(.caption.weight(.semibold))
                }
                Spacer()
                Image(systemName: monitor.snapshot.controlAvailability.isWritable ? "checkmark.shield.fill" : "lock.shield.fill")
                    .foregroundStyle(monitor.snapshot.controlAvailability.isWritable ? R3Theme.good : R3Theme.warning)
            }
            Divider().opacity(0.45)
            Text(SystemIdentity.productFamily)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .r3Glass(
            cornerRadius: 18,
            tint: monitor.snapshot.controlAvailability.isWritable ? R3Theme.good : R3Theme.warning
        )
        .padding(.horizontal, 12)
    }
}

struct MenuBarPanel: View {
    @EnvironmentObject private var monitor: HardwareMonitor
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ZStack {
            AmbientBackground()
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 11) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 40, height: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("R3 Control").font(.headline)
                        Text("Updated \(monitor.snapshot.timestamp, style: .time)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    StatusPill(text: model.profile.rawValue, tint: R3Theme.accent)
                }

                HStack(spacing: 9) {
                    miniMetric("CPU", monitor.snapshot.cpuTemperature.map { "\(Int($0))°" } ?? "—", R3Theme.accent)
                    miniMetric("LOAD", monitor.snapshot.cpuLoad.percentText, R3Theme.cyan)
                    miniMetric("FAN", monitor.snapshot.fanRPM.map { "\(Int($0))" } ?? "N/A", R3Theme.violet)
                }

                Picker("Profile", selection: Binding(
                    get: { model.profile },
                    set: { model.selectProfile($0) }
                )) {
                    ForEach(PerformanceProfile.allCases) { profile in
                        Text(profile.rawValue).tag(profile)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Fan behavior", selection: Binding(
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
                .pickerStyle(.segmented)

                if model.coolingMode == .custom {
                    HStack(spacing: 10) {
                        Image(systemName: "fan.fill")
                            .foregroundStyle(R3Theme.cyan)
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
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .frame(width: 38, alignment: .trailing)
                    }
                }

                if !monitor.snapshot.controlAvailability.isWritable {
                    Label("Preferences saved locally · firmware unchanged", systemImage: "lock.shield.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Button {
                    openWindow(id: "dashboard")
                    NSApp.activate(ignoringOtherApps: true)
                } label: {
                    Label("Open Dashboard", systemImage: "rectangle.inset.filled")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .tint(R3Theme.accent)
                .r3ProminentButtonStyle()

                HStack {
                    Button("Refresh") { monitor.refresh() }
                    Spacer()
                    Button("Quit") { NSApp.terminate(nil) }
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .font(.caption)
            }
            .padding(18)
        }
        .frame(width: 360)
    }

    private func miniMetric(_ title: String, _ value: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Circle().fill(tint).frame(width: 6, height: 6)
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .contentTransition(.numericText())
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .r3Glass(cornerRadius: 16, tint: tint)
    }
}

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ZStack {
            AmbientBackground()
            GlassSection("General", subtitle: "Personalize how R3 Control starts", symbol: "gearshape.fill") {
                Toggle("Launch R3 Control at login", isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.setLaunchAtLogin($0) }
                ))
                Text("Uses the native macOS login-item service; no background helper is installed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let error = model.loginItemError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(R3Theme.warning)
                }
                Divider()
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Control preferences")
                            .font(.callout.weight(.medium))
                        Text("Restore Comfort, Auto and 50% Custom fan speed.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Reset") { model.resetControls() }
                }
            }
            .padding(24)
        }
        .frame(width: 540, height: 340)
    }
}
