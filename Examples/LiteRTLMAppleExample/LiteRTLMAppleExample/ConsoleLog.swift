import Foundation

enum ConsoleLog {
    private static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func info(_ message: @autoclosure () -> String, category: String = "App") {
        emit(level: "INFO", category: category, message: message())
    }

    static func error(_ message: @autoclosure () -> String, category: String = "App") {
        emit(level: "ERROR", category: category, message: message())
    }

    static func debug(_ message: @autoclosure () -> String, category: String = "App") {
        emit(level: "DEBUG", category: category, message: message())
    }

    static func preview(_ text: String, limit: Int = 240) -> String {
        let normalized = text.replacingOccurrences(of: "\n", with: "\\n")
        guard normalized.count > limit else { return normalized }
        return "\(normalized.prefix(limit))..."
    }

    private static func emit(level: String, category: String, message: String) {
        let timestamp = formatter.string(from: Date())
        print("[LiteRTLMAppleExample][\(timestamp)][\(level)][\(category)] \(message)")
    }
}
