# Multimodal Image Input — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bump the LiteRT-LM upstream pin to current `main` HEAD, refresh the package's patches and XCFrameworks for the renamed C API, and add a working text + image input flow to the sample app so a user on iPhone, iPad, Apple Vision Pro, native Mac, or Mac Catalyst can attach a photo and ask Gemma 4 E2B about it.

**Architecture:** Library work is patch-and-rebuild against `7d1923daaaa1e5143f77f0adb105188e53e8485e`. Swift runtime is updated for the new builder-pattern conversation config and the new log-level scale, and gains an optional image content part in the user message JSON (`{"type":"image","blob":"<base64-jpeg>"}`). The sample app gains a `PhotosPicker`-backed attach button in the existing Prompt card and re-encodes any picker output to JPEG via ImageIO before handing bytes to the engine.

**Tech Stack:** Swift 6, SwiftUI, PhotosUI / `PhotosPicker`, ImageIO, the LiteRT-LM C API, Bazelisk + Xcode for the rebuild pipeline.

---

## Pre-work check (do not skip)

Before Task 1, verify the dev machine has the prerequisites the rebuild needs:

```bash
command -v bazelisk && bazelisk version
command -v xcodebuild && xcodebuild -version
command -v git && git --version
command -v git-lfs && git lfs version
```

All four must exist. If `git-lfs` is missing, install with `brew install git-lfs`.

## Task 1: Bump pinned upstream revision

**Files:**
- Modify: `scripts/subscripts/common.sh:8`

- [ ] **Step 1.1: Read the current pin**

```bash
grep UPSTREAM_BASE_REVISION_DEFAULT /Users/rogerio/git/liteRT-LM-Apple/scripts/subscripts/common.sh
```

Expected: `UPSTREAM_BASE_REVISION_DEFAULT="e4d5da404e54eeea7903ae23d81fe8447cb3e089"`

- [ ] **Step 1.2: Edit the pin**

Change line 8 in `scripts/subscripts/common.sh` from:

```bash
UPSTREAM_BASE_REVISION_DEFAULT="e4d5da404e54eeea7903ae23d81fe8447cb3e089"
```

to:

```bash
UPSTREAM_BASE_REVISION_DEFAULT="7d1923daaaa1e5143f77f0adb105188e53e8485e"
```

- [ ] **Step 1.3: Verify the change**

```bash
grep UPSTREAM_BASE_REVISION_DEFAULT /Users/rogerio/git/liteRT-LM-Apple/scripts/subscripts/common.sh
```

Expected: `UPSTREAM_BASE_REVISION_DEFAULT="7d1923daaaa1e5143f77f0adb105188e53e8485e"`

- [ ] **Step 1.4: Commit**

```bash
cd /Users/rogerio/git/liteRT-LM-Apple
git add scripts/subscripts/common.sh
git commit -m "build: bump upstream LiteRT-LM pin to 7d1923d"
```

## Task 2: Clone upstream at the new pin (precondition for Task 3)

**Files:** none modified.

- [ ] **Step 2.1: Run the existing clone subscript**

```bash
cd /Users/rogerio/git/liteRT-LM-Apple
./scripts/subscripts/clone_upstream.sh
```

Expected output ends with:

```
Prepared upstream LiteRT-LM checkout:
  repo: /Users/rogerio/git/liteRT-LM-Apple/.worktree/LiteRT-LM
  revision: 7d1923daaaa1e5143f77f0adb105188e53e8485e
```

- [ ] **Step 2.2: Verify the checkout state**

```bash
git -C /Users/rogerio/git/liteRT-LM-Apple/.worktree/LiteRT-LM rev-parse HEAD
ls /Users/rogerio/git/liteRT-LM-Apple/.worktree/LiteRT-LM/c/
```

Expected: `7d1923daaaa1e5143f77f0adb105188e53e8485e`, and `c/` contains `BUILD`, `engine.h`, `engine.cc`, `engine_test.cc`, `CMakeLists.txt`.

## Task 3: Refresh the export patch against the new tree

The current patch was built for revision `e4d5da4`. It targets a `c/BUILD` and a `c/engine.{h,cc}` that no longer match. We rewrite the patch by editing the upstream tree manually, then capturing the diff.

