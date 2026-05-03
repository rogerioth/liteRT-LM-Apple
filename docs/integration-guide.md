# Integration Guide

This package exists to make LiteRT-LM feel like a normal Swift Package Manager dependency in an iOS, visionOS, macOS, or Mac Catalyst app.

## Add The Package

Use the repository URL:

```text
https://github.com/rogerioth/liteRT-LM-Apple.git
```

In Xcode:

1. Open your app project.
2. Choose `File` -> `Add Package Dependencies...`.
3. Enter the repository URL.
4. Select the version you want to consume.
5. Link `LiteRTLMApple` to your app target.

In `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/rogerioth/liteRT-LM-Apple.git", from: "0.2.5")
]
```

If you want to track the latest unreleased package state (visionOS support, multimodal image input, refreshed upstream pin) before the next tagged release, you can point SPM at `main` instead:

```swift
dependencies: [
    .package(url: "https://github.com/rogerioth/liteRT-LM-Apple.git", branch: "main")
]
```

## What You Import

```swift
import LiteRTLMApple
```

The package exposes the upstream LiteRT-LM C surface directly through the packaged headers and binary targets. It does not try to hide the upstream API behind a large Swift abstraction layer.

## Platform Notes

- This branch supports `iOS 13.0+`.
- This branch supports `visionOS 1.0+`.
- This branch supports Apple Silicon `macOS 14.0+`.
- This branch supports Apple Silicon Mac Catalyst.
- The checked-in iOS simulator, visionOS simulator, Mac Catalyst, and macOS slices are `arm64` only.
- The current Mac Catalyst slice is derived from the Apple Silicon iOS simulator dylib because upstream does not publish a dedicated Catalyst binary yet.
- The current visionOS device and simulator slices are derived from the packaged iOS device and iOS simulator dylibs because upstream does not publish dedicated visionOS binaries yet.

## What Your App Needs To Provide

At integration time, your app is still responsible for a few runtime decisions:

- where the `.litertlm` model file lives on disk
- where the LiteRT-LM cache directory should live
- how prompts and response JSON are encoded and decoded
- what UI or state model you want around download and inference

If you want a working reference for those pieces, use the sample app in `Examples/LiteRTLMAppleExample/`.

## Minimal Runtime Shape

At a high level, LiteRT-LM usage looks like this:

1. Create engine settings with the model path.
2. Set the runtime library directory if you depend on dynamically loaded accelerators.
3. Set the cache directory.
4. Set model/runtime limits such as image count and token budget.
5. Create the engine.
6. Create a session config.
7. Create a conversation config.
8. Send a JSON message payload.
9. Parse the JSON response payload.

The main README includes a small Swift example for that flow.

## Sending An Image

To attach an image to a user message, embed a base64-encoded PNG (or any other `stb_image`-decodable format) as the first content part:

```json
{"role":"user","content":[
  {"type":"image","blob":"<base64>"},
  {"type":"text","text":"What is this?"}
]}
```

If you go through the sample app's `LiteRTLMRuntime` wrapper, the Swift API takes care of the boilerplate:

```swift
let result = try await LiteRTLMRuntime().generateResponse(
    modelURL: modelURL,
    cacheDirectory: cacheDirectory,
    inputs: InferenceInputs(prompt: "What is this?", imageData: pngData),
    options: LiteRTLMRuntimeOptions()
)
```

If you call the C API directly, the sample app's effective GPU profile for image prompts is:

```c
LiteRtLmEngineSettings* settings = litert_lm_engine_settings_create(
    model_path,
    /*backend_str=*/"gpu",
    /*vision_backend_str=*/"cpu",            // Gemma 4 default; see note below
    /*audio_backend_str=*/NULL);
litert_lm_engine_settings_set_runtime_library_dir(settings, runtime_library_dir);
litert_lm_engine_settings_set_cache_dir(settings, cache_dir);
litert_lm_engine_settings_set_max_num_images(settings, 1);
litert_lm_engine_settings_set_main_activation_data_type(settings, 1);  // FLOAT16
litert_lm_engine_settings_set_max_num_tokens(settings, 384);
litert_lm_engine_settings_set_advanced_bool(
    settings, kLiteRtLmAdvancedConvertWeightsOnGpu, false);  // E4B only
litert_lm_engine_settings_set_advanced_bool(
    settings, kLiteRtLmAdvancedCacheCompiledShadersOnly, true);
litert_lm_engine_settings_enable_benchmark(settings);
```

