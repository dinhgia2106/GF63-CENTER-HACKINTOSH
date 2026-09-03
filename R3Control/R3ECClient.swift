import Foundation

struct R3DirectBatteryReading: Sendable {
    let percent: Double
    let healthPercent: Double
    let cycleCount: Int?
    let isCharging: Bool
    let isDischarging: Bool
    let presentRate: UInt32
    let voltage: UInt32
    let powerUnit: UInt8
}

struct R3ECReading: Sendable {
    let firmware: String
    let cpuTemperature: Double?
    let fanPercent: Double?
    let fanRPM: Double?
    let fanModeRaw: UInt8
    let coolerBoost: Bool
    let performanceProfileRaw: UInt8
    let packagePowerLimit1: Double?
    let packagePowerLimit2: Double?
    let ecoPlusActive: Bool
    let powerLimitLocked: Bool
    let chargeLimit: Int?
    let chargeLimitSupported: Bool
    let directBattery: R3DirectBatteryReading?
    let writable: Bool
}

final class R3ECClient {
    func read() -> (reading: R3ECReading?, result: Int32) {
        var raw = R3ECStatus()
        let result = R3ECReadStatus(&raw)
        guard result == 0, (1...5).contains(raw.protocolVersion) else { return (nil, result) }

        let firmware = withUnsafeBytes(of: &raw.firmware) { bytes in
            String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }
        let directBattery: R3DirectBatteryReading?
        if raw.protocolVersion >= 4,
           raw.batteryDataValid != 0,
           raw.batteryLastFullChargeCapacity > 0,
           raw.batteryDesignCapacity > 0 {
            directBattery = R3DirectBatteryReading(
                percent: min(max(
                    Double(raw.batteryRemainingCapacity) / Double(raw.batteryLastFullChargeCapacity),
                    0
                ), 1),
                healthPercent: min(max(
                    Double(raw.batteryLastFullChargeCapacity) / Double(raw.batteryDesignCapacity),
                    0
                ), 1),
                cycleCount: raw.protocolVersion >= 5 && raw.batteryCycleCountValid != 0
                    ? Int(raw.batteryCycleCount) : nil,
                isCharging: (raw.batteryState & 0x02) != 0,
                isDischarging: (raw.batteryState & 0x01) != 0,
                presentRate: raw.batteryPresentRate,
                voltage: raw.batteryPresentVoltage,
                powerUnit: raw.batteryPowerUnit
            )
        } else {
            directBattery = nil
        }
        let reading = R3ECReading(
            firmware: firmware,
            cpuTemperature: raw.cpuTemperature > 0 ? Double(raw.cpuTemperature) : nil,
            fanPercent: raw.fanPercent <= 100 ? Double(raw.fanPercent) : nil,
            fanRPM: raw.fanRPM > 0 ? Double(raw.fanRPM) : nil,
            fanModeRaw: raw.fanModeRaw,
            coolerBoost: raw.coolerBoost != 0,
            performanceProfileRaw: raw.performanceProfileRaw,
            packagePowerLimit1: raw.packagePowerLimit1Deciwatts > 0
                ? Double(raw.packagePowerLimit1Deciwatts) / 10 : nil,
            packagePowerLimit2: raw.packagePowerLimit2Deciwatts > 0
                ? Double(raw.packagePowerLimit2Deciwatts) / 10 : nil,
            ecoPlusActive: raw.ecoPlusActive != 0,
            powerLimitLocked: raw.powerLimitLocked != 0,
            chargeLimit: raw.chargeLimit > 0 ? Int(raw.chargeLimit) : nil,
            chargeLimitSupported: (raw.capabilities & (1 << 5)) != 0,
            directBattery: directBattery,
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

    func setChargeLimit(_ percent: Int) -> Int32 {
        R3ECApplyChargeLimit(UInt8(clamping: percent))
    }

    func setPerformanceProfile(_ profile: PerformanceProfile) -> Int32 {
        let value: UInt8
        switch profile {
        case .ecoPlus: value = 0
        case .eco: value = 0
        case .comfort: value = 1
        case .sport: value = 2
        case .turbo: value = 3
        }
        return R3ECApplyPerformanceProfile(value)
    }

    func setEcoPlus(_ enabled: Bool) -> Int32 {
        R3ECApplyEcoPlus(enabled)
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