**Files:**
- Modify: `patches/0001-export-ios-shared-engine-dylib.patch` (full rewrite)

- [ ] **Step 3.1: Reset the upstream tree to a clean state**

```bash
cd /Users/rogerio/git/liteRT-LM-Apple/.worktree/LiteRT-LM
git reset --hard
git clean -fd
```

- [ ] **Step 3.2: Add the `engine_cpu_shared` cc_binary target to `c/BUILD`**

Append after the existing `cc_library(name = "engine_cpu", ...)` block (line ~86 in upstream HEAD `c/BUILD`):

```python
cc_binary(
    name = "engine_cpu_shared",
    linkshared = 1,
    linkstatic = 1,
    linkopts = select({
        "@platforms//os:ios": [
            "-Wl,-install_name,@rpath/libLiteRTLMEngineCPU.dylib",
        ],
        "@platforms//os:macos": [
            "-Wl,-install_name,@rpath/libLiteRTLMEngineCPU.dylib",
        ],
        "//conditions:default": [],
    }),
    deps = [
        ":engine_cpu",
    ],
)
```

Use the Edit tool to insert this immediately after `cc_library(name = "engine_cpu"...)` and before `cc_test(name = "engine_test"...)`.

- [ ] **Step 3.3: Add the `litert_lm_engine_settings_set_max_num_images` declaration to `c/engine.h`**

Locate `litert_lm_engine_settings_set_max_num_tokens` declaration in upstream HEAD's `c/engine.h`. Insert immediately after its closing semicolon:

```c
// Sets the maximum number of image inputs the engine should reserve KV cache
// space for. Required to be at least 1 when sending images through the
// conversation API on a vision-capable model (e.g. Gemma 4 E2B / E4B);
// leaving it at 0 (the default) causes the prefill graph to fail with a
// DYNAMIC_UPDATE_SLICE shape mismatch on physical iOS devices.
//
// @param settings The engine settings.
// @param max_num_images The maximum number of images per prompt.
LITERT_LM_C_API_EXPORT
void litert_lm_engine_settings_set_max_num_images(
    LiteRtLmEngineSettings* settings, int max_num_images);
```

- [ ] **Step 3.4: Add the `litert_lm_engine_settings_set_max_num_images` definition to `c/engine.cc`**

Locate `litert_lm_engine_settings_set_max_num_tokens(...)` definition in upstream HEAD's `c/engine.cc`. Insert immediately after its closing brace `}`:

```cpp
void litert_lm_engine_settings_set_max_num_images(
    LiteRtLmEngineSettings* settings, int max_num_images) {
  if (settings && settings->settings) {
    settings->settings->GetMutableMainExecutorSettings().SetMaxNumImages(
        static_cast<uint32_t>(max_num_images));
  }
}
```

- [ ] **Step 3.5: Verify edits compile structurally**

```bash
grep -n 'engine_cpu_shared' /Users/rogerio/git/liteRT-LM-Apple/.worktree/LiteRT-LM/c/BUILD
grep -n 'set_max_num_images' /Users/rogerio/git/liteRT-LM-Apple/.worktree/LiteRT-LM/c/engine.h
grep -n 'set_max_num_images' /Users/rogerio/git/liteRT-LM-Apple/.worktree/LiteRT-LM/c/engine.cc
```

Expected: all three commands print at least one line.

- [ ] **Step 3.6: Capture the diff as the new patch**

```bash
cd /Users/rogerio/git/liteRT-LM-Apple/.worktree/LiteRT-LM
git diff -- c/BUILD c/engine.h c/engine.cc > /Users/rogerio/git/liteRT-LM-Apple/patches/0001-export-ios-shared-engine-dylib.patch
```

- [ ] **Step 3.7: Verify the patch reapplies cleanly**

```bash
cd /Users/rogerio/git/liteRT-LM-Apple/.worktree/LiteRT-LM
git reset --hard
git apply --check /Users/rogerio/git/liteRT-LM-Apple/patches/0001-export-ios-shared-engine-dylib.patch
echo $?
```

Expected: exit code `0` (no output from `git apply --check` on success).

