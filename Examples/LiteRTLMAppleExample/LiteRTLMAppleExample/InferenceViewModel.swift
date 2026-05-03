import Foundation

@MainActor
final class InferenceViewModel: ObservableObject {
    @Published private(set) var selectedModel: ExampleModelDescriptor = ExampleModelCatalog.defaultModel
    @Published var prompt = "Explain why running LiteRT-LM locally on iPhone, iPad, or Mac can be useful in three short sentences."
    @Published private(set) var localModelURL: URL?
    @Published private(set) var downloadProgress: ModelDownloadProgress?
    @Published private(set) var response = ""
    @Published private(set) var benchmark: InferenceBenchmark?
    @Published private(set) var errorMessage = ""
    @Published private(set) var isDownloading = false
    @Published private(set) var isRunning = false
    @Published private(set) var attachedImageData: Data?

    private let modelStore: ModelStore
    private let runtime: LiteRTLMRuntimeProtocol
    private var hasStarted = false

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

    func startIfNeeded() {
        guard !hasStarted else { return }
        hasStarted = true
        ConsoleLog.info("App startup detected. Refreshing local model state.", category: "ViewModel")
        refreshLocalModelState()
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
        attachedImageData = nil
        refreshLocalModelState()
    }

    func attachImage(_ data: Data) {
        attachedImageData = data
        errorMessage = ""
        ConsoleLog.info("Attached image (\(data.count) bytes).", category: "ViewModel")
    }

    func clearAttachedImage() {
        guard attachedImageData != nil else { return }
        attachedImageData = nil
        ConsoleLog.info("Cleared attached image.", category: "ViewModel")
    }

    func setExamplePromptForAttachedImage() {
        prompt = "What is this?"
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
            attachedImageData = nil
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

        let inputs = InferenceInputs(prompt: trimmedPrompt, imageData: attachedImageData)

        errorMessage = ""
        response = ""
        benchmark = nil
        isRunning = true
        ConsoleLog.info(
            "Running inference with model=\(selectedModel.displayName) prompt_chars=\(trimmedPrompt.count) image_bytes=\(inputs.imageData?.count ?? 0) prompt_preview=\(ConsoleLog.preview(trimmedPrompt)).",
            category: "ViewModel"
        )

        Task {
            do {
                let result = try await runtime.generateResponse(
                    modelURL: localModelURL,
                    cacheDirectory: modelStore.cacheDirectory,
                    inputs: inputs,
                    options: LiteRTLMRuntimeOptions()
                )

                response = result.text
                benchmark = result.benchmark
                ConsoleLog.info(
                    "Inference completed. response_chars=\(result.text.count) response_preview=\(ConsoleLog.preview(result.text)).",
                    category: "ViewModel"
                )
                if let benchmark = result.benchmark {
                    ConsoleLog.info(
                        "Benchmark init=\(benchmark.initializationDescription) ttft=\(benchmark.timeToFirstTokenDescription) prefill=[\(benchmark.prefillDescription)] decode=[\(benchmark.decodeDescription)].",
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

    private static func describe(_ error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription {
            return description
        }

        return String(describing: error)
    }
}