A few subtleties worth knowing:

- If `vision_backend_str` is left `NULL`, the first image content part will crash inside the runtime (`vision_executor_` is null).
- If `max_num_images` is left at the default `0`, vision prefill fails with a `DYNAMIC_UPDATE_SLICE` shape mismatch.
- For Gemma 4 image prompts, prefer `vision_backend_str = "cpu"`. The Metal vision encoder currently runs in FP16 (the C wrapper's memory-saving default) and produces semantically wrong embeddings for Gemma 4 — the dog test photo is described as "a crowd of people" or "a person's face". Forcing FP32 vision GPU restores correctness but exceeds iOS cold-start memory limits when paired with the GPU main executor. The sample app's `LiteRTLMRuntimeOptions.visionBackend` defaults to `.cpu` for Gemma 4 to side-step both failure modes.
- For E4B specifically, also set main `kLiteRtLmAdvancedConvertWeightsOnGpu = false` and the vision-GPU `cache_compiled_shaders_only = true` if you are running vision GPU. CPU-side weight conversion is slower during cold engine creation, but it lowers the pre-`send_message` process footprint enough to fit the tested memory budget on iPhone 16 Pro Max and iPhone 17 Pro Max.
- Avoid setting `prefill_chunk_size` for GPU vision prompts unless you have a specific reason; that override can conflict with the model's baked vision-prefill graph.

The sample app applies EXIF orientation, downsizes picker output to a 1024-pixel longest edge, and re-encodes it as PNG before sending it to LiteRT-LM. Re-encoding is important for HEIC photos from iOS, because the underlying `stb_image` decoder does not support HEIC.

## Current Sample Runtime Defaults

The sample app's `LiteRTLMRuntimeOptions()` ships with these defaults:

- `backend`: `.gpu`
- `visionBackend`: `nil` — runtime resolves to `.cpu` for Gemma 4 image prompts (E2B and E4B), otherwise mirrors `backend` when an image is attached, otherwise no vision executor
- audio backend: not instantiated
- `maxNumImages`: `1`
- `mainActivationDataType`: `nil` — runtime resolves to `.float16` on GPU main
- `maxNumTokens`: `nil` — runtime resolves to `384` on GPU main
- `advanced.gpuConvertWeightsOnGpu`: `nil` — runtime resolves to `false` for E4B on GPU main
- `advanced.gpuCacheCompiledShadersOnly`: `nil` — runtime resolves to `true` on GPU main
- `visionGPU.cacheCompiledShadersOnly`: `nil` — runtime resolves to `true` when vision is GPU
- `cpuKernelMode`: `nil` — runtime resolves to `.builtin` for E4B main-CPU + vision-GPU; otherwise upstream default
- session max output tokens: `256` (currently hard-coded in `LiteRTLMRuntime`)
- `benchmark`: `true`

There are no environment-variable overrides. To change any setting per-call, mutate the corresponding field on `LiteRTLMRuntimeOptions` before passing it to `generateResponse`.

The benchmark fields exposed in the sample UI and logs are:

- initialization time from `litert_lm_benchmark_info_get_total_init_time_in_second`
- time to first token from `litert_lm_benchmark_info_get_time_to_first_token`
- per-turn prefill token count and throughput from `litert_lm_benchmark_info_get_num_prefill_turns`, `litert_lm_benchmark_info_get_prefill_token_count_at`, and `litert_lm_benchmark_info_get_prefill_tokens_per_sec_at`
- per-turn decode token count and throughput from `litert_lm_benchmark_info_get_num_decode_turns`, `litert_lm_benchmark_info_get_decode_token_count_at`, and `litert_lm_benchmark_info_get_decode_tokens_per_sec_at`

## When To Use The Sample App First

If your real goal is "prove Gemma 4 can run on this device," start with the sample app before building your own runtime layer.

That path gives you:

- pinned model download URLs
- local storage handling
- cache directory creation
- inference execution
- benchmark collection
- Xcode console logging for downloads and runtime setup
- one tested SwiftUI flow that now works on iPhone, iPad, Apple Vision Pro, native Mac, and Mac Catalyst