- [ ] **Step 3.8: Commit the patch**

```bash
cd /Users/rogerio/git/liteRT-LM-Apple
git add patches/0001-export-ios-shared-engine-dylib.patch
git commit -m "build: refresh upstream export patch for HEAD pin"
```

## Task 4: Run the full rebuild pipeline

This invokes the existing `scripts/buildall.sh`, which calls clone, patch, build, and package subscripts in order. First-time builds with cleared bazel state can take 30–60 min; the worktree is reused across runs so subsequent builds are faster.

**Files:**
- Modify: `Artifacts/LiteRTLMEngineCPU.xcframework/` (rebuilt in place)
- Modify: `Artifacts/GemmaModelConstraintProvider.xcframework/` (rebuilt in place)
- Modify: `Sources/LiteRTLMApple/include/engine.h` (refreshed from upstream)

- [ ] **Step 4.1: Kick off the build**

```bash
cd /Users/rogerio/git/liteRT-LM-Apple
./scripts/buildall.sh
```

Expected final output:

```
Updated package artifacts:
  /Users/rogerio/git/liteRT-LM-Apple/Artifacts/LiteRTLMEngineCPU.xcframework
  /Users/rogerio/git/liteRT-LM-Apple/Artifacts/GemmaModelConstraintProvider.xcframework
  /Users/rogerio/git/liteRT-LM-Apple/Sources/LiteRTLMApple/include/engine.h
```

If the build fails with a Bazel external-deps error, run once more (transient `git clone` retries during external fetches are expected). If it fails with a structural error on the patched files, investigate and adjust the patch in Task 3 before retrying.

- [ ] **Step 4.2: Verify the new engine.h exposes the expected symbols**

```bash
grep -nE 'set_max_num_images|conversation_config_create|LiteRtLmInputData|LiteRtLmSamplerType' /Users/rogerio/git/liteRT-LM-Apple/Sources/LiteRTLMApple/include/engine.h
```

Expected output includes (order may vary):

```
litert_lm_engine_settings_set_max_num_images
LiteRtLmConversationConfig* litert_lm_conversation_config_create();
LiteRtLmInputData
LiteRtLmSamplerType
```

- [ ] **Step 4.3: Verify all six XCFramework slices are present for both frameworks**

```bash
ls /Users/rogerio/git/liteRT-LM-Apple/Artifacts/LiteRTLMEngineCPU.xcframework/
ls /Users/rogerio/git/liteRT-LM-Apple/Artifacts/GemmaModelConstraintProvider.xcframework/
```

Expected: each lists `Info.plist` plus six platform directories: `ios-arm64`, `ios-arm64-simulator`, `ios-arm64-maccatalyst`, `macos-arm64`, `xros-arm64`, `xros-arm64-simulator`.

- [ ] **Step 4.4: Commit the artifacts and refreshed header**

```bash
cd /Users/rogerio/git/liteRT-LM-Apple
git add Artifacts/ Sources/LiteRTLMApple/include/engine.h
git commit -m "build: rebuild XCFrameworks against upstream 7d1923d"
```

## Task 5: Update Swift runtime for the new C API

The 6-arg `litert_lm_conversation_config_create` is gone. Replace with the new builder. Also adapt log level (was 1=WARNING, now 1=DEBUG → use 3 for WARNING).

**Files:**
- Modify: `Examples/LiteRTLMAppleExample/LiteRTLMAppleExample/LiteRTLMRuntime.swift` (full rewrite of the C-API call sites)

- [ ] **Step 5.1: Replace `LiteRTLMRuntime.swift` with the new implementation**

Overwrite the file with this content:

```swift
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
        // 0=VERBOSE, 1=DEBUG, 2=INFO, 3=WARNING, 4=ERROR, 5=FATAL, 1000=SILENT.
        litert_lm_set_min_log_level(3)

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
        litert_lm_engine_settings_set_max_num_images(settings, 1)
        litert_lm_engine_settings_set_prefill_chunk_size(settings, 256)
        litert_lm_engine_settings_enable_benchmark(settings)
        ConsoleLog.debug(
            "Applied engine settings: max_num_tokens=1024 max_num_images=1 prefill_chunk_size=256 benchmark=enabled.",
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
```

