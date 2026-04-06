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

protocol LiteRTLMRuntimeProtocol: Sendable {
    func generateResponse(
        modelURL: URL,
        cacheDirectory: URL,
        prompt: String
    ) async throws -> InferenceResult
}

struct LiteRTLMRuntime: LiteRTLMRuntimeProtocol {
    func generateResponse(
        modelURL: URL,
        cacheDirectory: URL,
        prompt: String
    ) async throws -> InferenceResult {
        ConsoleLog.info(
            "Queueing inference task. model=\(modelURL.path) cache=\(cacheDirectory.path) prompt_chars=\(prompt.count).",
            category: "Runtime"
        )
        return try await Task.detached(priority: .userInitiated) {
            try generateResponseSynchronously(
                modelURL: modelURL,
                cacheDirectory: cacheDirectory,
                prompt: prompt
            )
        }.value
    }

    private func generateResponseSynchronously(
        modelURL: URL,
        cacheDirectory: URL,
        prompt: String
    ) throws -> InferenceResult {
        ConsoleLog.info(
            "Starting synchronous inference. model=\(modelURL.path) cache=\(cacheDirectory.path).",
            category: "Runtime"
        )
        ConsoleLog.debug("Prompt preview=\(ConsoleLog.preview(prompt)).", category: "Runtime")
        litert_lm_set_min_log_level(1)

        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        ConsoleLog.debug("Ensured runtime cache directory exists.", category: "Runtime")

        let settings = modelURL.path.withCString { modelPathPointer in
            "cpu".withCString { backendPointer in
                litert_lm_engine_settings_create(modelPathPointer, backendPointer, nil, nil)
            }
        }

        guard let settings else {
            throw LiteRTLMRuntimeError("Failed to create LiteRT-LM engine settings.")
        }
        defer { litert_lm_engine_settings_delete(settings) }
        ConsoleLog.info("Created engine settings for CPU backend.", category: "Runtime")

        litert_lm_engine_settings_set_max_num_tokens(settings, 1024)
        litert_lm_engine_settings_set_prefill_chunk_size(settings, 256)
        litert_lm_engine_settings_enable_benchmark(settings)
        ConsoleLog.debug("Applied engine settings: max_num_tokens=1024 prefill_chunk_size=256 benchmark=enabled.", category: "Runtime")

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

        let systemMessageJSON =
            #"{"type":"text","text":"You are a concise assistant running entirely on-device. Answer clearly and directly."}"#

        let conversationConfig = systemMessageJSON.withCString { systemMessagePointer in
            litert_lm_conversation_config_create(
                engine,
                sessionConfig,
                systemMessagePointer,
                nil,
                nil,
                false
            )
        }

        guard let conversationConfig else {
            throw LiteRTLMRuntimeError("Failed to create LiteRT-LM conversation config.")
        }
        defer { litert_lm_conversation_config_delete(conversationConfig) }
        ConsoleLog.info("Created conversation config.", category: "Runtime")

        guard let conversation = litert_lm_conversation_create(engine, conversationConfig) else {
            throw LiteRTLMRuntimeError("Failed to create LiteRT-LM conversation.")
        }
        defer { litert_lm_conversation_delete(conversation) }
        ConsoleLog.info("Created LiteRT-LM conversation.", category: "Runtime")

        let messageJSON = try Self.makeUserMessageJSON(prompt: prompt)
        let extraContextJSON = #"{"enable_thinking":false}"#
        ConsoleLog.debug("Message JSON=\(ConsoleLog.preview(messageJSON)).", category: "Runtime")
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

    private static func makeUserMessageJSON(prompt: String) throws -> String {
        let message: [String: Any] = [
            "role": "user",
            "content": [
                [
                    "type": "text",
                    "text": prompt,
                ],
            ],
        ]

        let data = try JSONSerialization.data(withJSONObject: message)

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
