import Foundation

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

    @Published var selection: Section? = .overview
    @Published var profile: PerformanceProfile = .comfort
    @Published var coolingMode: CoolingMode = .auto
    @Published var coolerBoost = false
    @Published var launchAtLogin = false
    @Published var showSafetyDetails = false
}