- [ ] **Step 5.2: Spot-check the wire format with a one-shot Swift script**

Create `/tmp/litertlm-jsonshape.swift`:

```swift
import Foundation

struct InferenceInputs {
    let prompt: String
    let imageData: Data?
}

func makeUserMessageJSON(inputs: InferenceInputs) throws -> String {
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
    return String(data: data, encoding: .utf8)!
}

// Text-only path.
let textOnly = try makeUserMessageJSON(inputs: .init(prompt: "Hi", imageData: nil))
assert(textOnly.contains(#""role":"user""#), "text-only missing role: \(textOnly)")
assert(textOnly.contains(#""text":"Hi""#), "text-only missing text: \(textOnly)")
assert(!textOnly.contains(#""type":"image""#), "text-only should not contain image part: \(textOnly)")

// Text + image path.
let withImage = try makeUserMessageJSON(
    inputs: .init(prompt: "What is this?", imageData: Data([0xDE, 0xAD, 0xBE, 0xEF]))
)
assert(withImage.contains(#""type":"image""#), "with-image missing image part: \(withImage)")
assert(withImage.contains(#""text":"What is this?""#), "with-image missing text: \(withImage)")
assert(withImage.contains(#""blob":"3q2+7w==""#), "with-image base64 wrong: \(withImage)")

// Image content part must precede the text part.
let imageRange = withImage.range(of: #""type":"image""#)!
let textRange = withImage.range(of: #""type":"text""#)!
assert(imageRange.lowerBound < textRange.lowerBound, "image must precede text: \(withImage)")

print("OK")
```

Run:

```bash
swift /tmp/litertlm-jsonshape.swift
```

Expected: `OK`. If the assertions fail, the JSON shape regressed; fix `makeUserMessageJSON` until both pass.

Note: `0xDE, 0xAD, 0xBE, 0xEF` base64-encodes to `3q2+7w==` (no `/` to worry about JSON-escaping).

- [ ] **Step 5.3: Commit the runtime update**

```bash
cd /Users/rogerio/git/liteRT-LM-Apple
git add Examples/LiteRTLMAppleExample/LiteRTLMAppleExample/LiteRTLMRuntime.swift
git commit -m "feat(sample): adapt runtime to new C API and image content path"
```

## Task 6: Add a cross-platform JPEG normalizer

This helper takes whatever bytes the picker hands us (HEIC, PNG, JPEG, …) and returns JPEG bytes the engine can decode.

**Files:**
- Create: `Examples/LiteRTLMAppleExample/LiteRTLMAppleExample/ImageDataNormalizer.swift`

- [ ] **Step 6.1: Write the helper**

Create the new file with:

```swift
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ImageDataNormalizer {
    enum NormalizationError: LocalizedError {
        case decodeFailed
        case encodeFailed

        var errorDescription: String? {
            switch self {
            case .decodeFailed:
                return "Could not decode the selected image."
            case .encodeFailed:
                return "Could not re-encode the selected image as JPEG."
            }
        }
    }

    /// Re-encode arbitrary picker bytes (HEIC, PNG, JPEG, …) as JPEG so the
    /// LiteRT-LM stb_image-based decoder can ingest them.
    static func makeJPEGData(
        from rawData: Data,
        compressionQuality: Double = 0.9
    ) throws -> Data {
        guard
            let source = CGImageSourceCreateWithData(rawData as CFData, nil),
            let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw NormalizationError.decodeFailed
        }

        let mutableData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            mutableData,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw NormalizationError.encodeFailed
        }

        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: compressionQuality,
        ]
        CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            throw NormalizationError.encodeFailed
        }

        return mutableData as Data
    }
}
```

- [ ] **Step 6.2: Commit**

```bash
cd /Users/rogerio/git/liteRT-LM-Apple
git add Examples/LiteRTLMAppleExample/LiteRTLMAppleExample/ImageDataNormalizer.swift
git commit -m "feat(sample): add JPEG normalizer for picker output"
```

## Task 7: Wire image state through the view model

**Files:**
- Modify: `Examples/LiteRTLMAppleExample/LiteRTLMAppleExample/InferenceViewModel.swift` (full rewrite)

