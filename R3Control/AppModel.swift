import Foundation
import ServiceManagement

struct FanCurvePoint: Codable, Equatable, Identifiable, Sendable {
    var temperature: Int
    var percent: Int

    var id: Int { temperature }
}

struct ControlConfiguration: Codable, Equatable, Sendable {
    var profile: PerformanceProfile
    var coolingMode: CoolingMode
    var coolerBoost: Bool
    var manualFanPercent: Int
    var fanCurve: [FanCurvePoint]
    var chargeLimit: Int

    static let defaultFanCurve = [
        FanCurvePoint(temperature: 55, percent: 38),
        FanCurvePoint(temperature: 64, percent: 42),
        FanCurvePoint(temperature: 73, percent: 45),
        FanCurvePoint(temperature: 76, percent: 50),
        FanCurvePoint(temperature: 82, percent: 55),
        FanCurvePoint(temperature: 88, percent: 62)
    ]

    static let `default` = ControlConfiguration(
        profile: .comfort,
        coolingMode: .auto,
        coolerBoost: false,
        manualFanPercent: 50,
        fanCurve: defaultFanCurve,
        chargeLimit: 100
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
    private static let configurationKey = "control.configuration.v1"

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
    var coolerBoost: Bool { configuration.coolerBoost }
    var manualFanPercent: Int { configuration.manualFanPercent }
    var fanCurve: [FanCurvePoint] { configuration.fanCurve }

    func selectProfile(_ profile: PerformanceProfile) {
        configuration.profile = profile
        persist()
    }

    func setCoolingMode(_ mode: CoolingMode) {
        configuration.coolingMode = mode
        if mode != .advanced { configuration.coolerBoost = false }
        persist()
    }

    func setCoolerBoost(_ enabled: Bool) {
        configuration.coolerBoost = enabled
        persist()
    }

    func setManualFanSpeed(_ percent: Int) {
        configuration.manualFanPercent = min(max(percent, 35), 100)
        persist()
    }

    func setFanSpeed(_ percent: Int, at index: Int) {
        guard configuration.fanCurve.indices.contains(index) else { return }
        let minimumSafeSpeed = index == configuration.fanCurve.count - 1 ? 62 : 35
        let lowerBound = max(minimumSafeSpeed, index == 0 ? 35 : configuration.fanCurve[index - 1].percent)
        let upperBound = index == configuration.fanCurve.count - 1
            ? 100
            : configuration.fanCurve[index + 1].percent
        configuration.fanCurve[index].percent = min(max(percent, lowerBound), upperBound)
        persist()
    }

    func resetFanCurve() {
        configuration.fanCurve = ControlConfiguration.defaultFanCurve
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
        [60, 80, 100].contains(configuration.chargeLimit)
            && configuration.coolingMode != .silent
            && (35...100).contains(configuration.manualFanPercent)
            && configuration.fanCurve.count == 6
            && configuration.fanCurve.allSatisfy {
                (45...95).contains($0.temperature) && (35...100).contains($0.percent)
            }
            && (configuration.fanCurve.last?.percent ?? 0) >= 62
            && zip(configuration.fanCurve, configuration.fanCurve.dropFirst()).allSatisfy {
                $0.temperature < $1.temperature && $0.percent <= $1.percent
            }
    }

}
