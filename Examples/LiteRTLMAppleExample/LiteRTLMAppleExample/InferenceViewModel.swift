import Foundation

@MainActor
final class InferenceViewModel: ObservableObject {
    @Published private(set) var selectedModel: ExampleModelDescriptor = ExampleModelCatalog.defaultModel
    @Published var prompt = "Explain why running LiteRT-LM locally on iPhone, iPad, Apple TV, or Mac can be useful in three short sentences."
    @Published private(set) var localModelURL: URL?
    @Published private(set) var downloadProgress: ModelDownloadProgress?
    @Published private(set) var response = ""
    @Published private(set) var benchmark: InferenceBenchmark?
    @Published private(set) var errorMessage = ""
    @Published private(set) var isDownloading = false
    @Published private(set) var isRunning = false

    private let modelStore: ModelStore
    private let runtime: LiteRTLMRuntimeProtocol
    private let automation = SampleAutomation.current
    private var hasStarted = false
    private var hasAttemptedAutomationDownload = false
    private var hasAttemptedAutomationInference = false

    init(
        modelStore: ModelStore = ModelStore(),
        runtime: LiteRTLMRuntimeProtocol = LiteRTLMRuntime()
    ) {
        self.modelStore = modelStore
        self.runtime = runtime
        ConsoleLog.info(
            "Initialized with default model \(selectedModel.displayName) (\(selectedModel.fileName), \(selectedModel.sizeDescription)).",
            category: "ViewModel"
        )
        if automation.isEnabled {
            ConsoleLog.info("Launch automation is enabled: \(automation.summary).", category: "Automation")
        }
    }

    var statusTitle: String {
        if isRunning {
            return "Running Inference"
        }

        if isDownloading {
            return "Downloading Model"
        }

        if localModelURL != nil {
            return "Ready"
        }

        return "Not Downloaded"
    }

    var statusMessage: String {
        if isRunning {
            return "The selected model is loaded from local storage and the prompt is executing on-device."
        }

        if let downloadProgress {
            return "Downloading \(downloadProgress.completedDescription) of \(downloadProgress.totalDescription)."
        }

        if localModelURL != nil {
            return "The model is available locally and ready for inference."
        }

        return "Download the selected `.litertlm` file to begin."
    }

    var statusAccentName: String {
        if isRunning {
            return "Cedar"
        }

        if isDownloading {
            return "Amber"
        }

        if localModelURL != nil {
            return "Forest"
        }

        return "Slate"
    }

    var localModelPath: String {
        localModelURL?.path ?? "No local model downloaded yet."
    }

    var canDownloadSelectedModel: Bool {
        !isDownloading && !isRunning && localModelURL == nil
    }

    var canDeleteSelectedModel: Bool {
        !isDownloading && !isRunning && localModelURL != nil
    }

