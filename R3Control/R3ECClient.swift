import Foundation

struct R3ECReading: Sendable {
    let firmware: String
    let cpuTemperature: Double?
    let fanPercent: Double?
    let fanRPM: Double?
    let fanModeRaw: UInt8
    let coolerBoost: Bool
    let performanceProfileRaw: UInt8
    let chargeLimit: Int?
    let writable: Bool
}

final class R3ECClient {
    func read() -> (reading: R3ECReading?, result: Int32) {
        var raw = R3ECStatus()
        let result = R3ECReadStatus(&raw)
        guard result == 0, raw.protocolVersion == 1 || raw.protocolVersion == 2 else { return (nil, result) }

        let firmware = withUnsafeBytes(of: &raw.firmware) { bytes in
            String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }
        let reading = R3ECReading(
            firmware: firmware,
            cpuTemperature: raw.cpuTemperature > 0 ? Double(raw.cpuTemperature) : nil,
            fanPercent: raw.fanPercent <= 100 ? Double(raw.fanPercent) : nil,
            fanRPM: raw.fanRPM > 0 ? Double(raw.fanRPM) : nil,
            fanModeRaw: raw.fanModeRaw,
            coolerBoost: raw.coolerBoost != 0,
            performanceProfileRaw: raw.performanceProfileRaw,
            chargeLimit: raw.chargeLimit > 0 ? Int(raw.chargeLimit) : nil,
            writable: raw.writable != 0
        )
        return (reading, result)
    }

    func setFirmwareAuto() -> Int32 {
        R3ECApplyFanMode(0)
    }

    func setSilentMode() -> Int32 {
        R3ECApplyFanMode(1)
    }

    func setFixedFanSpeed(_ percent: Int) -> Int32 {
        R3ECApplyFixedFanSpeed(UInt8(clamping: percent))
    }

    func setCoolerBoost(_ enabled: Bool) -> Int32 {
        R3ECApplyCoolerBoost(enabled)
    }

    func setPerformanceProfile(_ profile: PerformanceProfile) -> Int32 {
        let value: UInt8
        switch profile {
        case .eco: value = 0
        case .comfort: value = 1
        case .sport: value = 2
        case .turbo: value = 3
        }
        return R3ECApplyPerformanceProfile(value)
    }

    func restoreAuto() -> Int32 {
        R3ECRestoreAuto()
    }

    func close() {
        R3ECClose()
    }

    static func describe(_ result: Int32) -> String {
        switch UInt32(bitPattern: result) {
        case 0: return "OK"
        case 0xE00002C1: return "R3EC rejected the app entitlement"
        case 0xE00002F0: return "R3EC service was not found"
        case 0xE00002C7: return "The EC command is unsupported"
        case 0xE00002E2: return "The EC command is not permitted for this firmware"
        case 0xE00002C2: return "The EC command or value is invalid"
        default: return String(format: "IOKit error 0x%08X", UInt32(bitPattern: result))
        }
    }
}
