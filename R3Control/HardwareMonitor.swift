import Combine
import Foundation
import WidgetKit

@MainActor
final class HardwareMonitor: ObservableObject {
    @Published private(set) var snapshot = HardwareSnapshot.placeholder
    @Published private(set) var history: [HardwareSnapshot] = []
    @Published private(set) var lastError: String?

    private let smc = SMCReader()
    private let cpu = CPULoadReader()
    private var timer: AnyCancellable?

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
    }

    func refresh() {
        let memory = MemoryReader.sample()
        let disk = DiskReader.sample()
        let battery = BatteryReader.sample()
        let fanCount = smc.uint8("FNum") ?? 0
        let fanRPM = fanCount > 0 ? smc.double("F0Ac") : nil
        let fanMaximumRPM = fanCount > 0 ? smc.double("F0Mx") : nil
        let fanPercent = fanRPM.flatMap { current in
            fanMaximumRPM.flatMap { maximum in
                maximum > 0 ? min(max(current / maximum * 100, 0), 100) : nil
            }
        }

        let next = HardwareSnapshot(
            timestamp: .now,
            cpuTemperature: smc.double("TC0P") ?? smc.double("TC0D"),
            cpuPackagePower: smc.double("PC0C") ?? smc.double("PCPR"),
            cpuLoad: cpu.sample(),
            memoryUsed: memory.used,
            memoryTotal: memory.total,
            diskUsed: disk.used,
            diskTotal: disk.total,
            fanPercent: fanPercent,
            fanRPM: fanRPM,
            batteryPercent: battery.percent,
            batteryIsCharging: battery.isCharging,
            batteryIsConnected: battery.isConnected,
            batteryHealthPercent: battery.healthPercent,
            batteryCycleCount: battery.cycleCount,
            ecFirmware: nil,
            controlAvailability: .monitorOnly(reason: "R3EC bridge is unavailable")
        )

        snapshot = next
        history.append(next)
        if history.count > 300 { history.removeFirst(history.count - 300) }
        SharedSnapshotStore.save(next)
        WidgetCenter.shared.reloadTimelines(ofKind: "R3StatusWidget")
    }
}
