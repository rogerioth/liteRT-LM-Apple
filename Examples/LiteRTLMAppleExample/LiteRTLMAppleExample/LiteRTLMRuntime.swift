import Foundation
import LiteRTLMApple

struct InferenceBenchmark: Sendable {
    let initializationSeconds: Double
    let timeToFirstTokenSeconds: Double
    let prefillTurns: [InferenceBenchmarkTurn]
    let decodeTurns: [InferenceBenchmarkTurn]

    var initializationDescription: String {
        String(format: "%.2fs", initializationSeconds)
    }

    var timeToFirstTokenDescription: String {
        String(format: "%.2fs", timeToFirstTokenSeconds)
    }

    var prefillDescription: String {
        Self.turnsDescription(prefillTurns)
    }

    var decodeDescription: String {
        Self.turnsDescription(decodeTurns)
    }

    private static func turnsDescription(_ turns: [InferenceBenchmarkTurn]) -> String {
        guard !turns.isEmpty else { return "none" }
        return turns.enumerated()
            .map { index, turn in
                "turn\(index)=\(turn.tokenCount)t/\(turn.tokensPerSecondDescription)/\(turn.durationDescription)"
            }
            .joined(separator: ",")
    }
}

struct InferenceBenchmarkTurn: Sendable {
    let tokenCount: Int
    let tokensPerSecond: Double

    var durationSeconds: Double? {
        guard tokensPerSecond > 0 else { return nil }
        return Double(tokenCount) / tokensPerSecond
    }

    var tokensPerSecondDescription: String {
        String(format: "%.2ftps", tokensPerSecond)
    }

    var durationDescription: String {
        guard let durationSeconds else { return "n/a" }
        return String(format: "%.2fs", durationSeconds)
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
        inputs: InferenceInputs,
        options: LiteRTLMRuntimeOptions
    ) async throws -> InferenceResult
}

extension LiteRTLMRuntimeProtocol {
    func generateResponse(
        modelURL: URL,
        cacheDirectory: URL,
        inputs: InferenceInputs
    ) async throws -> InferenceResult {
        try await generateResponse(
            modelURL: modelURL,
            cacheDirectory: cacheDirectory,
            inputs: inputs,
            options: LiteRTLMRuntimeOptions()
        )
    }
}

struct LiteRTLMRuntime: LiteRTLMRuntimeProtocol {
    func generateResponse(
        modelURL: URL,
        cacheDirectory: URL,
        inputs: InferenceInputs,
        options: LiteRTLMRuntimeOptions
    ) async throws -> InferenceResult {
        ConsoleLog.info(
            "Queueing inference task. model=\(modelURL.path) cache=\(cacheDirectory.path) prompt_chars=\(inputs.prompt.count) image_bytes=\(inputs.imageData?.count ?? 0).",
            category: "Runtime"
        )
        let queuedAt = ProcessInfo.processInfo.systemUptime
        return try await Task.detached(priority: .userInitiated) {
            try generateResponseSynchronously(
                modelURL: modelURL,
                cacheDirectory: cacheDirectory,
                inputs: inputs,
                options: options,
                queuedAt: queuedAt
            )
        }.value
    }

