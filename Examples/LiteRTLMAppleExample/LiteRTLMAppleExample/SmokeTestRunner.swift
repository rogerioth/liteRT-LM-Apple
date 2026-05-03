import Darwin
import Foundation

#if DEBUG
enum SmokeTestRunner {
    private static let smokeTestFlag = "--smoke-test"

    static func runIfRequested(arguments: [String] = ProcessInfo.processInfo.arguments) {
        guard arguments.contains(smokeTestFlag) else { return }

        Task.detached(priority: .userInitiated) {
            let exitCode = await run(arguments: arguments)
            fflush(stdout)
            fflush(stderr)
            exit(exitCode)
        }
    }

    private static func run(arguments: [String]) async -> Int32 {
        var timing = PhaseTiming("smoke_test", category: "SmokeTest")
        do {
            let model = try modelDescriptor(from: value(after: "--smoke-model", in: arguments))
            let imageURL = try imageURL(from: value(after: "--smoke-image", in: arguments))
            let prompt = value(after: "--smoke-prompt", in: arguments) ?? "What is this?"
            let store = ModelStore()
            timing.mark("arguments_resolved")

            ConsoleLog.info(
                "SMOKE_TEST starting model=\(model.displayName) image=\(imageURL.path) prompt=\(ConsoleLog.preview(prompt)).",
                category: "SmokeTest"
            )

            guard let modelURL = try store.localURLIfPresent(for: model) else {
                throw SmokeTestError("Missing local model for \(model.displayName). Expected \(store.localURL(for: model).path).")
            }
            timing.mark("model_lookup", metadata: "model_bytes=\(try fileSize(at: modelURL))")

            let rawImageData = try Data(contentsOf: imageURL)
            ConsoleLog.info(
                "SMOKE_TEST loaded image raw_bytes=\(rawImageData.count).",
                category: "SmokeTest"
            )
            timing.mark("image_load", metadata: "raw_bytes=\(rawImageData.count)")
            let normalizedImageData = try ImageDataNormalizer.makePNGData(from: rawImageData)
            timing.mark("image_normalize", metadata: "png_bytes=\(normalizedImageData.count)")
            let result = try await LiteRTLMRuntime().generateResponse(
                modelURL: modelURL,
                cacheDirectory: store.cacheDirectory,
                inputs: InferenceInputs(prompt: prompt, imageData: normalizedImageData),
                options: LiteRTLMRuntimeOptions()
            )
            timing.mark("generate_response", metadata: "response_chars=\(result.text.count)")

            ConsoleLog.info(
                "SMOKE_TEST PASS model=\(model.displayName) response_chars=\(result.text.count) response_preview=\(ConsoleLog.preview(result.text)).",
                category: "SmokeTest"
            )
            if let benchmark = result.benchmark {
                ConsoleLog.info(
                    "SMOKE_TEST benchmark init=\(benchmark.initializationDescription) ttft=\(benchmark.timeToFirstTokenDescription) prefill=[\(benchmark.prefillDescription)] decode=[\(benchmark.decodeDescription)].",
                    category: "SmokeTest"
                )
            }
            timing.mark("total", metadata: "response_chars=\(result.text.count)")
            return 0
        } catch {
            timing.mark("failure")
            ConsoleLog.error("SMOKE_TEST FAIL \(describe(error)).", category: "SmokeTest")
            return 1
        }
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag),
              arguments.indices.contains(index + 1)
        else {
            return nil
        }
        return arguments[index + 1]
    }

    private static func modelDescriptor(from value: String?) throws -> ExampleModelDescriptor {
        switch value?.lowercased() {
        case nil, "e4b", "gemma-4-e4b", "gemma4e4b":
            return ExampleModelCatalog.gemma4E4B
        case "e2b", "gemma-4-e2b", "gemma4e2b":
            return ExampleModelCatalog.gemma4E2B
        default:
            throw SmokeTestError("Unknown smoke model '\(value ?? "")'. Use e2b or e4b.")
        }
    }

    private static func imageURL(from value: String?) throws -> URL {
        guard let value, !value.isEmpty else {
            throw SmokeTestError("Missing --smoke-image path.")
        }

        if value.hasPrefix("/") {
            return URL(fileURLWithPath: value)
        }

        let fileManager = FileManager.default
        let searchRoots = [
            fileManager.urls(for: .documentDirectory, in: .userDomainMask).first,
            fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
            fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first,
            URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true),
        ].compactMap { $0 }

        for root in searchRoots {
            let candidate = root.appendingPathComponent(value, isDirectory: false)
            if fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
        }

        return URL(fileURLWithPath: value)
    }

    private static func describe(_ error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription {
            return description
        }

        return String(describing: error)
    }

    private static func fileSize(at url: URL) throws -> UInt64 {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        return UInt64(values.fileSize ?? 0)
    }
}

private struct SmokeTestError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? {
        message
    }
}
#endif
