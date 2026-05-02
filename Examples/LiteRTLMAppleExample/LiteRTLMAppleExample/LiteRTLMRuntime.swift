import Foundation
import LiteRTLMApple

struct InferenceBenchmark: Sendable {
    let initializationSeconds: Double
    let timeToFirstTokenSeconds: Double

    var initializationDescription: String {
        String(format: "%.2fs", initializationSeconds)
    }

    var timeToFirstTokenDescription: String {
        String(format: "%.2fs", timeToFirstTokenSeconds)
    }
}

struct InferenceResult: Sendable {
    let text: String
    let benchmark: InferenceBenchmark?
}

struct InferenceInputs: Sendable {
    let prompt: String
    let imageData: Data?
}

protocol LiteRTLMRuntimeProtocol: Sendable {
    func generateResponse(
        modelURL: URL,
        cacheDirectory: URL,
        inputs: InferenceInputs
    ) async throws -> InferenceResult
}

struct LiteRTLMRuntime: LiteRTLMRuntimeProtocol {
    func generateResponse(
        modelURL: URL,
        cacheDirectory: URL,
        inputs: InferenceInputs
    ) async throws -> InferenceResult {
        ConsoleLog.info(
            "Queueing inference task. model=\(modelURL.path) cache=\(cacheDirectory.path) prompt_chars=\(inputs.prompt.count) image_bytes=\(inputs.imageData?.count ?? 0).",
            category: "Runtime"
        )
        return try await Task.detached(priority: .userInitiated) {
            try generateResponseSynchronously(
                modelURL: modelURL,
                cacheDirectory: cacheDirectory,
                inputs: inputs
            )
        }.value
    }

