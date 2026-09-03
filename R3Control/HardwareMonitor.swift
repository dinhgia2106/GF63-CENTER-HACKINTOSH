import Combine
import Foundation
import WidgetKit

@MainActor
final class HardwareMonitor: ObservableObject {
    @Published private(set) var snapshot = HardwareSnapshot.placeholder
    @Published private(set) var history: [HardwareSnapshot] = []
    @Published private(set) var lastError: String?
    @Published private(set) var lastControlMessage: String?
    @Published private(set) var activePerformanceProfile: PerformanceProfile?
    @Published private(set) var packagePowerLimit1: Double?
    @Published private(set) var packagePowerLimit2: Double?
    @Published private(set) var ecoPlusActive = false
    @Published private(set) var powerLimitLocked = false
    @Published private(set) var chargeLimit: Int?
    @Published private(set) var chargeLimitSupported = false
    @Published private(set) var batteryTelemetryNotice: String?

    private let smc = SMCReader()
    private let ec = R3ECClient()
    private let cpu = CPULoadReader()
    private var timer: AnyCancellable?
    private var pendingCoolingApply: Task<Void, Never>?
    private var lastWidgetReload = Date.distantPast
    private var configuredPerformanceProfile: PerformanceProfile?
    private var configuredCoolingMode: CoolingMode?

    func start(configuration: ControlConfiguration) {
        configuredPerformanceProfile = configuration.profile
        configuredCoolingMode = configuration.coolingMode
        guard timer == nil else { return }
        refresh()
        configureTimer(every: 2)
    }

    func stop() {
        timer?.cancel()
        timer = nil
        pendingCoolingApply?.cancel()
        pendingCoolingApply = nil
        if snapshot.controlAvailability.isWritable {
            _ = ec.restoreAuto()
        }
        ec.close()
    }

    func refresh() {
        let memory = MemoryReader.sample()
        let disk = DiskReader.sample()
        let battery = BatteryReader.sample()
        batteryTelemetryNotice = battery.telemetryNotice
        let ecResult = ec.read()
        let ecReading = ecResult.reading
        packagePowerLimit1 = ecReading?.packagePowerLimit1
        packagePowerLimit2 = ecReading?.packagePowerLimit2
        ecoPlusActive = ecReading?.ecoPlusActive ?? false
        powerLimitLocked = ecReading?.powerLimitLocked ?? false
        chargeLimit = ecReading?.chargeLimit
        chargeLimitSupported = ecReading?.chargeLimitSupported ?? false
        activePerformanceProfile = ecReading.flatMap { reading in
            switch reading.performanceProfileRaw {
            case 0xC2: return reading.ecoPlusActive ? .ecoPlus : .eco
            case 0xC1: return .comfort
            case 0xC0: return .sport
            case 0xC4: return .turbo
            default: return nil
            }
        }
        let activeCoolingMode = ecReading.flatMap { reading -> CoolingMode? in
            if reading.coolerBoost { return .boost }
            switch reading.fanModeRaw & 0xFC {
            case 0x0C: return .auto
            case 0x1C: return .silent
            case 0x4C, 0x8C: return .custom
            default: return nil
            }
        }
        let fanCount = smc.uint8("FNum") ?? 0
        let smcFanRPM = fanCount > 0 ? smc.double("F0Ac") : nil
        let fanMaximumRPM = fanCount > 0 ? smc.double("F0Mx") : nil
        let smcFanPercent = smcFanRPM.flatMap { current in
            fanMaximumRPM.flatMap { maximum in
                maximum > 0 ? min(max(current / maximum * 100, 0), 100) : nil
            }
        }
        let availability: ControlAvailability
        if let ecReading {
            availability = ecReading.writable
                ? .available(firmware: ecReading.firmware)
                : .monitorOnly(reason: "unsupported EC firmware \(ecReading.firmware)")
        } else {
            availability = .monitorOnly(reason: "R3EC kext is not loaded or the app is not entitled")
        }

        let next = HardwareSnapshot(
            timestamp: .now,
            cpuTemperature: ecReading?.cpuTemperature ?? smc.double("TC0P") ?? smc.double("TC0D"),
            cpuPackagePower: smc.double("PC0C") ?? smc.double("PCPR"),
            cpuLoad: cpu.sample(),
            memoryUsed: memory.used,
            memoryTotal: memory.total,
            diskUsed: disk.used,
            diskTotal: disk.total,
            fanPercent: ecReading?.fanPercent ?? smcFanPercent,
            fanRPM: ecReading?.fanRPM ?? smcFanRPM,
            performanceProfile: activePerformanceProfile ?? configuredPerformanceProfile,
            coolingMode: activeCoolingMode ?? configuredCoolingMode,
            batteryPercent: battery.percent,
            batteryIsCharging: battery.isCharging,
            batteryIsConnected: battery.isConnected,
            batteryHealthPercent: battery.healthPercent,
            batteryCycleCount: battery.cycleCount,
            ecFirmware: ecReading?.firmware,
            controlAvailability: availability
        )

        snapshot = next
        history.append(next)
        if history.count > 300 { history.removeFirst(history.count - 300) }
        SharedSnapshotStore.save(next)
        if Date.now.timeIntervalSince(lastWidgetReload) >= 60 {
            WidgetCenter.shared.reloadTimelines(ofKind: "R3StatusWidget")
            lastWidgetReload = .now
        }
    }