    private func generateResponseSynchronously(
        modelURL: URL,
        cacheDirectory: URL,
        inputs: InferenceInputs,
        options: LiteRTLMRuntimeOptions,
        queuedAt: TimeInterval? = nil
    ) throws -> InferenceResult {
        let startedAt = ProcessInfo.processInfo.systemUptime
        if let queuedAt {
            PhaseTiming.log(
                "runtime",
                phase: "task_queue_wait",
                elapsed: startedAt - queuedAt,
                category: "Runtime"
            )
        }
        var timing = PhaseTiming("runtime", category: "Runtime", startedAt: startedAt)
        ConsoleLog.info(
            "Starting synchronous inference. model=\(modelURL.path) cache=\(cacheDirectory.path) image_attached=\(inputs.imageData != nil).",
            category: "Runtime"
        )
        ConsoleLog.debug("Prompt preview=\(ConsoleLog.preview(inputs.prompt)).", category: "Runtime")

        let runtimeCacheDirectory = Self.runtimeCacheDirectory(
            baseDirectory: cacheDirectory,
            options: options
        )
        litert_lm_set_min_log_level(options.minLogLevel.rawValue)

        try FileManager.default.createDirectory(at: runtimeCacheDirectory, withIntermediateDirectories: true)
        ConsoleLog.debug(
            "Ensured runtime cache directory exists at \(runtimeCacheDirectory.path).",
            category: "Runtime"
        )
        timing.mark("cache_prepare")

        let backend = options.backend
        let resolvedVisionBackend = Self.resolvedVisionBackend(
            options: options,
            modelURL: modelURL,
            hasImage: inputs.imageData != nil
        )
        let visionBackendSource = options.visionBackend == nil ? "default" : "options"
        let backendName = backend.name
        let visionBackendName = resolvedVisionBackend?.name ?? "none"

        let settings = modelURL.path.withCString { modelPathPointer in
            backendName.withCString { backendPointer in
                if let visionBackend = resolvedVisionBackend {
                    return visionBackend.name.withCString { visionBackendPointer in
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
            "Created engine settings backend=\(backendName) vision_backend=\(visionBackendName)(\(visionBackendSource)).",
            category: "Runtime"
        )
        timing.mark("engine_settings_create")

        let runtimeLibraryDirectory = Self.runtimeLibraryDirectory()
        runtimeLibraryDirectory.path.withCString { runtimeLibraryDirectoryPointer in
            litert_lm_engine_settings_set_runtime_library_dir(settings, runtimeLibraryDirectoryPointer)
        }
        ConsoleLog.info(
            "Configured LiteRT runtime library directory=\(runtimeLibraryDirectory.path).",
            category: "Runtime"
        )

        litert_lm_engine_settings_set_max_num_images(settings, options.maxNumImages)

        if let activationDataType = options.activationDataType {
            litert_lm_engine_settings_set_activation_data_type(settings, activationDataType.rawValue)
        }
        let resolvedMainActivationDataType = Self.resolvedMainActivationDataType(
            options: options,
            backend: backend
        )
        if let resolvedMainActivationDataType {
            litert_lm_engine_settings_set_main_activation_data_type(settings, resolvedMainActivationDataType.rawValue)
        }
        if let visionActivationDataType = options.visionActivationDataType {
            litert_lm_engine_settings_set_vision_activation_data_type(settings, visionActivationDataType.rawValue)
        }
        if let audioActivationDataType = options.audioActivationDataType {
            litert_lm_engine_settings_set_audio_activation_data_type(settings, audioActivationDataType.rawValue)
        }

        let resolvedMaxNumTokens = Self.resolvedMaxNumTokens(options: options, backend: backend)
        if let resolvedMaxNumTokens {
            litert_lm_engine_settings_set_max_num_tokens(settings, resolvedMaxNumTokens)
        }

        if let prefillChunkSize = options.prefillChunkSize {
            litert_lm_engine_settings_set_prefill_chunk_size(settings, prefillChunkSize)
        }

        if let prefillBatchSizes = options.prefillBatchSizes, !prefillBatchSizes.isEmpty {
            prefillBatchSizes.withUnsafeBufferPointer { buffer in
                litert_lm_engine_settings_set_prefill_batch_sizes(
                    settings,
                    buffer.baseAddress,
                    Int32(buffer.count)
                )
            }
        }

        let resolvedAdvancedBools = Self.advancedBoolDescriptors.map { descriptor in
            (descriptor: descriptor,
             resolved: descriptor.resolve(options: options.advanced, modelURL: modelURL, backend: backend))
        }
        for entry in resolvedAdvancedBools {
            if let value = entry.resolved?.value {
                litert_lm_engine_settings_set_advanced_bool(
                    settings,
                    entry.descriptor.option,
                    value
                )
            }
        }
        let resolvedVisionGpuBools = Self.visionGpuBoolDescriptors.map { descriptor in
            (descriptor: descriptor,
             resolved: descriptor.resolve(options: options.visionGPU, visionBackend: resolvedVisionBackend))
        }
        for entry in resolvedVisionGpuBools {
            if let value = entry.resolved?.value {
                litert_lm_engine_settings_set_vision_gpu_bool(
                    settings,
                    entry.descriptor.option,
                    value
                )
            }
        }

        if let externalTensorMode = options.gpuExternalTensorMode {
            litert_lm_engine_settings_set_gpu_external_tensor_mode(settings, externalTensorMode)
        }
        if let hintKernelBatchSize = options.gpuHintKernelBatchSize {
            litert_lm_engine_settings_set_gpu_hint_kernel_batch_size(settings, hintKernelBatchSize)
        }

        let resolvedCpuKernelMode = Self.resolvedCpuKernelMode(
            options: options,
            modelURL: modelURL,
            backend: backend,
            visionBackend: resolvedVisionBackend
        )
        if let resolvedCpuKernelMode {
            litert_lm_engine_settings_set_cpu_kernel_mode(settings, resolvedCpuKernelMode.rawValue)
        }

        if let parallelLoading = options.parallelLoading {
            litert_lm_engine_settings_set_parallel_file_section_loading(settings, parallelLoading)
        }

        if options.benchmark {
            litert_lm_engine_settings_enable_benchmark(settings)
        }
        let advancedLog = resolvedAdvancedBools
            .map { "\($0.descriptor.name)=\($0.resolved?.formatted ?? "unset")" }
            .joined(separator: " ")
        let visionGpuLog = resolvedVisionGpuBools
            .map { "\($0.descriptor.name)=\($0.resolved?.formatted ?? "unset")" }
            .joined(separator: " ")
        let coreLog = [
            "max_num_images=\(options.maxNumImages)",
            "max_num_tokens=\(formatOptional(resolvedMaxNumTokens))",
            "activation_data_type=\(formatOptional(options.activationDataType))",
            "main_activation_data_type=\(formatOptional(resolvedMainActivationDataType))",
            "vision_activation_data_type=\(formatOptional(options.visionActivationDataType))",
            "audio_activation_data_type=\(formatOptional(options.audioActivationDataType))",
            "prefill_chunk_size=\(formatOptional(options.prefillChunkSize))",
            "prefill_batch_sizes=\(options.prefillBatchSizes.map { $0.map(String.init).joined(separator: ",") } ?? "unset")",
            "gpu_external_tensor_mode=\(formatOptional(options.gpuExternalTensorMode))",
            "gpu_hint_kernel_batch_size=\(formatOptional(options.gpuHintKernelBatchSize))",
            "cpu_kernel_mode=\(formatOptional(resolvedCpuKernelMode))",
            "parallel_loading=\(formatOptional(options.parallelLoading))",
            "benchmark=\(options.benchmark ? "enabled" : "disabled")",
            "cache_subdirectory=\(options.cacheSubdirectory ?? "unset")",
        ].joined(separator: " ")
        ConsoleLog.debug("Applied engine settings: \(coreLog).", category: "Runtime")
        ConsoleLog.debug("Advanced bool settings: \(advancedLog).", category: "Runtime")
        ConsoleLog.debug("Vision-GPU bool settings: \(visionGpuLog).", category: "Runtime")

        runtimeCacheDirectory.path.withCString { cachePointer in
            litert_lm_engine_settings_set_cache_dir(settings, cachePointer)
        }
        ConsoleLog.debug("Configured engine cache directory=\(runtimeCacheDirectory.path).", category: "Runtime")
        timing.mark(
            "engine_settings_configure",
            metadata: "backend=\(backendName) vision_backend=\(visionBackendName) max_num_tokens=\(formatOptional(resolvedMaxNumTokens)) benchmark=\(options.benchmark ? "enabled" : "disabled")"
        )

        guard let engine = litert_lm_engine_create(settings) else {
            throw LiteRTLMRuntimeError("Failed to create LiteRT-LM engine.")
        }
        defer { litert_lm_engine_delete(engine) }
        ConsoleLog.info("Created LiteRT-LM engine.", category: "Runtime")
        timing.mark("engine_create")

        guard let sessionConfig = litert_lm_session_config_create() else {
            throw LiteRTLMRuntimeError("Failed to create LiteRT-LM session config.")
        }
        defer { litert_lm_session_config_delete(sessionConfig) }
        ConsoleLog.info("Created session config.", category: "Runtime")
        timing.mark("session_config_create")

        litert_lm_session_config_set_max_output_tokens(sessionConfig, 256)
        ConsoleLog.debug("Configured session max_output_tokens=256.", category: "Runtime")

        guard let conversationConfig = litert_lm_conversation_config_create() else {
            throw LiteRTLMRuntimeError("Failed to create LiteRT-LM conversation config.")
        }
        defer { litert_lm_conversation_config_delete(conversationConfig) }

        litert_lm_conversation_config_set_session_config(conversationConfig, sessionConfig)

        ConsoleLog.info("Configured conversation config (session only).", category: "Runtime")
        timing.mark("conversation_configure")

        guard let conversation = litert_lm_conversation_create(engine, conversationConfig) else {
            throw LiteRTLMRuntimeError("Failed to create LiteRT-LM conversation.")
        }
        defer { litert_lm_conversation_delete(conversation) }
        ConsoleLog.info("Created LiteRT-LM conversation.", category: "Runtime")
        timing.mark("conversation_create")

        let messageJSON = try Self.makeUserMessageJSON(inputs: inputs)
        let extraContextJSON = #"{}"#
        ConsoleLog.debug("Message JSON=\(ConsoleLog.preview(messageJSON, limit: 200)).", category: "Runtime")
        ConsoleLog.debug("Extra context JSON=\(extraContextJSON).", category: "Runtime")
        timing.mark("message_json_encode", metadata: "json_chars=\(messageJSON.count)")

        let generatedText = try messageJSON.withCString { messagePointer -> String in
            try extraContextJSON.withCString { extraContextPointer -> String in
                let sendStartedAt = ProcessInfo.processInfo.systemUptime
                guard let response = litert_lm_conversation_send_message(
                    conversation,
                    messagePointer,
                    extraContextPointer
                ) else {
                    throw LiteRTLMRuntimeError("LiteRT-LM returned no response object.")
                }
                defer { litert_lm_json_response_delete(response) }
                PhaseTiming.log(
                    "runtime",
                    phase: "conversation_send_message",
                    elapsed: ProcessInfo.processInfo.systemUptime - sendStartedAt,
                    category: "Runtime"
                )

                let parseStartedAt = ProcessInfo.processInfo.systemUptime
                guard let responsePointer = litert_lm_json_response_get_string(response) else {
                    throw LiteRTLMRuntimeError("LiteRT-LM returned an empty response pointer.")
                }

                let rawJSON = String(cString: responsePointer)
                ConsoleLog.debug(
                    "Raw response JSON=\(ConsoleLog.preview(rawJSON, limit: 400)).",
                    category: "Runtime"
                )
                let extractedText = try Self.extractText(fromConversationResponseJSON: rawJSON)
                PhaseTiming.log(
                    "runtime",
                    phase: "response_parse",
                    elapsed: ProcessInfo.processInfo.systemUptime - parseStartedAt,
                    category: "Runtime",
                    metadata: "raw_json_chars=\(rawJSON.count) response_chars=\(extractedText.count)"
                )
                return extractedText
            }
        }
        timing.mark("conversation_send_and_parse", metadata: "response_chars=\(generatedText.count)")
        ConsoleLog.info(
            "Extracted response text (\(generatedText.count) chars). preview=\(ConsoleLog.preview(generatedText)).",
            category: "Runtime"
        )

        let benchmark: InferenceBenchmark?
        if let benchmarkInfo = litert_lm_conversation_get_benchmark_info(conversation) {
            defer { litert_lm_benchmark_info_delete(benchmarkInfo) }
            let prefillTurnCount = max(0, Int(litert_lm_benchmark_info_get_num_prefill_turns(benchmarkInfo)))
            let prefillTurns = (0..<prefillTurnCount).map { index in
                InferenceBenchmarkTurn(
                    tokenCount: Int(litert_lm_benchmark_info_get_prefill_token_count_at(benchmarkInfo, Int32(index))),
                    tokensPerSecond: litert_lm_benchmark_info_get_prefill_tokens_per_sec_at(benchmarkInfo, Int32(index))
                )
            }
            let decodeTurnCount = max(0, Int(litert_lm_benchmark_info_get_num_decode_turns(benchmarkInfo)))
            let decodeTurns = (0..<decodeTurnCount).map { index in
                InferenceBenchmarkTurn(
                    tokenCount: Int(litert_lm_benchmark_info_get_decode_token_count_at(benchmarkInfo, Int32(index))),
                    tokensPerSecond: litert_lm_benchmark_info_get_decode_tokens_per_sec_at(benchmarkInfo, Int32(index))
                )
            }
            benchmark = InferenceBenchmark(
                initializationSeconds: litert_lm_benchmark_info_get_total_init_time_in_second(benchmarkInfo),
                timeToFirstTokenSeconds: litert_lm_benchmark_info_get_time_to_first_token(benchmarkInfo),
                prefillTurns: prefillTurns,
                decodeTurns: decodeTurns
            )
            if let benchmark {
                ConsoleLog.info(
                    "Benchmark collected. init=\(benchmark.initializationDescription) ttft=\(benchmark.timeToFirstTokenDescription) prefill=[\(benchmark.prefillDescription)] decode=[\(benchmark.decodeDescription)].",
                    category: "Runtime"
                )
            }
        } else {
            benchmark = nil
            ConsoleLog.debug("No benchmark info returned by conversation.", category: "Runtime")
        }
        timing.mark("benchmark_collect")
        timing.mark("total", metadata: "response_chars=\(generatedText.count)")

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

    private static func resolvedVisionBackend(
        options: LiteRTLMRuntimeOptions,
        modelURL: URL,
        hasImage: Bool
    ) -> LiteRTLMBackend? {
        if let explicit = options.visionBackend {
            return explicit
        }
        guard hasImage else { return nil }
        // Gemma 4 vision encoders (both E2B and E4B) produce semantically wrong
        // embeddings when run on Metal GPU with FP16 activations (the C
        // wrapper's current memory-saving default — verified by the dog photo
        // being described as "people"/"a person's face"). FP32 vision GPU is
        // correct but exceeds iOS cold-start memory limits when paired with
        // the GPU main executor. Default to CPU vision for these models to
        // preserve correctness; callers can override via options.visionBackend.
        if isGemma4Vision(modelURL: modelURL) {
            return .cpu
        }
        return options.backend == .gpu ? .gpu : .cpu
    }

    private static func resolvedMainActivationDataType(
        options: LiteRTLMRuntimeOptions,
        backend: LiteRTLMBackend
    ) -> LiteRTLMActivationDataType? {
        if let explicit = options.mainActivationDataType {
            return explicit
        }
        guard options.activationDataType == nil, backend == .gpu else { return nil }
        return .float16
    }

    private static func resolvedMaxNumTokens(
        options: LiteRTLMRuntimeOptions,
        backend: LiteRTLMBackend
    ) -> Int32? {
        if let explicit = options.maxNumTokens {
            return explicit
        }
        guard backend == .gpu else { return nil }
        return 384
    }

    private static func resolvedCpuKernelMode(
        options: LiteRTLMRuntimeOptions,
        modelURL: URL,
        backend: LiteRTLMBackend,
        visionBackend: LiteRTLMBackend?
    ) -> LiteRTLMCPUKernelMode? {
        if let explicit = options.cpuKernelMode {
            return explicit
        }
        guard backend == .cpu, visionBackend == .gpu, isE4B(modelURL: modelURL) else { return nil }
        return .builtin
    }

    private static func isE4B(modelURL: URL) -> Bool {
        modelURL.lastPathComponent.lowercased().contains("e4b")
    }

    private static func isGemma4Vision(modelURL: URL) -> Bool {
        let name = modelURL.lastPathComponent.lowercased()
        return name.contains("e2b") || name.contains("e4b")
    }

    /// Resolved value for a bool descriptor, with provenance for logging.
    private struct ResolvedBool {
        let value: Bool
        let isDefault: Bool

        var formatted: String {
            isDefault ? "\(value)(default)" : "\(value)"
        }
    }

    /// Describes one entry in the upstream "advanced" bool settings table.
    /// `getValue` reads the caller's explicit value; `getDefault` returns the
    /// runtime's per-model fallback when the caller didn't set one.
    private struct AdvancedBoolDescriptor {
        let name: String
        let option: Int32
        let getValue: @Sendable (LiteRTLMAdvancedOptions) -> Bool?
        let getDefault: @Sendable (URL, LiteRTLMBackend) -> Bool?

        func resolve(options: LiteRTLMAdvancedOptions, modelURL: URL, backend: LiteRTLMBackend) -> ResolvedBool? {
            if let explicit = getValue(options) {
                return ResolvedBool(value: explicit, isDefault: false)
            }
            if let fallback = getDefault(modelURL, backend) {
                return ResolvedBool(value: fallback, isDefault: true)
            }
            return nil
        }
    }

    private struct VisionGpuBoolDescriptor {
        let name: String
        let option: Int32
        let getValue: @Sendable (LiteRTLMVisionGPUOptions) -> Bool?
        let getDefault: @Sendable (LiteRTLMBackend?) -> Bool?

        func resolve(options: LiteRTLMVisionGPUOptions, visionBackend: LiteRTLMBackend?) -> ResolvedBool? {
            if let explicit = getValue(options) {
                return ResolvedBool(value: explicit, isDefault: false)
            }
            if let fallback = getDefault(visionBackend) {
                return ResolvedBool(value: fallback, isDefault: true)
            }
            return nil
        }
    }

    private static let advancedBoolDescriptors: [AdvancedBoolDescriptor] = [
        .init(name: "clearKvCacheBeforePrefill", option: 0,
              getValue: { $0.clearKvCacheBeforePrefill },
              getDefault: { _, _ in nil }),
        .init(name: "gpuMadviseOriginalSharedTensors", option: 1,
              getValue: { $0.gpuMadviseOriginalSharedTensors },
              getDefault: { _, _ in nil }),
        .init(name: "gpuConvertWeightsOnGpu", option: 2,
              getValue: { $0.gpuConvertWeightsOnGpu },
              getDefault: { modelURL, backend in
                  guard backend == .gpu, isE4B(modelURL: modelURL) else { return nil }
                  return false
              }),
        .init(name: "gpuWaitForWeightsConversionCompleteInBenchmark", option: 3,
              getValue: { $0.gpuWaitForWeightsConversionCompleteInBenchmark },
              getDefault: { _, _ in nil }),
        .init(name: "gpuOptimizeShaderCompilation", option: 4,
              getValue: { $0.gpuOptimizeShaderCompilation },
              getDefault: { _, _ in nil }),
        .init(name: "gpuCacheCompiledShadersOnly", option: 5,
              getValue: { $0.gpuCacheCompiledShadersOnly },
              getDefault: { _, backend in backend == .gpu ? true : nil }),
        .init(name: "gpuShareConstantTensors", option: 6,
              getValue: { $0.gpuShareConstantTensors },
              getDefault: { _, _ in nil }),
        .init(name: "samplerHandlesInput", option: 7,
              getValue: { $0.samplerHandlesInput },
              getDefault: { _, _ in nil }),
        .init(name: "gpuAllowSrcQuantizedFcConvOps", option: 8,
              getValue: { $0.gpuAllowSrcQuantizedFcConvOps },
              getDefault: { _, _ in nil }),
        .init(name: "gpuHintWaitingForCompletion", option: 9,
              getValue: { $0.gpuHintWaitingForCompletion },
              getDefault: { _, _ in nil }),
        .init(name: "gpuContextLowPriority", option: 10,
              getValue: { $0.gpuContextLowPriority },
              getDefault: { _, _ in nil }),
        .init(name: "gpuDisableDelegateClustering", option: 11,
              getValue: { $0.gpuDisableDelegateClustering },
              getDefault: { _, _ in nil }),
    ]

    private static let visionGpuBoolDescriptors: [VisionGpuBoolDescriptor] = [
        .init(name: "madviseOriginalSharedTensors", option: 1,
              getValue: { $0.madviseOriginalSharedTensors },
              getDefault: { _ in nil }),
        .init(name: "convertWeightsOnGpu", option: 2,
              getValue: { $0.convertWeightsOnGpu },
              getDefault: { _ in nil }),
        .init(name: "cacheCompiledShadersOnly", option: 5,
              getValue: { $0.cacheCompiledShadersOnly },
              getDefault: { visionBackend in visionBackend == .gpu ? true : nil }),
        .init(name: "shareConstantTensors", option: 6,
              getValue: { $0.shareConstantTensors },
              getDefault: { _ in nil }),
    ]

    private static func runtimeCacheDirectory(baseDirectory: URL, options: LiteRTLMRuntimeOptions) -> URL {
        guard let rawSubdirectory = options.cacheSubdirectory else {
            return baseDirectory
        }
        let sanitizedSubdirectory = rawSubdirectory
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .filter { character in
                character.isLetter || character.isNumber || character == "-" || character == "_" || character == "."
            }
        guard !sanitizedSubdirectory.isEmpty else {
            ConsoleLog.error(
                "Ignoring invalid cacheSubdirectory=\(rawSubdirectory).",
                category: "Runtime"
            )
            return baseDirectory
        }
        return baseDirectory.appendingPathComponent(sanitizedSubdirectory, isDirectory: true)
    }

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

private func formatOptional<T>(_ value: T?) -> String {
    guard let value else { return "unset" }
    return String(describing: value)
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