    private func generateResponseSynchronously(
        modelURL: URL,
        cacheDirectory: URL,
        inputs: InferenceInputs
    ) throws -> InferenceResult {
        ConsoleLog.info(
            "Starting synchronous inference. model=\(modelURL.path) cache=\(cacheDirectory.path) image_attached=\(inputs.imageData != nil).",
            category: "Runtime"
        )
        ConsoleLog.debug("Prompt preview=\(ConsoleLog.preview(inputs.prompt)).", category: "Runtime")
#if DEBUG
        let environment = ProcessInfo.processInfo.environment
#else
        let environment: [String: String] = [:]
#endif
        // 0=VERBOSE, 1=DEBUG, 2=INFO, 3=WARNING, 4=ERROR, 5=FATAL, 1000=SILENT.
        let minLogLevel = environment["LITERT_LM_MIN_LOG_LEVEL"].flatMap(Int32.init) ?? 3
        litert_lm_set_min_log_level(minLogLevel)

        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        ConsoleLog.debug("Ensured runtime cache directory exists.", category: "Runtime")

        let backendName = environment["LITERT_LM_BACKEND"] ?? "cpu"
        let normalizedBackendName = backendName.trimmingCharacters(in: .whitespacesAndNewlines)
        let visionBackendName = environment["LITERT_LM_VISION_BACKEND"] ?? "cpu"
        let normalizedVisionBackendName = visionBackendName.trimmingCharacters(in: .whitespacesAndNewlines)
        let usesVisionBackend = !normalizedVisionBackendName.isEmpty
            && normalizedVisionBackendName.lowercased() != "none"

        let settings = modelURL.path.withCString { modelPathPointer in
            backendName.withCString { backendPointer in
                if usesVisionBackend {
                    return normalizedVisionBackendName.withCString { visionBackendPointer in
                        litert_lm_engine_settings_create(
                            modelPathPointer,
                            backendPointer,
                            visionBackendPointer,
                            nil
                        )
                    }
                } else {
                    return litert_lm_engine_settings_create(
                        modelPathPointer,
                        backendPointer,
                        nil,
                        nil
                    )
                }
            }
        }

        guard let settings else {
            throw LiteRTLMRuntimeError("Failed to create LiteRT-LM engine settings.")
        }
        defer { litert_lm_engine_settings_delete(settings) }
        ConsoleLog.info(
            "Created engine settings backend=\(backendName) vision_backend=\(usesVisionBackend ? normalizedVisionBackendName : "none").",
            category: "Runtime"
        )

        let runtimeLibraryDirectory = Self.runtimeLibraryDirectory()
        runtimeLibraryDirectory.path.withCString { runtimeLibraryDirectoryPointer in
            litert_lm_engine_settings_set_runtime_library_dir(settings, runtimeLibraryDirectoryPointer)
        }
        ConsoleLog.info(
            "Configured LiteRT runtime library directory=\(runtimeLibraryDirectory.path).",
            category: "Runtime"
        )

        let maxNumImages = environment["LITERT_LM_MAX_NUM_IMAGES"].flatMap(Int32.init) ?? 1
        litert_lm_engine_settings_set_max_num_images(settings, maxNumImages)

        if let activationDataType = environment["LITERT_LM_ACTIVATION_DATA_TYPE"].flatMap(Int32.init) {
            litert_lm_engine_settings_set_activation_data_type(settings, activationDataType)
        }
        if let mainActivationDataType = environment["LITERT_LM_MAIN_ACTIVATION_DATA_TYPE"].flatMap(Int32.init) {
            litert_lm_engine_settings_set_main_activation_data_type(settings, mainActivationDataType)
        }
        if let visionActivationDataType = environment["LITERT_LM_VISION_ACTIVATION_DATA_TYPE"].flatMap(Int32.init) {
            litert_lm_engine_settings_set_vision_activation_data_type(settings, visionActivationDataType)
        }
        if let audioActivationDataType = environment["LITERT_LM_AUDIO_ACTIVATION_DATA_TYPE"].flatMap(Int32.init) {
            litert_lm_engine_settings_set_audio_activation_data_type(settings, audioActivationDataType)
        }

        if let maxNumTokens = environment["LITERT_LM_MAX_NUM_TOKENS"].flatMap(Int32.init) {
            litert_lm_engine_settings_set_max_num_tokens(settings, maxNumTokens)
        }

        if let prefillChunkSize = environment["LITERT_LM_PREFILL_CHUNK_SIZE"].flatMap(Int32.init) {
            litert_lm_engine_settings_set_prefill_chunk_size(settings, prefillChunkSize)
        }

        if let rawPrefillBatchSizes = environment["LITERT_LM_PREFILL_BATCH_SIZES"] {
            if let prefillBatchSizes = Self.prefillBatchSizes(rawPrefillBatchSizes) {
                prefillBatchSizes.withUnsafeBufferPointer { buffer in
                    litert_lm_engine_settings_set_prefill_batch_sizes(
                        settings,
                        buffer.baseAddress,
                        Int32(buffer.count)
                    )
                }
            } else {
                ConsoleLog.error(
                    "Ignoring invalid LITERT_LM_PREFILL_BATCH_SIZES=\(rawPrefillBatchSizes).",
                    category: "Runtime"
                )
            }
        }

        for advancedBoolSetting in Self.advancedBoolSettings {
            if let rawValue = environment[advancedBoolSetting.environmentKey] {
                if let enabled = Bool(rawValue) {
                    litert_lm_engine_settings_set_advanced_bool(
                        settings,
                        advancedBoolSetting.option,
                        enabled
                    )
                } else {
                    ConsoleLog.error(
                        "Ignoring invalid \(advancedBoolSetting.environmentKey)=\(rawValue).",
                        category: "Runtime"
                    )
                }
            }
        }

        if let externalTensorMode = environment["LITERT_LM_GPU_EXTERNAL_TENSOR_MODE"].flatMap(Bool.init) {
            litert_lm_engine_settings_set_gpu_external_tensor_mode(settings, externalTensorMode)
        }
        if let hintKernelBatchSize = environment["LITERT_LM_GPU_HINT_KERNEL_BATCH_SIZE"].flatMap(Int32.init) {
            litert_lm_engine_settings_set_gpu_hint_kernel_batch_size(settings, hintKernelBatchSize)
        }

        let defaultCPUKernelModeName = Self.defaultCPUKernelModeName(
            modelURL: modelURL,
            backendName: normalizedBackendName,
            visionBackendName: usesVisionBackend ? normalizedVisionBackendName : nil
        )
        let cpuKernelModeName = environment["LITERT_LM_CPU_KERNEL_MODE"] ?? defaultCPUKernelModeName
        if let cpuKernelMode = Self.cpuKernelModeValue(cpuKernelModeName) {
            litert_lm_engine_settings_set_cpu_kernel_mode(settings, cpuKernelMode)
        } else if let cpuKernelModeName, !cpuKernelModeName.isEmpty {
            ConsoleLog.error(
                "Ignoring invalid LITERT_LM_CPU_KERNEL_MODE=\(cpuKernelModeName).",
                category: "Runtime"
            )
        }

        if let parallelLoading = environment["LITERT_LM_PARALLEL_LOADING"].flatMap(Bool.init) {
            litert_lm_engine_settings_set_parallel_file_section_loading(settings, parallelLoading)
        }

        let benchmarkEnabled = environment["LITERT_LM_BENCHMARK"].flatMap(Bool.init) ?? true
        if benchmarkEnabled {
            litert_lm_engine_settings_enable_benchmark(settings)
        }
        let advancedLog = Self.advancedBoolSettings
            .map { "\($0.environmentKey)=\(environment[$0.environmentKey] ?? "default")" }
            .joined(separator: " ")
        ConsoleLog.debug(
            "Applied engine settings: max_num_images=\(maxNumImages) activation_data_type=\(environment["LITERT_LM_ACTIVATION_DATA_TYPE"] ?? "default") main_activation_data_type=\(environment["LITERT_LM_MAIN_ACTIVATION_DATA_TYPE"] ?? "default") vision_activation_data_type=\(environment["LITERT_LM_VISION_ACTIVATION_DATA_TYPE"] ?? "default") audio_activation_data_type=\(environment["LITERT_LM_AUDIO_ACTIVATION_DATA_TYPE"] ?? "default") max_num_tokens=\(environment["LITERT_LM_MAX_NUM_TOKENS"] ?? "default") prefill_chunk_size=\(environment["LITERT_LM_PREFILL_CHUNK_SIZE"] ?? "default") prefill_batch_sizes=\(environment["LITERT_LM_PREFILL_BATCH_SIZES"] ?? "default") gpu_external_tensor_mode=\(environment["LITERT_LM_GPU_EXTERNAL_TENSOR_MODE"] ?? "default") gpu_hint_kernel_batch_size=\(environment["LITERT_LM_GPU_HINT_KERNEL_BATCH_SIZE"] ?? "default") cpu_kernel_mode=\(cpuKernelModeName ?? "default") parallel_loading=\(environment["LITERT_LM_PARALLEL_LOADING"] ?? "default") benchmark=\(benchmarkEnabled ? "enabled" : "disabled") \(advancedLog).",
            category: "Runtime"
        )

        cacheDirectory.path.withCString { cachePointer in
            litert_lm_engine_settings_set_cache_dir(settings, cachePointer)
        }
        ConsoleLog.debug("Configured engine cache directory.", category: "Runtime")

        guard let engine = litert_lm_engine_create(settings) else {
            throw LiteRTLMRuntimeError("Failed to create LiteRT-LM engine.")
        }
        defer { litert_lm_engine_delete(engine) }
        ConsoleLog.info("Created LiteRT-LM engine.", category: "Runtime")

        guard let sessionConfig = litert_lm_session_config_create() else {
            throw LiteRTLMRuntimeError("Failed to create LiteRT-LM session config.")
        }
        defer { litert_lm_session_config_delete(sessionConfig) }
        ConsoleLog.info("Created session config.", category: "Runtime")

        litert_lm_session_config_set_max_output_tokens(sessionConfig, 256)
        ConsoleLog.debug("Configured session max_output_tokens=256.", category: "Runtime")

        guard let conversationConfig = litert_lm_conversation_config_create() else {
            throw LiteRTLMRuntimeError("Failed to create LiteRT-LM conversation config.")
        }
        defer { litert_lm_conversation_config_delete(conversationConfig) }

        litert_lm_conversation_config_set_session_config(conversationConfig, sessionConfig)

        let systemMessageJSON =
            #"{"type":"text","text":"You are a concise assistant running entirely on-device. Answer clearly and directly."}"#
        systemMessageJSON.withCString { pointer in
            litert_lm_conversation_config_set_system_message(conversationConfig, pointer)
        }
        ConsoleLog.info("Configured conversation config (session + system message).", category: "Runtime")

        guard let conversation = litert_lm_conversation_create(engine, conversationConfig) else {
            throw LiteRTLMRuntimeError("Failed to create LiteRT-LM conversation.")
        }
        defer { litert_lm_conversation_delete(conversation) }
        ConsoleLog.info("Created LiteRT-LM conversation.", category: "Runtime")

        let messageJSON = try Self.makeUserMessageJSON(inputs: inputs)
        let extraContextJSON = #"{"enable_thinking":false}"#
        ConsoleLog.debug("Message JSON=\(ConsoleLog.preview(messageJSON, limit: 200)).", category: "Runtime")
        ConsoleLog.debug("Extra context JSON=\(extraContextJSON).", category: "Runtime")

        let generatedText = try messageJSON.withCString { messagePointer -> String in
            try extraContextJSON.withCString { extraContextPointer -> String in
                guard let response = litert_lm_conversation_send_message(
                    conversation,
                    messagePointer,
                    extraContextPointer
                ) else {
                    throw LiteRTLMRuntimeError("LiteRT-LM returned no response object.")
                }
                defer { litert_lm_json_response_delete(response) }

                guard let responsePointer = litert_lm_json_response_get_string(response) else {
                    throw LiteRTLMRuntimeError("LiteRT-LM returned an empty response pointer.")
                }

                let rawJSON = String(cString: responsePointer)
                ConsoleLog.debug(
                    "Raw response JSON=\(ConsoleLog.preview(rawJSON, limit: 400)).",
                    category: "Runtime"
                )
                return try Self.extractText(fromConversationResponseJSON: rawJSON)
            }
        }
        ConsoleLog.info(
            "Extracted response text (\(generatedText.count) chars). preview=\(ConsoleLog.preview(generatedText)).",
            category: "Runtime"
        )

        let benchmark: InferenceBenchmark?
        if let benchmarkInfo = litert_lm_conversation_get_benchmark_info(conversation) {
            defer { litert_lm_benchmark_info_delete(benchmarkInfo) }
            benchmark = InferenceBenchmark(
                initializationSeconds: litert_lm_benchmark_info_get_total_init_time_in_second(benchmarkInfo),
                timeToFirstTokenSeconds: litert_lm_benchmark_info_get_time_to_first_token(benchmarkInfo)
            )
            if let benchmark {
                ConsoleLog.info(
                    "Benchmark collected. init=\(benchmark.initializationDescription) ttft=\(benchmark.timeToFirstTokenDescription).",
                    category: "Runtime"
                )
            }
        } else {
            benchmark = nil
            ConsoleLog.debug("No benchmark info returned by conversation.", category: "Runtime")
        }

        return InferenceResult(text: generatedText, benchmark: benchmark)
    }

