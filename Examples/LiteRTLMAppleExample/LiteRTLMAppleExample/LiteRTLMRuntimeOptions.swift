import Foundation

/// Compute backend selection passed to LiteRT-LM.
///
/// Mirrors the `backend_str` values accepted by the upstream
/// `litert_lm_engine_settings_create` C API. Only the two values exercised
/// by this sample app are exposed here; if you need NPU/QNN/Artisan
/// backends, extend this enum and forward the new raw value to the C API.
enum LiteRTLMBackend: String, Sendable {
    case gpu
    case cpu

    /// Lowercase name accepted by the C API.
    var name: String { rawValue }
}

/// Activation tensor precision applied to a LiteRT-LM executor.
///
/// Raw values intentionally match the C-side `litert::lm::ActivationDataType`
/// enum so they can be passed straight through the C wrapper.
enum LiteRTLMActivationDataType: Int32, Sendable {
    case float32 = 0
    case float16 = 1
    case int16 = 2
    case int8 = 3
}

/// CPU kernel implementation used by the main executor when running on CPU.
///
/// Raw values match the upstream `LiteRtCpuKernelMode` enum.
enum LiteRTLMCPUKernelMode: Int32, Sendable {
    /// XNNPACK kernels (the upstream default for CPU).
    case xnnpack = 0
    /// Reference CPU kernels — slower, used as a debugging baseline.
    case reference = 1
    /// Built-in CPU kernels — required for the E4B "main CPU + vision GPU"
    /// configuration on Apple platforms because XNNPACK trips a reshape error
    /// on that path.
    case builtin = 2
}

/// Minimum log severity emitted by the LiteRT-LM C++ runtime.
///
/// Raw values match the `litert::lm::LogSeverity` enum. `.silent` suppresses
/// every message; lower numeric values are more verbose.
enum LiteRTLMLogLevel: Int32, Sendable {
    case verbose = 0
    case debug = 1
    case info = 2
    case warning = 3
    case error = 4
    case fatal = 5
    case silent = 1000
}

/// Per-call overrides for the upstream "advanced" engine settings.
///
/// Each property mirrors one entry in the `LiteRtLmAdvancedBoolOption` C
/// enum. A `nil` field means "let the runtime apply its model-aware default";
/// a non-nil field is forwarded directly to LiteRT-LM and skips the
/// fallback. See ``LiteRTLMRuntimeOptions`` for the exact defaults the
/// runtime applies.
struct LiteRTLMAdvancedOptions: Sendable {
    var clearKvCacheBeforePrefill: Bool? = nil
    var gpuMadviseOriginalSharedTensors: Bool? = nil
    var gpuConvertWeightsOnGpu: Bool? = nil
    var gpuWaitForWeightsConversionCompleteInBenchmark: Bool? = nil
    var gpuOptimizeShaderCompilation: Bool? = nil
    var gpuCacheCompiledShadersOnly: Bool? = nil
    var gpuShareConstantTensors: Bool? = nil
    var samplerHandlesInput: Bool? = nil
    var gpuAllowSrcQuantizedFcConvOps: Bool? = nil
    var gpuHintWaitingForCompletion: Bool? = nil
    var gpuContextLowPriority: Bool? = nil
    var gpuDisableDelegateClustering: Bool? = nil
}

/// Per-call overrides for the upstream vision-GPU bool settings.
///
/// Same `nil` semantics as ``LiteRTLMAdvancedOptions``: leaving a field nil
/// keeps the runtime's default; setting it forwards directly to LiteRT-LM.
struct LiteRTLMVisionGPUOptions: Sendable {
    var madviseOriginalSharedTensors: Bool? = nil
    var convertWeightsOnGpu: Bool? = nil
    var cacheCompiledShadersOnly: Bool? = nil
    var shareConstantTensors: Bool? = nil
}

