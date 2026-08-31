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
        FanCurvePoint(temperature: 45, percent: 20),
        FanCurvePoint(temperature: 55, percent: 30),
        FanCurvePoint(temperature: 65, percent: 42),
        FanCurvePoint(temperature: 75, percent: 58),
        FanCurvePoint(temperature: 85, percent: 78),
        FanCurvePoint(temperature: 95, percent: 100)
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
    var chargeLimit: Int { configuration.chargeLimit }

    func selectProfile(_ profile: PerformanceProfile) {
        configuration.profile = profile
        if configuration.coolingMode != .advanced {
            configuration.fanCurve = Self.curve(for: profile)
        }
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
        configuration.manualFanPercent = min(max(percent, 20), 100)
        persist()
    }

    func setFanSpeed(_ percent: Int, at index: Int) {
        guard configuration.fanCurve.indices.contains(index) else { return }
        let lowerBound = index == 0 ? 0 : configuration.fanCurve[index - 1].percent
        let upperBound = index == configuration.fanCurve.count - 1
            ? 100
            : configuration.fanCurve[index + 1].percent
        configuration.fanCurve[index].percent = min(max(percent, lowerBound), upperBound)
        persist()
    }

    func resetFanCurve() {
        configuration.fanCurve = Self.curve(for: configuration.profile)
        persist()
    }

    func setChargeLimit(_ limit: Int) {
        guard [60, 80, 100].contains(limit) else { return }
        configuration.chargeLimit = limit
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
            && (20...100).contains(configuration.manualFanPercent)
            && configuration.fanCurve.count >= 2
            && configuration.fanCurve.allSatisfy { (0...100).contains($0.percent) }
            && zip(configuration.fanCurve, configuration.fanCurve.dropFirst()).allSatisfy {
                $0.temperature < $1.temperature && $0.percent <= $1.percent
            }
    }

    private static func curve(for profile: PerformanceProfile) -> [FanCurvePoint] {
        let speeds: [Int]
        switch profile {
        case .eco: speeds = [15, 22, 32, 45, 65, 100]
        case .comfort: speeds = [20, 30, 42, 58, 78, 100]
        case .sport: speeds = [28, 38, 52, 68, 86, 100]
        case .turbo: speeds = [35, 48, 62, 76, 90, 100]
        }
        return zip([45, 55, 65, 75, 85, 95], speeds).map {
            FanCurvePoint(temperature: $0, percent: $1)
        }
    }
}
