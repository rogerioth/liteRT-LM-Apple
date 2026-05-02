import Foundation

struct PhaseTiming {
    private let label: String
    private let category: String
    private let startedAt: TimeInterval
    private var previousAt: TimeInterval

    init(_ label: String, category: String, startedAt: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        self.label = label
        self.category = category
        self.startedAt = startedAt
        self.previousAt = startedAt
    }

    mutating func mark(_ phase: String, metadata: String? = nil) {
        let now = ProcessInfo.processInfo.systemUptime
        let elapsed = now - previousAt
        let total = now - startedAt
        previousAt = now

        ConsoleLog.info(
            "TIMING \(label) phase=\(phase) elapsed=\(Self.format(elapsed)) total=\(Self.format(total))\(Self.metadataSuffix(metadata)).",
            category: category
        )
    }

    static func log(_ label: String, phase: String, elapsed: TimeInterval, category: String, metadata: String? = nil) {
        ConsoleLog.info(
            "TIMING \(label) phase=\(phase) elapsed=\(Self.format(elapsed))\(Self.metadataSuffix(metadata)).",
            category: category
        )
    }

    static func format(_ seconds: TimeInterval) -> String {
        String(format: "%.3fs", seconds)
    }

    private static func metadataSuffix(_ metadata: String?) -> String {
        guard let metadata, !metadata.isEmpty else { return "" }
        return " \(metadata)"
    }
}
