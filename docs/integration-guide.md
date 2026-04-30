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
2. Set the cache directory.
3. Create the engine.
4. Create a session config.
5. Create a conversation config.
6. Send a JSON message payload.
7. Parse the JSON response payload.

The main README includes a small Swift example for that flow.

## Sending An Image

To attach an image to a user message, embed a base64-encoded JPEG (or any stb_image-decodable format) as the first content part:

```json
{"role":"user","content":[
  {"type":"image","blob":"<base64>"},
  {"type":"text","text":"What is this?"}
]}
```

Before creating the engine, declare a vision backend so the engine actually instantiates a vision executor, and raise the per-prompt image budget so the prefill graph reserves enough KV cache:

```c
LiteRtLmEngineSettings* settings = litert_lm_engine_settings_create(
    model_path,
    /*backend_str=*/"cpu",
    /*vision_backend_str=*/"cpu",
    /*audio_backend_str=*/NULL);
litert_lm_engine_settings_set_max_num_images(settings, 1);
```

If `vision_backend_str` is left `NULL`, the first image content part will crash inside the runtime (`vision_executor_` is null). If `max_num_images` is left at the default `0`, vision prefill fails with a `DYNAMIC_UPDATE_SLICE` shape mismatch.

Avoid setting `max_num_tokens` or `prefill_chunk_size` for vision prompts unless you have a specific reason; those overrides can conflict with the model's baked vision-prefill graph. The engine handles decode, bicubic resize to the model's baked dimension (`768x768` for Gemma 4 E2B / E4B), and `[0, 1]` normalization, so callers do not need to preprocess the bitmap.

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