    static func makeUserMessageJSON(inputs: InferenceInputs) throws -> String {
        var contentParts: [[String: Any]] = []
        if let imageData = inputs.imageData {
            contentParts.append([
                "type": "image",
                "blob": imageData.base64EncodedString(),
            ])
        }
        contentParts.append([
            "type": "text",
            "text": inputs.prompt,
        ])

        let message: [String: Any] = [
            "role": "user",
            "content": contentParts,
        ]

        let data = try JSONSerialization.data(
            withJSONObject: message,
            options: [.sortedKeys]
        )

        guard let string = String(data: data, encoding: .utf8) else {
            throw LiteRTLMRuntimeError("Failed to encode the message JSON as UTF-8.")
        }

        return string
    }

    private static func extractText(fromConversationResponseJSON json: String) throws -> String {
        let jsonData = Data(json.utf8)
        let object = try JSONSerialization.jsonObject(with: jsonData)

        guard let message = object as? [String: Any] else {
            throw LiteRTLMRuntimeError("LiteRT-LM returned a non-object JSON response.")
        }

        let extractedText: String
        if let contentItems = message["content"] as? [[String: Any]] {
            extractedText = contentItems
                .compactMap { item in
                    guard (item["type"] as? String) == "text" else { return nil }
                    return item["text"] as? String
                }
                .joined()
        } else if let content = message["content"] as? [String: Any],
                  let text = content["text"] as? String {
            extractedText = text
        } else if let content = message["content"] as? String {
            extractedText = content
        } else {
            throw LiteRTLMRuntimeError("LiteRT-LM returned JSON without text content.")
        }

        let normalizedText = extractedText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedText.isEmpty else {
            throw LiteRTLMRuntimeError("LiteRT-LM returned empty text content.")
        }

        return normalizedText
    }

