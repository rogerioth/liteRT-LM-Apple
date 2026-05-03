import Darwin
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
            "TIMING \(label) phase=\(phase) elapsed=\(Self.format(elapsed)) total=\(Self.format(total))\(Self.metadataSuffix(metadata))\(Self.metadataSuffix(ProcessMemory.currentMetadata())).",
            category: category
        )
    }

    static func log(_ label: String, phase: String, elapsed: TimeInterval, category: String, metadata: String? = nil) {
        ConsoleLog.info(
            "TIMING \(label) phase=\(phase) elapsed=\(Self.format(elapsed))\(Self.metadataSuffix(metadata))\(Self.metadataSuffix(ProcessMemory.currentMetadata())).",
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

private enum ProcessMemory {
    static func currentMetadata() -> String? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), reboundPointer, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            return "memory_query_error=\(result)"
        }

        return [
            "memory_phys_footprint=\(formatBytes(info.phys_footprint))",
            "memory_resident=\(formatBytes(info.resident_size))",
            "memory_resident_peak=\(formatBytes(info.resident_size_peak))",
            "memory_virtual=\(formatBytes(info.virtual_size))",
            "device_physical_memory=\(formatBytes(ProcessInfo.processInfo.physicalMemory))",
        ].joined(separator: " ")
    }

    private static func formatBytes<T: BinaryInteger>(_ bytes: T) -> String {
        String(format: "%.1fMB", Double(Int64(bytes)) / 1_048_576.0)
    }
}
