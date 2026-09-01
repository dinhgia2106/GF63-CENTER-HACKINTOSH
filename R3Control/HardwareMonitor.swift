import Combine
import Foundation
import WidgetKit

@MainActor
final class HardwareMonitor: ObservableObject {
    @Published private(set) var snapshot = HardwareSnapshot.placeholder
    @Published private(set) var history: [HardwareSnapshot] = []
    @Published private(set) var lastError: String?
    @Published private(set) var lastControlMessage: String?

    private let smc = SMCReader()
    private let ec = R3ECClient()
    private let cpu = CPULoadReader()
    private var timer: AnyCancellable?
    private var pendingCoolingApply: Task<Void, Never>?

    func start() {
        guard timer == nil else { return }
        refresh()
        timer = Timer.publish(every: 2, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.refresh() }
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
        let ecResult = ec.read()
        let ecReading = ecResult.reading
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
        WidgetCenter.shared.reloadTimelines(ofKind: "R3StatusWidget")
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

    func applySavedConfiguration(_ configuration: ControlConfiguration) {
        applyCooling(configuration)
    }

    func restoreFirmwareAuto() {
        pendingCoolingApply?.cancel()
        pendingCoolingApply = nil
        if finish(ec.restoreAuto(), action: "Firmware Auto restored") {
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
}
