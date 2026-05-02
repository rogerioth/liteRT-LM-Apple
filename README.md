# LiteRT-LM-Apple

[![CircleCI](https://dl.circleci.com/status-badge/img/gh/rogerioth/liteRT-LM-Apple/tree/main.svg?style=svg)](https://dl.circleci.com/status-badge/redirect/gh/rogerioth/liteRT-LM-Apple/tree/main)
[![Quality Gate Status](https://sonarcloud.io/api/project_badges/measure?project=rogerioth_liteRT-LM-Apple&metric=alert_status)](https://sonarcloud.io/summary/new_code?id=rogerioth_liteRT-LM-Apple)

If you want to run LiteRT-LM models inside an iPhone, iPad, Apple Vision Pro, Mac, or Mac Catalyst app, but you do not want to spend your time packaging upstream Apple binaries by hand, this repository is for you.

`LiteRT-LM-Apple` gives you a Swift Package Manager-friendly way to integrate the upstream LiteRT-LM Apple C API into Xcode. You get prebuilt XCFrameworks, a thin package surface, a reproducible rebuild pipeline, and a working sample app that downloads a model locally and runs on-device inference.

If your practical goal is to run Gemma 4 on an iPhone, iPad, Apple Vision Pro, or Apple Silicon Mac, this repository gives you a direct path to do that in a native SwiftUI app.

## Why This Repo Exists

The upstream LiteRT-LM repository is source-first. This repository is integration-first.

If you are evaluating on-device LLM inference for Apple platforms, you usually want to answer questions like these quickly:

- Can I add this to my Xcode project today?
- Can I test model download and inference without inventing my own sample app first?
- Can I rebuild the packaged Apple artifacts later without guessing which Bazel steps matter?

This repo is designed to let you answer "yes" to all three.

## What You Get

- a Swift package product named `LiteRTLMApple`
- prebuilt `LiteRTLMEngineCPU.xcframework`, `LiteRtMetalAccelerator.xcframework`, and `GemmaModelConstraintProvider.xcframework`
- direct access to the upstream `engine.h` C API from Swift and Objective-C
- official package support for iOS, visionOS, Apple Silicon macOS, and Apple Silicon Mac Catalyst
- a complete SwiftUI sample app for local model download and single-turn inference on iPhone, iPad, Apple Vision Pro, native Mac, and Mac Catalyst
- a practical baseline for running Gemma 4 locally on Apple devices
- focused markdown documentation under `docs/` for integration, maintenance, and troubleshooting
- structured Xcode console logging in the sample app so you can see runtime and download failures clearly
- a one-command rebuild pipeline for refreshing the package from the pinned upstream revision

## Who This Is For

This repository is a good fit if you want:

- on-device LLM inference in an iOS, visionOS, or macOS app
- a Swift Package Manager dependency instead of a custom Xcode binary import flow
- a thin wrapper around upstream LiteRT-LM, not a large opinionated SDK
- a reproducible way to rebuild the Apple artifacts when upstream changes

This repository is probably not what you want if you are looking for:

- a full high-level chat SDK
- bundled models inside the package
- training, fine-tuning, or server-side inference tooling

## Quick Start

### Add The Package From GitHub

If you want to integrate this package into another app, use the GitHub repository URL and a tagged release.

- repository URL: `https://github.com/rogerioth/liteRT-LM-Apple.git`
- current release: `v0.2.5`

This branch's sample app intentionally resolves the package from `main` over GitHub SPM so the example tracks the latest unreleased package state (visionOS support, multimodal image input) until the next tag is cut.

In Xcode:

1. Open your project.
2. Choose `File` -> `Add Package Dependencies...`.
3. Enter `https://github.com/rogerioth/liteRT-LM-Apple.git`.
4. Select `Up to Next Minor Version`.
5. Set the version to `0.2.5`.
6. Link the `LiteRTLMApple` product to your app target.

In `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/rogerioth/liteRT-LM-Apple.git", from: "0.2.5")
]
```

Then import the package:

```swift
import LiteRTLMApple
```

### Prefer A Local Checkout?

If you want to inspect or modify the package while integrating it, you can add the repository as a local package instead:

1. Open your Xcode project.
2. Choose `File` -> `Add Package Dependencies...`.
3. Click `Add Local...`.
4. Select this repository.
5. Link the `LiteRTLMApple` product to your app target.

## What Integration Looks Like

The package intentionally stays close to the upstream LiteRT-LM C API. If you want low-level control, you still have it.

Here is a minimal single-turn flow from Swift:

```swift
import Foundation
import LiteRTLMApple

// The sample app's current default profile uses GPU for the main executor and
// GPU for the vision encoder when an image is attached. Use "cpu" for either
// backend if you intentionally want a CPU diagnostic path.
let settings = litert_lm_engine_settings_create(modelPath, "gpu", "gpu", nil)
litert_lm_engine_settings_set_runtime_library_dir(settings, runtimeLibraryDirectory)
litert_lm_engine_settings_set_cache_dir(settings, cacheDirectory)
litert_lm_engine_settings_set_max_num_images(settings, 1)
litert_lm_engine_settings_set_main_activation_data_type(settings, 1) // FLOAT16
litert_lm_engine_settings_set_max_num_tokens(settings, 384)
// E4B all-GPU prompts need the lower-memory CPU weight-conversion path.
litert_lm_engine_settings_set_advanced_bool(settings, kLiteRtLmAdvancedConvertWeightsOnGpu, false)
litert_lm_engine_settings_set_advanced_bool(settings, kLiteRtLmAdvancedCacheCompiledShadersOnly, true)
litert_lm_engine_settings_set_vision_gpu_bool(settings, kLiteRtLmAdvancedCacheCompiledShadersOnly, true)
litert_lm_engine_settings_enable_benchmark(settings)

let engine = litert_lm_engine_create(settings)

let sessionConfig = litert_lm_session_config_create()
litert_lm_session_config_set_max_output_tokens(sessionConfig, 256)

let conversationConfig = litert_lm_conversation_config_create()
litert_lm_conversation_config_set_session_config(conversationConfig, sessionConfig)
litert_lm_conversation_config_set_system_message(conversationConfig, systemMessageJSON)

let conversation = litert_lm_conversation_create(engine, conversationConfig)
let response = litert_lm_conversation_send_message(
    conversation,
    userMessageJSON,
    #"{"enable_thinking":false}"#
)
```

If you want a higher-level reference for model download, cache management, JSON handling, response extraction, and benchmark collection, look at the sample app instead of starting from scratch.

## Sample App

The example project in `Examples/LiteRTLMAppleExample/` shows the complete path most developers care about first:

- choose a pinned LiteRT-LM model
- download the `.litertlm` asset into local app storage
- initialize the engine with a cache directory
- run on-device inference from SwiftUI
- inspect structured `print` logs in the Xcode console

On this branch, the sample is configured as a universal SwiftUI app for iPhone, iPad, Apple Vision Pro, native Mac, and Mac Catalyst. Open it in Xcode and choose `My Mac`, `Apple Vision Pro`, a Mac Catalyst destination, or an iOS destination to exercise the same flow.

The current sample app includes pinned Gemma 4 examples:

- `Gemma 4 E2B` at about `2.58 GB`
- `Gemma 4 E4B` at about `3.65 GB`

That makes this repository a useful starting point if you want to put Gemma 4 directly on Apple hardware instead of routing inference through a server.

The sample runtime currently chooses this profile by default:

- main executor: `gpu`
- vision backend: `gpu` when an image is attached, `none` for text-only prompts unless overridden
- `litert_lm_engine_settings_set_max_num_images(settings, 1)`
- `litert_lm_engine_settings_set_main_activation_data_type(settings, 1)` (`FLOAT16`) for the GPU main executor
- `litert_lm_engine_settings_set_max_num_tokens(settings, 384)` for the GPU main executor
- `litert_lm_engine_settings_set_advanced_bool(settings, kLiteRtLmAdvancedConvertWeightsOnGpu, false)` for E4B on the GPU main executor
- `litert_lm_engine_settings_set_advanced_bool(settings, kLiteRtLmAdvancedCacheCompiledShadersOnly, true)` for the GPU main executor
- `litert_lm_engine_settings_set_vision_gpu_bool(settings, kLiteRtLmAdvancedCacheCompiledShadersOnly, true)` for the GPU vision executor
- `litert_lm_session_config_set_max_output_tokens(sessionConfig, 256)`
- `litert_lm_engine_settings_enable_benchmark(settings)`

The DEBUG sample still accepts `LITERT_LM_*` environment variables for device diagnostics, but regular app launches do not need those variables to use the GPU/GPU path.

Open it here:

```text
Examples/LiteRTLMAppleExample/LiteRTLMAppleExample.xcodeproj
```

If you want to point the sample at different models, update:

`Examples/LiteRTLMAppleExample/LiteRTLMAppleExample/ModelCatalog.swift`

## Multimodal

The sample app can attach a photo and ask Gemma 4 about it. Click `Attach Image` in the Prompt card, choose a photo from your Photos library, click the `"What is this?"` chip (or type your own prompt), and run inference. Picker output is re-encoded as JPEG before reaching the engine, so HEIC photos from iOS work uniformly on every platform.

The Conversation API on the C surface accepts user messages with mixed image and text content parts:

```json
{"role":"user","content":[
  {"type":"image","blob":"<base64-jpeg>"},
  {"type":"text","text":"What is this?"}
]}
```

These settings must be in place before creating the engine on a vision-capable model:

1. Pass `"cpu"` (or `"gpu"`) for `vision_backend_str` in `litert_lm_engine_settings_create` — passing `NULL` skips vision-executor instantiation and the first image content part will crash.
2. Call `litert_lm_engine_settings_set_max_num_images(settings, 1)` (or higher). The default of `0` causes the prefill graph to fail with a `DYNAMIC_UPDATE_SLICE` shape mismatch.
3. If you use the sample app's E4B GPU profile, set the main activation type to `FLOAT16` (`1`) and cap `max_num_tokens` to `384`. Higher GPU token budgets can exceed device memory on current public E4B artifacts.

Leave `prefill_chunk_size` at its model-driven default for GPU vision prompts. On CPU diagnostic paths, avoid overriding `max_num_tokens` or `prefill_chunk_size` unless you know the model artifact supports the requested shape.

## Screenshots

<p align="center">
  <img src="docs/images/example-overview.jpg" alt="LiteRT-LM Apple example app overview screen" width="280" />
  <img src="docs/images/example-chat.jpg" alt="LiteRT-LM Apple example app prompt and response screen" width="280" />
</p>

These screenshots show the current example app flow for selecting a local model, downloading it to the device, and running on-device inference from SwiftUI.

## Why Developers Use This Instead Of Wiring Up Upstream Directly

You can absolutely integrate LiteRT-LM by starting from upstream. This repository is useful when you want to move faster and keep the Apple packaging work out of your application repository.

In practice, that means:

- you do not need to manually export the Apple shared engine dylib yourself
- you do not need to manually build and package XCFrameworks before trying the API
- you still keep access to the original upstream C surface
- you can refresh the package from a pinned upstream revision with one public entrypoint

## Rebuilding The Package

If you need to refresh the checked-in binaries or repackage the library from the pinned upstream LiteRT-LM revision, use:

```bash
./scripts/buildall.sh
```

That script orchestrates the internal subscripts and runs the full pipeline:

1. clones LiteRT-LM into `.worktree/LiteRT-LM`
2. checks out the pinned upstream revision
3. fetches the required Git LFS-backed iOS prebuilts
4. applies the local Apple export patch
5. builds iOS device, iOS simulator, and macOS dylibs with `bazelisk`
6. derives an Apple Silicon Mac Catalyst slice from the iOS simulator dylib because upstream does not ship a dedicated Catalyst binary yet
7. derives visionOS device and simulator slices from the packaged iOS outputs because upstream does not ship dedicated visionOS dylibs yet
8. creates fresh XCFrameworks
9. refreshes the public `engine.h` header exposed by this package

### Requirements

- `git`
- `git-lfs`
- `bazelisk`
- `xcodebuild`
- Xcode command line tools

Updated outputs land in:

- `Artifacts/LiteRTLMEngineCPU.xcframework`
- `Artifacts/LiteRtMetalAccelerator.xcframework`
- `Artifacts/GemmaModelConstraintProvider.xcframework`
- `Sources/LiteRTLMApple/include/engine.h`

## Repository Layout

| Path | Purpose |
| --- | --- |
| `Package.swift` | Swift Package definition |
| `Sources/LiteRTLMApple/include/engine.h` | Public upstream C header exposed to Swift and Objective-C |
| `Artifacts/` | Prebuilt XCFramework artifacts consumed by the package |
| `patches/0001-export-ios-shared-engine-dylib.patch` | Local patch applied before packaging |
| `scripts/buildall.sh` | Public one-pass rebuild entrypoint |
| `scripts/subscripts/` | Internal clone, patch, build, and packaging helpers |
| `docs/` | Extra markdown documentation and screenshots for developers evaluating the package |
| `Examples/LiteRTLMAppleExample/` | SwiftUI sample app for download and inference |

## Documentation

If you want a deeper view than the main README, start here:

- [`docs/README.md`](docs/README.md) for the documentation index
- [`docs/integration-guide.md`](docs/integration-guide.md) for package integration guidance
- [`docs/sample-app.md`](docs/sample-app.md) for the example app structure and extension points
- [`docs/maintenance-guide.md`](docs/maintenance-guide.md) for rebuild and release workflow details
- [`docs/troubleshooting.md`](docs/troubleshooting.md) for common simulator, build, and model-size issues

## Related Repositories

If you want the official upstream sources and the broader Google reference apps around this ecosystem, these are the most relevant repositories:

- [`google-ai-edge/LiteRT-LM`](https://github.com/google-ai-edge/LiteRT-LM) is the upstream LiteRT-LM project this package is built from.
- [`google-ai-edge/gallery`](https://github.com/google-ai-edge/gallery) is Google's on-device ML and GenAI gallery app, which is a useful reference if you want to see how Google presents and experiments with local model experiences.

## Versioning

Swift Package Manager resolves this package from Git tags. If you are integrating it into another project, use a tagged release instead of an arbitrary commit when possible.

Current published release:

- `v0.2.5`

## Upstream Pin

- upstream repository: `https://github.com/google-ai-edge/LiteRT-LM.git`
- pinned revision: `7d1923daaaa1e5143f77f0adb105188e53e8485e`
- configuration source: `scripts/subscripts/common.sh`

## Compatibility Notes

- The package manifest declares `iOS 13.0`, `macOS 14.0`, and `visionOS 1.0`.
- The package supports iOS, visionOS, Apple Silicon native macOS, and Apple Silicon Mac Catalyst.
- The checked-in iOS simulator, visionOS simulator, Mac Catalyst, and macOS XCFramework slices are `arm64` only.
- The current `GemmaModelConstraintProvider` iOS simulator and Mac Catalyst slices have a minimum iOS-family version of `26.2`, so recent simulator or Catalyst runtimes, a real iOS device, or a native Mac build are the safest validation paths.
- The current Mac Catalyst slice is derived from the Apple Silicon iOS simulator dylib because upstream does not publish a dedicated Catalyst binary yet.
- The current visionOS device and simulator slices are derived from the packaged iOS device and iOS simulator dylibs because upstream does not publish dedicated visionOS binaries yet.
- The current checked-in visionOS slices have a minimum version of `1.0`.
- The current checked-in macOS slice has a minimum version of `14.0`.
- The sample app is a reference integration, not a production framework.
- Large LiteRT-LM model files require meaningful disk space and are better evaluated on real hardware when you care about latency.

## License

This repository is licensed under the Apache License 2.0. That matches both:

- [`google-ai-edge/LiteRT-LM`](https://github.com/google-ai-edge/LiteRT-LM)
- [`google-ai-edge/gallery`](https://github.com/google-ai-edge/gallery)

See [`LICENSE`](LICENSE) for the full text.

## If You Want To Start Fast

If your goal is simply to prove that LiteRT-LM can run in your iOS environment, do this:

1. Add the package from GitHub.
2. Open the sample app.
3. Download `Gemma 4 E2B`.
4. Watch the Xcode console while the model downloads and initializes.
5. Use that working path as your baseline before you build your own runtime layer.

That is the shortest path from "interesting repo" to "working on-device inference in Xcode."