    private static func defaultCPUKernelModeName(
        modelURL: URL,
        backendName: String,
        visionBackendName: String?
    ) -> String? {
        let usesMainCPU = backendName.lowercased() == "cpu"
        let usesVisionGPU = visionBackendName?.lowercased() == "gpu"
        let modelName = modelURL.lastPathComponent.lowercased()
        guard usesMainCPU, usesVisionGPU, modelName.contains("e4b") else { return nil }
        return "builtin"
    }

    private static func cpuKernelModeValue(_ value: String?) -> Int32? {
        guard let value else { return nil }
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "0", "xnnpack":
            return 0
        case "1", "reference":
            return 1
        case "2", "builtin", "built-in":
            return 2
        default:
            return nil
        }
    }

    private static func prefillBatchSizes(_ value: String) -> [Int32]? {
        let parts = value.split(separator: ",", omittingEmptySubsequences: false)
        guard !parts.isEmpty else { return nil }
        var sizes: [Int32] = []
        sizes.reserveCapacity(parts.count)
        for part in parts {
            let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let size = Int32(trimmed), size > 0 else { return nil }
            sizes.append(size)
        }
        return sizes.isEmpty ? nil : sizes
    }

    private static let advancedBoolSettings: [(environmentKey: String, option: Int32)] = [
        ("LITERT_LM_CLEAR_KV_CACHE_BEFORE_PREFILL", 0),
        ("LITERT_LM_GPU_MADVISE_ORIGINAL_SHARED_TENSORS", 1),
        ("LITERT_LM_GPU_CONVERT_WEIGHTS_ON_GPU", 2),
        ("LITERT_LM_GPU_WAIT_FOR_WEIGHTS_CONVERSION_COMPLETE_IN_BENCHMARK", 3),
        ("LITERT_LM_GPU_OPTIMIZE_SHADER_COMPILATION", 4),
        ("LITERT_LM_GPU_CACHE_COMPILED_SHADERS_ONLY", 5),
        ("LITERT_LM_GPU_SHARE_CONSTANT_TENSORS", 6),
        ("LITERT_LM_SAMPLER_HANDLES_INPUT", 7),
        ("LITERT_LM_GPU_ALLOW_SRC_QUANTIZED_FC_CONV_OPS", 8),
        ("LITERT_LM_GPU_HINT_WAITING_FOR_COMPLETION", 9),
        ("LITERT_LM_GPU_CONTEXT_LOW_PRIORITY", 10),
        ("LITERT_LM_GPU_DISABLE_DELEGATE_CLUSTERING", 11),
    ]

    private static func runtimeLibraryDirectory() -> URL {
        let fileManager = FileManager.default
        let frameworkDirectory = Bundle.main.bundleURL.appendingPathComponent("Frameworks", isDirectory: true)
        let candidates = [
            Bundle.main.privateFrameworksURL,
            frameworkDirectory,
            Bundle.main.bundleURL,
        ].compactMap { $0 }

        return candidates.first {
            fileManager.fileExists(
                atPath: $0.appendingPathComponent("libLiteRtMetalAccelerator.dylib").path
            )
        } ?? Bundle.main.privateFrameworksURL ?? frameworkDirectory
    }
}

private struct LiteRTLMRuntimeError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? {
        message
    }
}