/// Per-call configuration for ``LiteRTLMRuntime/generateResponse(modelURL:cacheDirectory:inputs:options:)``.
///
/// The struct's defaults are tuned to produce correct, stable Gemma 4 image
/// inference on Apple devices without any tweaking from the caller. In
/// practice that means:
///
/// - GPU main executor (`backend = .gpu`)
/// - CPU vision executor for Gemma 4 image prompts (E2B and E4B both produce
///   semantically wrong embeddings on the Metal FP16 vision encoder, and the
///   FP32 path exceeds iOS cold-start memory limits)
/// - FP16 main activations + a 384-token cap on GPU to fit current device
///   memory budgets
/// - E4B-specific main weight conversion on CPU and shader-cache reuse on
///   both main and vision GPU
///
/// The simplest call looks like this:
///
/// ```swift
/// let result = try await LiteRTLMRuntime().generateResponse(
///     modelURL: modelURL,
///     cacheDirectory: cacheDirectory,
///     inputs: InferenceInputs(prompt: "What is this?", imageData: pngData),
///     options: LiteRTLMRuntimeOptions()
/// )
/// ```
///
/// To run a diagnostic configuration — for example forcing FP32 vision on
/// the GPU encoder — mutate the relevant fields before passing the struct
/// in. Setting any field to a non-nil value bypasses the runtime's
/// model-aware default for that field:
///
/// ```swift
/// var options = LiteRTLMRuntimeOptions()
/// options.visionBackend = .gpu                       // override Gemma 4 default
/// options.visionActivationDataType = .float32        // correct embeddings, large memory
/// options.minLogLevel = .info                        // see runtime startup logs
/// let result = try await runtime.generateResponse(
///     modelURL: modelURL, cacheDirectory: cacheDirectory,
///     inputs: inputs, options: options
/// )
/// ```
///
/// Fields documented as "`nil` …" use a runtime fallback that depends on
/// other fields and on the model file name. Concrete fallback rules live in
/// ``LiteRTLMRuntime``.
struct LiteRTLMRuntimeOptions: Sendable {
    // MARK: - Core

    /// Backend used for the main LLM executor. Defaults to ``LiteRTLMBackend/gpu``.
    var backend: LiteRTLMBackend = .gpu

    /// Backend used for the vision encoder.
    ///
    /// `nil` lets the runtime resolve a model-aware default: when an image
    /// is attached and the model is Gemma 4 (E2B or E4B), defaults to
    /// ``LiteRTLMBackend/cpu``; otherwise mirrors ``backend``. When no image
    /// is attached, the vision executor is not instantiated at all.
    var visionBackend: LiteRTLMBackend? = nil

    /// Maximum number of tokens the engine plans for. `nil` defaults to
    /// `384` when ``backend`` is GPU (the largest budget that reliably fits
    /// the current public Gemma 4 E4B artifact on iPhone 16 Pro / 17 Pro);
    /// otherwise leaves the upstream default in place.
    var maxNumTokens: Int32? = nil

    /// Maximum number of images the prefill graph reserves capacity for.
    /// Vision-capable Gemma 4 models require at least `1`; `0` causes a
    /// `DYNAMIC_UPDATE_SLICE` shape mismatch at prefill time.
    var maxNumImages: Int32 = 1

    /// Minimum severity emitted by the LiteRT-LM C++ runtime.
    var minLogLevel: LiteRTLMLogLevel = .warning

    /// Whether to enable the LiteRT-LM benchmark collector.
    var benchmark: Bool = true

    /// Subdirectory appended to the cache base directory. `nil` uses the
    /// base directory directly. Sanitized to alphanumerics, `-`, `_`, and `.`
    /// before being applied.
    var cacheSubdirectory: String? = nil

    // MARK: - Tuning

    /// Global activation data type applied to main, vision, and audio
    /// executors at once. Specific overrides below take precedence.
    var activationDataType: LiteRTLMActivationDataType? = nil

    /// Main executor activation type. `nil` defaults to
    /// ``LiteRTLMActivationDataType/float16`` when ``backend`` is GPU and
    /// ``activationDataType`` is also `nil`.
    var mainActivationDataType: LiteRTLMActivationDataType? = nil

    /// Vision executor activation type. `nil` defers to upstream LiteRT-LM
    /// (which currently picks FP32 for vision GPU for backward compatibility,
    /// but the local C wrapper forces FP16 to fit Metal memory limits — see
    /// the runtime documentation for the trade-off).
    var visionActivationDataType: LiteRTLMActivationDataType? = nil

    /// Audio executor activation type. `nil` defers to upstream LiteRT-LM.
    var audioActivationDataType: LiteRTLMActivationDataType? = nil

    var prefillChunkSize: Int32? = nil
    var prefillBatchSizes: [Int32]? = nil
    var parallelLoading: Bool? = nil

    /// CPU kernel selection for the main executor. `nil` defaults to
    /// ``LiteRTLMCPUKernelMode/builtin`` when running E4B with main CPU and
    /// vision GPU (XNNPACK trips a reshape error on that path); otherwise
    /// defers to upstream.
    var cpuKernelMode: LiteRTLMCPUKernelMode? = nil

    var gpuExternalTensorMode: Bool? = nil
    var gpuHintKernelBatchSize: Int32? = nil

    // MARK: - Deep diagnostics

    /// Per-call overrides for the upstream "advanced" bool table. Most
    /// callers can leave this at its default; the runtime applies safe
    /// per-model defaults internally.
    var advanced: LiteRTLMAdvancedOptions = .init()

    /// Per-call overrides for the upstream vision-GPU bool table. Same
    /// guidance as ``advanced``.
    var visionGPU: LiteRTLMVisionGPUOptions = .init()

    init() {}
}