- [ ] **Step 7.1: Overwrite the view model**

Replace the file's contents with:

```swift
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
                    inputs: inputs
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

    private static func describe(_ error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription {
            return description
        }

        return String(describing: error)
    }
}
```

- [ ] **Step 7.2: Commit**

```bash
cd /Users/rogerio/git/liteRT-LM-Apple
git add Examples/LiteRTLMAppleExample/LiteRTLMAppleExample/InferenceViewModel.swift
git commit -m "feat(sample): track attached image state in view model"
```

## Task 8: Add the attach UI in ContentView

**Files:**
- Modify: `Examples/LiteRTLMAppleExample/LiteRTLMAppleExample/ContentView.swift`

- [ ] **Step 8.1: Add the PhotosUI import block at the top**

Find the imports at the top of `ContentView.swift`:

```swift
import SwiftUI
#if os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif
```

Replace with:

```swift
import SwiftUI
import PhotosUI
#if os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif
```

- [ ] **Step 8.2: Add the attach state to the view**

Find:

```swift
struct ContentView: View {
    @ObservedObject var viewModel: InferenceViewModel

    var body: some View {
```

Replace with:

```swift
struct ContentView: View {
    @ObservedObject var viewModel: InferenceViewModel
    @State private var pickerSelection: PhotosPickerItem?

    var body: some View {
```

- [ ] **Step 8.3: Replace the existing prompt card with the multimodal one**

Find the entire `private var promptCard: some View { ... }` block (the section after `// MARK: - Prompt`) and replace its body with:

```swift
    private var promptCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(icon: "text.bubble", title: "Prompt")

                if let imageData = viewModel.attachedImageData,
                   let preview = Self.previewImage(from: imageData) {
                    HStack(spacing: 10) {
                        preview
                            .resizable()
                            .scaledToFill()
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(Color.primary.opacity(0.08))
                            )

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Image attached")
                                .font(.footnote.weight(.semibold))
                            Text("\(imageData.count.formatted(.byteCount(style: .file)))")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button {
                            viewModel.clearAttachedImage()
                            pickerSelection = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title3)
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove attached image")
                    }
                    .padding(8)
                    .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.appSecondaryBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.08))
                        )

                    TextEditor(text: $viewModel.prompt)
                        .font(.footnote)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .frame(minHeight: 120)
                }

                HStack(spacing: 8) {
                    PhotosPicker(
                        selection: $pickerSelection,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        HStack(spacing: 6) {
                            Image(systemName: "paperclip")
                            Text(viewModel.attachedImageData == nil ? "Attach Image" : "Replace Image")
                                .lineLimit(1)
                                .fixedSize()
                        }
                        .font(.footnote.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 22)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .disabled(viewModel.isDownloading || viewModel.isRunning)

                    if viewModel.attachedImageData != nil {
                        Button {
                            viewModel.setExamplePromptForAttachedImage()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "questionmark.bubble")
                                Text("\"What is this?\"")
                                    .lineLimit(1)
                                    .fixedSize()
                            }
                            .font(.footnote.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 22)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                        .disabled(viewModel.isDownloading || viewModel.isRunning)
                    }
                }

                Button {
                    viewModel.runInference()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill")
                        Text(viewModel.isRunning ? "Running" : "Run Inference")
                            .lineLimit(1)
                            .fixedSize()
                    }
                    .font(.footnote.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 22)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(viewModel.localModelURL == nil || viewModel.isDownloading || viewModel.isRunning)
            }
        }
        .onChange(of: pickerSelection) { _, newValue in
            guard let newValue else { return }
            Task { await loadAttachedImage(from: newValue) }
        }
    }

    private func loadAttachedImage(from item: PhotosPickerItem) async {
        do {
            guard let rawData = try await item.loadTransferable(type: Data.self) else {
                await MainActor.run { viewModel.clearAttachedImage() }
                return
            }
            let normalized = try ImageDataNormalizer.makeJPEGData(from: rawData)
            await MainActor.run { viewModel.attachImage(normalized) }
        } catch {
            await MainActor.run {
                viewModel.clearAttachedImage()
                ConsoleLog.error("Failed to load attached image: \(error)", category: "ViewModel")
            }
        }
    }

    private static func previewImage(from data: Data) -> Image? {
#if os(macOS)
        guard let nsImage = NSImage(data: data) else { return nil }
        return Image(nsImage: nsImage)
#else
        guard let uiImage = UIImage(data: data) else { return nil }
        return Image(uiImage: uiImage)
#endif
    }
```

