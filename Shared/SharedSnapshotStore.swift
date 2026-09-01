import Foundation

enum SharedSnapshotStore {
    static let suiteName = "group.com.grazt.R3Control"
    private static let snapshotKey = "latestHardwareSnapshot"

    static func save(_ snapshot: HardwareSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults(suiteName: suiteName)?.set(data, forKey: snapshotKey)
    }

    static func load() -> HardwareSnapshot? {
        guard
            let data = UserDefaults(suiteName: suiteName)?.data(forKey: snapshotKey),
            let value = try? JSONDecoder().decode(HardwareSnapshot.self, from: data)
        else { return nil }
        return value
    }
}