    var canRunInference: Bool {
        !isDownloading &&
        !isRunning &&
        localModelURL != nil &&
        !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func startIfNeeded() {
        guard !hasStarted else { return }
        hasStarted = true
        applyAutomationConfigurationIfNeeded()
        ConsoleLog.info("App startup detected. Refreshing local model state.", category: "ViewModel")
        refreshLocalModelState()
        runAutomationIfNeeded(trigger: "startup")
    }

    func selectModel(_ model: ExampleModelDescriptor) {
        guard model != selectedModel else { return }
        ConsoleLog.info(
            "Selected model changed to \(model.displayName) (\(model.fileName), source=\(model.downloadURL.absoluteString)).",
            category: "ViewModel"
        )
        selectedModel = model
        response = ""
        benchmark = nil
        errorMessage = ""
        downloadProgress = nil
        refreshLocalModelState()
    }

    func setPrompt(_ newPrompt: String, source: String) {
        guard newPrompt != prompt else { return }
        prompt = newPrompt
        ConsoleLog.info(
            "Prompt updated from \(source). chars=\(newPrompt.count) preview=\(ConsoleLog.preview(newPrompt)).",
            category: "ViewModel"
        )
    }

    func downloadSelectedModel() {
        guard !isDownloading else { return }

        errorMessage = ""
        response = ""
        benchmark = nil
        isDownloading = true
        ConsoleLog.info(
            "Starting download for \(selectedModel.displayName) from \(selectedModel.downloadURL.absoluteString).",
            category: "ViewModel"
        )
        downloadProgress = ModelDownloadProgress(
            completedBytes: 0,
            totalBytes: selectedModel.sizeInBytes
        )

        Task {
            do {
                let downloadedURL = try await modelStore.download(selectedModel) { progress in
                    self.downloadProgress = progress
                }

                localModelURL = downloadedURL
                ConsoleLog.info(
                    "Download completed for \(self.selectedModel.displayName). Local path=\(downloadedURL.path).",
                    category: "ViewModel"
                )
            } catch is CancellationError {
                errorMessage = "The model download was cancelled."
                ConsoleLog.error(errorMessage, category: "ViewModel")
            } catch {
                errorMessage = Self.describe(error)
                localModelURL = nil
                ConsoleLog.error(
                    "Download failed for \(self.selectedModel.displayName): \(errorMessage)",
                    category: "ViewModel"
                )
            }

            isDownloading = false

            if localModelURL == nil {
                downloadProgress = nil
            } else {
                runAutomationIfNeeded(trigger: "download-complete")
            }
        }
    }

    func deleteSelectedModel() {
        do {
            ConsoleLog.info("Deleting local copy for \(selectedModel.displayName).", category: "ViewModel")
            try modelStore.delete(selectedModel)
            localModelURL = nil
            response = ""
            benchmark = nil
            errorMessage = ""
            downloadProgress = nil
            ConsoleLog.info("Deleted local model copy for \(selectedModel.displayName).", category: "ViewModel")
        } catch {
            errorMessage = Self.describe(error)
            ConsoleLog.error(
                "Failed to delete local copy for \(selectedModel.displayName): \(errorMessage)",
                category: "ViewModel"
            )
        }
    }

    func runInference() {
        guard !isRunning else { return }

        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else {
            errorMessage = "Enter a prompt before starting inference."
            ConsoleLog.error(errorMessage, category: "ViewModel")
            return
        }

        guard let localModelURL else {
            errorMessage = "Download the selected model before running inference."
            ConsoleLog.error(errorMessage, category: "ViewModel")
            return
        }

        errorMessage = ""
        response = ""
        benchmark = nil
        isRunning = true
        ConsoleLog.info(
            "Running inference with model=\(selectedModel.displayName) prompt_chars=\(trimmedPrompt.count) prompt_preview=\(ConsoleLog.preview(trimmedPrompt)).",
            category: "ViewModel"
        )

        Task {
            do {
                let result = try await runtime.generateResponse(
                    modelURL: localModelURL,
                    cacheDirectory: modelStore.cacheDirectory,
                    prompt: trimmedPrompt
                )

                response = result.text
                benchmark = result.benchmark
                ConsoleLog.info(
                    "Inference completed. response_chars=\(result.text.count) response_preview=\(ConsoleLog.preview(result.text)).",
                    category: "ViewModel"
                )
                if let benchmark = result.benchmark {
                    ConsoleLog.info(
                        "Benchmark init=\(benchmark.initializationDescription) ttft=\(benchmark.timeToFirstTokenDescription).",
                        category: "ViewModel"
                    )
                }
            } catch {
                errorMessage = Self.describe(error)
                ConsoleLog.error("Inference failed: \(errorMessage)", category: "ViewModel")
            }

            isRunning = false
        }
    }

    private func refreshLocalModelState() {
        do {
            localModelURL = try modelStore.localURLIfPresent(for: selectedModel)
            if let localModelURL {
                ConsoleLog.info(
                    "Found local model for \(selectedModel.displayName) at \(localModelURL.path).",
                    category: "ViewModel"
                )
            } else {
                ConsoleLog.info(
                    "No local model present for \(selectedModel.displayName).",
                    category: "ViewModel"
                )
            }
        } catch {
            errorMessage = Self.describe(error)
            localModelURL = nil
            ConsoleLog.error(
                "Failed to refresh local model state for \(selectedModel.displayName): \(errorMessage)",
                category: "ViewModel"
            )
        }
    }

    private func applyAutomationConfigurationIfNeeded() {
        guard automation.isEnabled else { return }

        if let requestedModel = automation.requestedModel {
            if requestedModel == selectedModel {
                ConsoleLog.debug(
                    "Automation requested model \(requestedModel.displayName), which is already selected.",
                    category: "Automation"
                )
            } else {
                ConsoleLog.info(
                    "Automation selected model \(requestedModel.displayName) (\(requestedModel.fileName)).",
                    category: "Automation"
                )
                selectedModel = requestedModel
                response = ""
                benchmark = nil
                errorMessage = ""
                downloadProgress = nil
            }
        } else if let requestedModelName = automation.requestedModelName {
            ConsoleLog.error(
                "Automation requested unknown model '\(requestedModelName)'. Using default selection instead.",
                category: "Automation"
            )
        }

        if let promptOverride = automation.promptOverride,
           promptOverride != prompt {
            setPrompt(promptOverride, source: "launch automation")
        }
    }

    private func runAutomationIfNeeded(trigger: String) {
        guard automation.isEnabled else { return }

        if automation.autoDownload,
           localModelURL == nil,
           !isDownloading,
           !hasAttemptedAutomationDownload {
            hasAttemptedAutomationDownload = true
            ConsoleLog.info(
                "Automation requested model download during \(trigger).",
                category: "Automation"
            )
            downloadSelectedModel()
            return
        }

        if automation.autoRunInference,
           localModelURL != nil,
           !isRunning,
           !hasAttemptedAutomationInference {
            hasAttemptedAutomationInference = true
            ConsoleLog.info(
                "Automation requested inference during \(trigger).",
                category: "Automation"
            )
            runInference()
        }
    }

    private static func describe(_ error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription {
            return description
        }

        return String(describing: error)
    }
}

private struct SampleAutomation {
    let autoDownload: Bool
    let autoRunInference: Bool
    let promptOverride: String?
    let requestedModelName: String?

