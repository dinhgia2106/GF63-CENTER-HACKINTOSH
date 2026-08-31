import Foundation
import IOKit
import IOKit.ps
import Darwin.Mach

enum SystemIdentity {
    static let productFamily = "MSI GF63 Series"

    static var modelIdentifier: String {
        sysctlString("hw.model") ?? "Unknown"
    }

    static var cpuName: String {
        sysctlString("machdep.cpu.brand_string") ?? "Intel CPU"
    }

    static var cpuTopology: String {
        let physical = sysctlInteger("hw.physicalcpu")
        let logical = sysctlInteger("hw.logicalcpu")
        guard physical > 0, logical > 0 else { return "Unknown topology" }
        return "\(physical)C/\(logical)T"
    }

    static var osSummary: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }

    static var architecture: String {
#if arch(x86_64)
        return "x86_64"
#elseif arch(arm64)
        return "arm64"
#else
        return "Unknown architecture"
#endif
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 1 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    private static func sysctlInteger(_ name: String) -> Int {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return 0 }
        return Int(value)
    }
}

final class SMCReader: @unchecked Sendable {
    func double(_ key: String) -> Double? {
        var result = 0.0
        let ok = key.withCString { R3SMCReadDouble($0, &result) }
        return ok && result.isFinite ? result : nil
    }

    func uint8(_ key: String) -> UInt8? {
        var result: UInt8 = 0
        let ok = key.withCString { R3SMCReadUInt8($0, &result) }
        return ok ? result : nil
    }

    deinit { R3SMCClose() }
}

final class CPULoadReader: @unchecked Sendable {
    private var previous: [UInt32]?

    func sample() -> Double {
        var cpuInfo: processor_info_array_t?
        var count: mach_msg_type_number_t = 0
        var cpuCount: natural_t = 0
        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &cpuCount,
            &cpuInfo,
            &count
        )
        guard result == KERN_SUCCESS, let cpuInfo else { return 0 }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: cpuInfo), vm_size_t(count) * vm_size_t(MemoryLayout<integer_t>.stride))
        }

        let values = (0..<Int(count)).map { UInt32(bitPattern: cpuInfo[$0]) }
        guard let previous, previous.count == values.count else {
            self.previous = values
            return 0
        }

        var used: UInt64 = 0
        var total: UInt64 = 0
        for cpu in 0..<Int(cpuCount) {
            let base = cpu * Int(CPU_STATE_MAX)
            let user = UInt64(values[base + Int(CPU_STATE_USER)] &- previous[base + Int(CPU_STATE_USER)])
            let system = UInt64(values[base + Int(CPU_STATE_SYSTEM)] &- previous[base + Int(CPU_STATE_SYSTEM)])
            let nice = UInt64(values[base + Int(CPU_STATE_NICE)] &- previous[base + Int(CPU_STATE_NICE)])
            let idle = UInt64(values[base + Int(CPU_STATE_IDLE)] &- previous[base + Int(CPU_STATE_IDLE)])
            used += user + system + nice
            total += user + system + nice + idle
        }
        self.previous = values
        return total == 0 ? 0 : min(max(Double(used) / Double(total), 0), 1)
    }
}

enum MemoryReader {
    static func sample() -> (used: UInt64, total: UInt64) {
        let total = ProcessInfo.processInfo.physicalMemory
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return (0, total) }
        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)
        let page = UInt64(pageSize)
        let free = UInt64(stats.free_count + stats.speculative_count) * page
        return (total > free ? total - free : 0, total)
    }
}

enum DiskReader {
    static func sample() -> (used: UInt64, total: UInt64) {
        guard let values = try? FileManager.default.attributesOfFileSystem(forPath: "/"),
              let total = values[.systemSize] as? NSNumber,
              let free = values[.systemFreeSize] as? NSNumber else { return (0, 0) }
        let totalValue = total.uint64Value
        return (totalValue - free.uint64Value, totalValue)
    }
}

struct BatterySample: Sendable {
    var percent: Double?
    var isCharging = false
    var isConnected = false
    var healthPercent: Double?
    var cycleCount: Int?
}

enum BatteryReader {
    static func sample() -> BatterySample {
        guard
            let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef],
            let source = sources.first,
            let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any]
        else { return BatterySample() }

        let current = (description[kIOPSCurrentCapacityKey] as? NSNumber)?.doubleValue
        let max = (description[kIOPSMaxCapacityKey] as? NSNumber)?.doubleValue
        let percent = current.flatMap { value in max.flatMap { $0 > 0 ? value / $0 : nil } }
        let state = description[kIOPSPowerSourceStateKey] as? String
        let charging = (description[kIOPSIsChargingKey] as? Bool) ?? false

        let registry = registryDetails()
        return BatterySample(
            percent: percent,
            isCharging: charging,
            isConnected: state == kIOPSACPowerValue,
            healthPercent: registry.healthPercent,
            cycleCount: registry.cycleCount
        )
    }

    private static func registryDetails() -> (healthPercent: Double?, cycleCount: Int?) {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != IO_OBJECT_NULL else { return (nil, nil) }
        defer { IOObjectRelease(service) }

        var unmanaged: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &unmanaged, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let properties = unmanaged?.takeRetainedValue() as? [String: Any] else {
            return (nil, nil)
        }

        let cycleCount = (properties["CycleCount"] as? NSNumber)?.intValue
        let design = (properties["DesignCapacity"] as? NSNumber)?.doubleValue
        let maximum = (properties["MaxCapacity"] as? NSNumber)?.doubleValue
        let health: Double?
        if let design, let maximum, design > 0 {
            health = min(max(maximum / design, 0), 1)
        } else {
            health = nil
        }
        return (health, cycleCount)
    }
}
