import Foundation
import ServiceManagement

struct ControlConfiguration: Codable, Equatable, Sendable {
    var profile: PerformanceProfile
    var coolingMode: CoolingMode
    var manualFanPercent: Int

    static let `default` = ControlConfiguration(
        profile: .comfort,
        coolingMode: .auto,
        manualFanPercent: 50
    )
}

@MainActor
final class AppModel: ObservableObject {
    enum Section: String, CaseIterable, Identifiable {
        case overview = "Overview"
        case cooling = "Cooling"
        case battery = "Battery"
        case diagnostics = "Diagnostics"

        var id: String { rawValue }

        var symbol: String {
            switch self {
            case .overview: return "gauge.with.dots.needle.50percent"
            case .cooling: return "fan"
            case .battery: return "battery.75percent"
            case .diagnostics: return "stethoscope"
            }
        }
    }

    enum SavedState: Equatable {
        case saved(Date)
        case failed(String)

        var message: String {
            switch self {
            case .saved: return "Configuration saved"
            case .failed(let message): return message
            }
        }
    }

    @Published var selection: Section? = .overview
    @Published private(set) var configuration: ControlConfiguration
    @Published private(set) var launchAtLogin: Bool
    @Published private(set) var savedState: SavedState
    @Published private(set) var loginItemError: String?
    @Published var showSafetyDetails = false

    private let defaults: UserDefaults
    private static let configurationKey = "control.configuration.v2"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.configurationKey),
           let saved = try? JSONDecoder().decode(ControlConfiguration.self, from: data),
           Self.isValid(saved) {
            configuration = saved
        } else {
            configuration = .default
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
        savedState = .saved(.now)
    }

    var profile: PerformanceProfile { configuration.profile }
    var coolingMode: CoolingMode { configuration.coolingMode }
    var manualFanPercent: Int { configuration.manualFanPercent }

    func selectProfile(_ profile: PerformanceProfile) {
        configuration.profile = profile
        persist()
    }

    func setCoolingMode(_ mode: CoolingMode) {
        configuration.coolingMode = mode
        persist()
    }

    func setManualFanSpeed(_ percent: Int) {
        configuration.manualFanPercent = min(max(percent, 35), 100)
        persist()
    }

    func resetControls() {
        configuration = .default
        persist()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        loginItemError = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLogin = SMAppService.mainApp.status == .enabled
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            loginItemError = error.localizedDescription
        }
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(configuration)
            defaults.set(data, forKey: Self.configurationKey)
            savedState = .saved(.now)
        } catch {
            savedState = .failed("Could not save configuration: \(error.localizedDescription)")
        }
    }

    private static func isValid(_ configuration: ControlConfiguration) -> Bool {
        (35...100).contains(configuration.manualFanPercent)
    }

}