    static let current = SampleAutomation(processInfo: .processInfo)

    init(processInfo: ProcessInfo) {
        let environment = processInfo.environment
        autoDownload = Self.flag("LITERT_SAMPLE_AUTO_DOWNLOAD", in: environment)
        autoRunInference = Self.flag("LITERT_SAMPLE_AUTO_RUN_INFERENCE", in: environment)
        promptOverride = Self.trimmedValue(for: "LITERT_SAMPLE_PROMPT", in: environment)
        requestedModelName = Self.trimmedValue(for: "LITERT_SAMPLE_MODEL", in: environment)
    }

    var isEnabled: Bool {
        autoDownload || autoRunInference || promptOverride != nil || requestedModelName != nil
    }

    var requestedModel: ExampleModelDescriptor? {
        guard let requestedModelName else { return nil }

        return ExampleModelCatalog.all.first { model in
            model.fileName.caseInsensitiveCompare(requestedModelName) == .orderedSame ||
            model.displayName.caseInsensitiveCompare(requestedModelName) == .orderedSame
        }
    }

    var summary: String {
        var parts: [String] = []
        if autoDownload {
            parts.append("auto_download=true")
        }
        if autoRunInference {
            parts.append("auto_run_inference=true")
        }
        if let requestedModelName {
            parts.append("model=\(requestedModelName)")
        }
        if let promptOverride {
            parts.append("prompt_chars=\(promptOverride.count)")
        }
        return parts.joined(separator: ", ")
    }

    private static func flag(_ key: String, in environment: [String: String]) -> Bool {
        guard let value = environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
            return false
        }

        return value == "1" || value == "true" || value == "yes" || value == "on"
    }

    private static func trimmedValue(for key: String, in environment: [String: String]) -> String? {
        guard let rawValue = environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawValue.isEmpty else {
            return nil
        }

        return rawValue
    }
}
