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

To attach an image to a user message, embed a base64-encoded JPEG (or any stb_image-decodable format) as the first content part:

```json
{"role":"user","content":[
  {"type":"image","blob":"<base64>"},
  {"type":"text","text":"What is this?"}
]}
```

Before creating the engine, declare a vision backend so the engine actually instantiates a vision executor, and raise the per-prompt image budget so the prefill graph reserves enough KV cache. The current sample app uses this GPU profile for image prompts:

```c
LiteRtLmEngineSettings* settings = litert_lm_engine_settings_create(
    model_path,
    /*backend_str=*/"gpu",
    /*vision_backend_str=*/"gpu",
    /*audio_backend_str=*/NULL);
litert_lm_engine_settings_set_runtime_library_dir(settings, runtime_library_dir);
litert_lm_engine_settings_set_cache_dir(settings, cache_dir);
litert_lm_engine_settings_set_max_num_images(settings, 1);
litert_lm_engine_settings_set_main_activation_data_type(settings, 1);  // FLOAT16
litert_lm_engine_settings_set_max_num_tokens(settings, 384);
litert_lm_engine_settings_set_advanced_bool(
    settings, kLiteRtLmAdvancedCacheCompiledShadersOnly, true);
litert_lm_engine_settings_set_vision_gpu_bool(
    settings, kLiteRtLmAdvancedCacheCompiledShadersOnly, true);
litert_lm_engine_settings_enable_benchmark(settings);
```

If `vision_backend_str` is left `NULL`, the first image content part will crash inside the runtime (`vision_executor_` is null). If `max_num_images` is left at the default `0`, vision prefill fails with a `DYNAMIC_UPDATE_SLICE` shape mismatch.

Use `"cpu"` for either backend only when you intentionally want a CPU diagnostic path. Avoid setting `prefill_chunk_size` for GPU vision prompts unless you have a specific reason; that override can conflict with the model's baked vision-prefill graph. The sample app caps GPU `max_num_tokens` at `384` because larger budgets can exceed the memory envelope of the current public E4B artifact. The engine handles decode, bicubic resize to the model's baked patch budget, and `[0, 1]` normalization, so callers do not need to preprocess the bitmap beyond providing a decoder-supported image format.

For all-GPU E4B prompts, the sample app also enables `kLiteRtLmAdvancedCacheCompiledShadersOnly` on both the main and vision GPU executors. This avoids the larger cold-cache Metal serialization path that can be killed by iOS memory pressure on first image inference. Explicit DEBUG overrides can still set either option to `false` for diagnostics.

The sample app re-encodes picker output as JPEG before sending it to LiteRT-LM. This is important for HEIC photos from iOS, because the underlying `stb_image` decoder does not support HEIC.

## Current Sample Runtime Defaults

The sample app's `LiteRTLMRuntime` currently applies these defaults when no DEBUG override is provided:

- `backend_str`: `"gpu"`
- `vision_backend_str`: `"gpu"` when image data is attached, `"none"` for text-only prompts
- `audio_backend_str`: `NULL`
- `max_num_images`: `1`
- main activation data type: `1` (`FLOAT16`) for GPU main executor
- max tokens: `384` for GPU main executor
- main GPU cache mode: compiled shaders only
- vision GPU cache mode: compiled shaders only
- session max output tokens: `256`
- benchmark collection: enabled

`LITERT_LM_*` environment variables still exist in the sample app as DEBUG-only diagnostics. They are not required for normal sample app launches.

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