    func applyCooling(_ configuration: ControlConfiguration) {
        pendingCoolingApply?.cancel()
        pendingCoolingApply = nil

        var result: Int32
        switch configuration.coolingMode {
        case .auto:
            result = ec.setCoolerBoost(false)
            if result == 0 { result = ec.setFirmwareAuto() }
        case .silent:
            result = ec.setCoolerBoost(false)
            if result == 0 { result = ec.setSilentMode() }
        case .boost:
            result = ec.setFirmwareAuto()
            if result == 0 { result = ec.setCoolerBoost(true) }
        case .custom:
            result = ec.setCoolerBoost(false)
            if result == 0 { result = ec.setFixedFanSpeed(configuration.manualFanPercent) }
        }
        if result != 0 { _ = ec.restoreAuto() }
        guard finish(result, action: "Fan behavior \(configuration.coolingMode.rawValue)") else { return }
        configuredCoolingMode = configuration.coolingMode
        refresh()
    }

    func scheduleCooling(_ configuration: ControlConfiguration) {
        pendingCoolingApply?.cancel()
        pendingCoolingApply = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(300))
            } catch {
                return
            }
            self?.applyCooling(configuration)
        }
    }

    func setPerformanceProfile(_ profile: PerformanceProfile) {
        var result: Int32
        if profile == .ecoPlus {
            result = ec.setPerformanceProfile(.eco)
            if result == 0 { result = ec.setEcoPlus(true) }
            if result == 0 { result = ec.setCoolerBoost(false) }
            if result == 0 { result = ec.setFirmwareAuto() }
        } else {
            result = ec.setEcoPlus(false)
            if result == 0 { result = ec.setPerformanceProfile(profile) }
        }
        if result != 0 {
            _ = ec.setEcoPlus(false)
            _ = ec.restoreAuto()
        }
        if finish(result, action: "Performance profile \(profile.rawValue)") {
            configuredPerformanceProfile = profile
            if profile == .ecoPlus { configuredCoolingMode = .auto }
            configureTimer(every: profile == .ecoPlus ? 10 : 2)
            refresh()
        }
    }

    @discardableResult
    func setChargeLimit(_ percent: Int) -> Bool {
        guard [60, 80, 100].contains(percent) else {
            lastError = "Charge limit failed: only the verified 60%, 80% and 100% presets are accepted."
            lastControlMessage = nil
            return false
        }
        guard chargeLimitSupported else {
            lastError = "Charge limit failed: this R3EC firmware does not expose verified charge control."
            lastControlMessage = nil
            return false
        }
        guard finish(ec.setChargeLimit(percent), action: "Charge limit \(percent)%") else {
            return false
        }
        refresh()
        return true
    }

    func applySavedConfiguration(_ configuration: ControlConfiguration) {
        setPerformanceProfile(configuration.profile)
        guard lastError == nil else { return }
        applyCooling(configuration)
    }

    func restoreFirmwareAuto() {
        pendingCoolingApply?.cancel()
        pendingCoolingApply = nil
        if finish(ec.restoreAuto(), action: "Firmware Auto restored") {
            configuredCoolingMode = .auto
            refresh()
        }
    }

    @discardableResult
    private func finish(_ result: Int32, action: String) -> Bool {
        guard result == 0 else {
            lastError = "\(action) failed: \(R3ECClient.describe(result))."
            lastControlMessage = nil
            return false
        }
        lastError = nil
        lastControlMessage = "\(action) applied and verified by EC read-back."
        return true
    }

    private func configureTimer(every interval: TimeInterval) {
        timer?.cancel()
        timer = Timer.publish(every: interval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.refresh() }
    }
}