- [ ] **Step 8.4: Verify the existing call sites of `promptCard` and `previewImage` are intact**

```bash
grep -nE 'promptCard|previewImage|loadAttachedImage' /Users/rogerio/git/liteRT-LM-Apple/Examples/LiteRTLMAppleExample/LiteRTLMAppleExample/ContentView.swift
```

Expected: at least one call to `promptCard` from the view body, and the new helpers exist exactly once.

- [ ] **Step 8.5: Commit**

```bash
cd /Users/rogerio/git/liteRT-LM-Apple
git add Examples/LiteRTLMAppleExample/LiteRTLMAppleExample/ContentView.swift
git commit -m "feat(sample): add image attach UI to prompt card"
```

## Task 9: Add Photo Library usage description (defensive)

`PhotosPicker` with `.shared()` runs out-of-process on every Apple platform, so a Photo Library usage description is **not strictly required** for the build to succeed or for the picker to function. However, declaring the key is best practice (some review tooling expects it, and any future direct PhotoKit usage would need it). Add it preemptively. **If the Catalyst run already works without this task, it is safe to skip.**

**Files:**
- Modify: `Examples/LiteRTLMAppleExample/LiteRTLMAppleExample.xcodeproj/project.pbxproj`

- [ ] **Step 9.1: Locate the Info.plist values**

```bash
grep -nE 'INFOPLIST_KEY_NS|GENERATE_INFOPLIST_FILE|INFOPLIST_FILE' /Users/rogerio/git/liteRT-LM-Apple/Examples/LiteRTLMAppleExample/LiteRTLMAppleExample.xcodeproj/project.pbxproj | head -20
```

If output shows `GENERATE_INFOPLIST_FILE = YES` plus `INFOPLIST_KEY_NS*` entries, the project uses generated Info.plist with build-setting overrides — proceed to Step 9.2.

If output shows `INFOPLIST_FILE = ...` only, edit the referenced plist file directly with the same key/value as Step 9.2.

- [ ] **Step 9.2: Add the photo-library usage key**

For each `XCBuildConfiguration` block under the app target (Debug and Release), insert this line in the alphabetical position among the `INFOPLIST_KEY_*` settings:

```
INFOPLIST_KEY_NSPhotoLibraryUsageDescription = "Attach a photo from your library to ask the on-device model about it.";
```

- [ ] **Step 9.3: Commit**

```bash
cd /Users/rogerio/git/liteRT-LM-Apple
git add Examples/LiteRTLMAppleExample/LiteRTLMAppleExample.xcodeproj/project.pbxproj
git commit -m "feat(sample): declare photo library usage for image attach"
```

## Task 10: Build the sample app for Mac Catalyst

**Files:** none modified.

- [ ] **Step 10.1: Resolve Swift Package Manager state**

```bash
cd /Users/rogerio/git/liteRT-LM-Apple/Examples/LiteRTLMAppleExample
xcodebuild -resolvePackageDependencies -project LiteRTLMAppleExample.xcodeproj 2>&1 | tail -10
```

Expected: `Resolved source packages:` block listing `liteRT-LM-Apple`. If the SPM resolution still points at a remote URL that no longer matches your local edits, switch the package reference to a local path before continuing (Xcode → Package Dependencies → drag the repo root in as a local package, or edit the project.pbxproj `XCRemoteSwiftPackageReference` to a `XCLocalSwiftPackageReference`).

- [ ] **Step 10.2: Build for Mac Catalyst**

```bash
cd /Users/rogerio/git/liteRT-LM-Apple/Examples/LiteRTLMAppleExample
xcodebuild \
  -project LiteRTLMAppleExample.xcodeproj \
  -scheme LiteRTLMAppleExample \
  -destination 'platform=macOS,variant=Mac Catalyst' \
  -configuration Debug \
  build 2>&1 | tail -40
```

