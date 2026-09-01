import Foundation

struct HardwareSnapshot: Codable, Sendable, Equatable {
    var timestamp: Date
    var cpuTemperature: Double?
    var cpuPackagePower: Double?
    var cpuLoad: Double
    var memoryUsed: UInt64
    var memoryTotal: UInt64
    var diskUsed: UInt64
    var diskTotal: UInt64
    var fanPercent: Double?
    var fanRPM: Double?
    var batteryPercent: Double?
    var batteryIsCharging: Bool
    var batteryIsConnected: Bool
    var batteryHealthPercent: Double?
    var batteryCycleCount: Int?
    var ecFirmware: String?
    var controlAvailability: ControlAvailability

    static let placeholder = HardwareSnapshot(
        timestamp: .now,
        cpuTemperature: 62,
        cpuPackagePower: 11.8,
        cpuLoad: 0.24,
        memoryUsed: 15 * 1_073_741_824,
        memoryTotal: 32 * 1_073_741_824,
        diskUsed: 49 * 1_073_741_824,
        diskTotal: 512 * 1_073_741_824,
        fanPercent: nil,
        fanRPM: nil,
        batteryPercent: 0.67,
        batteryIsCharging: false,
        batteryIsConnected: true,
        batteryHealthPercent: nil,
        batteryCycleCount: nil,
        ecFirmware: nil,
        controlAvailability: .monitorOnly(reason: "EC bridge is not installed")
    )
}

enum ControlAvailability: Codable, Sendable, Equatable {
    case available(firmware: String)
    case monitorOnly(reason: String)

    var isWritable: Bool {
        if case .available = self { return true }
        return false
    }

    var message: String {
        switch self {
        case .available(let firmware): return "Controls enabled • \(firmware)"
        case .monitorOnly(let reason): return "Monitor only • \(reason)"
        }
    }
}

enum PerformanceProfile: String, CaseIterable, Identifiable, Codable, Sendable {
    case eco = "Eco"
    case comfort = "Comfort"
    case sport = "Sport"
    case turbo = "Turbo"

    var id: String { rawValue }
}

enum CoolingMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case auto = "Auto"
    case silent = "Silent"
    case boost = "Boost"
    case custom = "Custom"

    var id: String { rawValue }
}

extension Double {
    var percentText: String { "\(Int((self * 100).rounded()))%" }
}
