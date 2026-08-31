import Foundation

enum SharedSnapshotStore {
    private static let suiteName = "com.grazt.R3Control.shared"
    private static let snapshotKey = "latestHardwareSnapshot"

    static func save(_ snapshot: HardwareSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults(suiteName: suiteName)?.set(data, forKey: snapshotKey)
    }

    static func load() -> HardwareSnapshot {
        guard
            let data = UserDefaults(suiteName: suiteName)?.data(forKey: snapshotKey),
            let value = try? JSONDecoder().decode(HardwareSnapshot.self, from: data)
        else { return .placeholder }
        return value
    }
}