Expected: `** BUILD SUCCEEDED **` at the bottom.

- [ ] **Step 10.3: Capture and address any errors**

If the build fails, read the error block, fix in-place (most likely candidates: `litert_lm_*` symbols Swift can't see → check that `engine.h` was refreshed; SwiftUI API misuse on Catalyst → adjust per error). Repeat Step 10.2 until green.

- [ ] **Step 10.4: Commit any compile fixes**

```bash
cd /Users/rogerio/git/liteRT-LM-Apple
git add -p
git commit -m "fix(sample): address Catalyst build issues from C-API rename"
```

(Skip if no fixes were needed.)

## Task 11: End-to-end Catalyst validation with computer use

**Files:** none modified during this task; documentation update follows in Task 12.

- [ ] **Step 11.1: Open the project in Xcode**

```bash
open /Users/rogerio/git/liteRT-LM-Apple/Examples/LiteRTLMAppleExample/LiteRTLMAppleExample.xcodeproj
```

- [ ] **Step 11.2: Set the destination to Mac Catalyst**

Use computer-use to: select `LiteRTLMAppleExample` scheme, click the destination, choose `My Mac (Mac Catalyst)`, click the Run button.

- [ ] **Step 11.3: Download Gemma 4 E2B if not already present**

In the running app, click `Download` on the Gemma 4 E2B card. Wait for completion (≈ 2.6 GB; can take several minutes).

- [ ] **Step 11.4: Make `~/Downloads/IMG_1500.jpg` available to the picker**

`PhotosPicker` reads the user's Photos library. Add `~/Downloads/IMG_1500.jpg` to Photos via Finder if not present:

```bash
osascript -e 'tell application "Photos"
    activate
    import POSIX file "/Users/rogerio/Downloads/IMG_1500.jpg" skip check duplicates true
end tell'
```

(If Photos prompts about permissions, accept them.)

- [ ] **Step 11.5: Attach the image and run inference**

In the running app: click `Attach Image`, pick `IMG_1500.jpg` from Photos, click `"What is this?"` chip, click `Run Inference`. Wait for completion.

- [ ] **Step 11.6: Verify the response is plausible**

Read the response. It should describe what is in the image. If it instead returns a generic "I cannot see images" or hallucinates, the wire format or `max_num_images` setting did not take effect. Re-check Steps 5.1 and 5.2 of the runtime task.

- [ ] **Step 11.7: Capture a screenshot for the docs**

Use computer-use to take a screenshot of the running app showing the image, the prompt, and the response. Save to `docs/images/example-multimodal.jpg`.

```bash
ls -la /Users/rogerio/git/liteRT-LM-Apple/docs/images/example-multimodal.jpg
```

Expected: the file exists.

- [ ] **Step 11.8: Commit the screenshot**

```bash
cd /Users/rogerio/git/liteRT-LM-Apple
git add docs/images/example-multimodal.jpg
git commit -m "docs: add multimodal sample screenshot"
```

## Task 12: Update documentation

**Files:**
- Modify: `README.md`
- Modify: `docs/sample-app.md`
- Modify: `docs/integration-guide.md`
- Modify: `docs/troubleshooting.md`
- Modify: `docs/maintenance-guide.md`

- [ ] **Step 12.1: Update upstream pin reference in `README.md`**

Find `pinned revision: \`e4d5da404e54eeea7903ae23d81fe8447cb3e089\`` and replace with `pinned revision: \`7d1923daaaa1e5143f77f0adb105188e53e8485e\``.

- [ ] **Step 12.2: Add a "Multimodal" section to `README.md`**

Insert this section after `## Sample App` and before `## Screenshots`:

```markdown
## Multimodal

The sample app can attach a photo and ask Gemma 4 about it. Click `Attach Image` in the Prompt card, choose a photo from your Photos library, click the `"What is this?"` chip (or type your own prompt), and run inference. The picker output is re-encoded as JPEG before going to the engine, so HEIC photos from iOS work uniformly on every platform.

The Conversation API on the C surface accepts user messages with mixed image and text content parts:

```json
{"role":"user","content":[
  {"type":"image","blob":"<base64-jpeg>"},
  {"type":"text","text":"What is this?"}
]}
```

Use `litert_lm_engine_settings_set_max_num_images(settings, 1)` before creating the engine on a vision-capable model — leaving it at the default `0` causes the prefill graph to fail with a `DYNAMIC_UPDATE_SLICE` shape mismatch on physical iOS devices.
```

- [ ] **Step 12.3: Add a "What It Demonstrates" entry to `docs/sample-app.md`**

Find the bullet list under `## What It Demonstrates` and append:

```markdown
- attaching a photo and running multimodal inference against Gemma 4
```

- [ ] **Step 12.4: Add a multimodal section to `docs/integration-guide.md`**

Insert after the `## Minimal Runtime Shape` section:

```markdown
## Sending An Image

To attach an image to a user message, embed a base64-encoded JPEG (or any stb_image-decodable format) as the first content part:

```json
{"role":"user","content":[
  {"type":"image","blob":"<base64>"},
  {"type":"text","text":"What is this?"}
]}
```

Before creating the engine, raise the per-prompt image budget so the prefill graph reserves enough KV cache:

```c
litert_lm_engine_settings_set_max_num_images(settings, 1);
```

The engine handles decode, bicubic resize to the model's baked dimension (`768x768` for Gemma 4 E2B / E4B), and `[0, 1]` normalization, so callers do not need to preprocess the bitmap.
```

- [ ] **Step 12.5: Add a multimodal entry to `docs/troubleshooting.md`**

Append:

```markdown
## Multimodal

- "Model says it cannot see images" or returns generic text when an image is attached: check that `litert_lm_engine_settings_set_max_num_images` was called with a value of at least `1` before `litert_lm_engine_create`.
- HEIC photos from the iOS Photos library: re-encode to JPEG (or PNG) before sending. The sample app does this via `ImageDataNormalizer`. The engine's stb_image-based decoder does not support HEIC.
- `DYNAMIC_UPDATE_SLICE` shape mismatch on iOS device prefill: same root cause as above — `max_num_images` left at the default `0`.
- Crash during E4B vision prefill on Apple Silicon: track upstream issue #1933. As a workaround, use Gemma 4 E2B for image testing.
```

- [ ] **Step 12.6: Update `docs/maintenance-guide.md` with the new pin**

Find any reference to the previous revision `e4d5da4...` and replace with `7d1923d...`.

- [ ] **Step 12.7: Commit documentation changes**

```bash
cd /Users/rogerio/git/liteRT-LM-Apple
git add README.md docs/sample-app.md docs/integration-guide.md docs/troubleshooting.md docs/maintenance-guide.md
git commit -m "docs: cover multimodal flow and refreshed upstream pin"
```

## Task 13: Final verification

- [ ] **Step 13.1: Re-run the Catalyst build to confirm cleanliness after docs**

```bash
cd /Users/rogerio/git/liteRT-LM-Apple/Examples/LiteRTLMAppleExample
xcodebuild \
  -project LiteRTLMAppleExample.xcodeproj \
  -scheme LiteRTLMAppleExample \
  -destination 'platform=macOS,variant=Mac Catalyst' \
  -configuration Debug \
  build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 13.2: Optional cross-platform smoke build**

```bash
cd /Users/rogerio/git/liteRT-LM-Apple/Examples/LiteRTLMAppleExample
for dest in 'platform=macOS' 'generic/platform=iOS Simulator' 'generic/platform=visionOS Simulator'; do
  echo "=== $dest ==="
  xcodebuild \
    -project LiteRTLMAppleExample.xcodeproj \
    -scheme LiteRTLMAppleExample \
    -destination "$dest" \
    -configuration Debug \
    build 2>&1 | tail -3
done
```

Expected: each ends with `** BUILD SUCCEEDED **`. If any fail, read errors and either fix or document the failing slice in `docs/troubleshooting.md`.

- [ ] **Step 13.3: Inspect the final commit log**

```bash
cd /Users/rogerio/git/liteRT-LM-Apple
git log --oneline -15
```

Sanity-check that each task corresponds to a commit and there are no obvious omissions. No further action unless you spot a missing step.
