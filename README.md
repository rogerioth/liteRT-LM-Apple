# LiteRT-LM-Apple

If you want to run LiteRT-LM models inside an iPhone or iPad app, but you do not want to spend your time packaging upstream Apple binaries by hand, this repository is for you.

`LiteRT-LM-Apple` gives you a Swift Package Manager-friendly way to integrate the upstream LiteRT-LM iOS C API into Xcode. You get prebuilt XCFrameworks, a thin package surface, a reproducible rebuild pipeline, and a working sample app that downloads a model locally and runs on-device inference.

If your practical goal is to run Gemma 4 on an iPhone or iPad, this repository gives you a direct path to do that in a native iOS app.

## Why This Repo Exists

The upstream LiteRT-LM repository is source-first. This repository is integration-first.

If you are evaluating on-device LLM inference for iOS, you usually want to answer questions like these quickly:

- Can I add this to my Xcode project today?
- Can I test model download and inference without inventing my own sample app first?
- Can I rebuild the packaged Apple artifacts later without guessing which Bazel steps matter?

This repo is designed to let you answer "yes" to all three.

## What You Get

- a Swift package product named `LiteRTLMApple`
- prebuilt `LiteRTLMEngineCPU.xcframework` and `GemmaModelConstraintProvider.xcframework`
- direct access to the upstream `engine.h` C API from Swift and Objective-C
- a complete SwiftUI sample app for local model download and single-turn inference
- a practical baseline for running Gemma 4 locally on iOS devices
- structured Xcode console logging in the sample app so you can see runtime and download failures clearly
- a one-command rebuild pipeline for refreshing the package from the pinned upstream revision

## Who This Is For

This repository is a good fit if you want:

- on-device LLM inference in an iOS app
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
- current release: `v0.2.0`

In Xcode:

1. Open your project.
2. Choose `File` -> `Add Package Dependencies...`.
3. Enter `https://github.com/rogerioth/liteRT-LM-Apple.git`.
4. Select `Up to Next Minor Version`.
5. Set the version to `0.2.0`.
6. Link the `LiteRTLMApple` product to your app target.

In `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/rogerioth/liteRT-LM-Apple.git", from: "0.2.0")
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

let settings = litert_lm_engine_settings_create(modelPath, "cpu", nil, nil)
litert_lm_engine_settings_set_cache_dir(settings, cacheDirectory)

let engine = litert_lm_engine_create(settings)
let sessionConfig = litert_lm_session_config_create()
litert_lm_session_config_set_max_output_tokens(sessionConfig, 256)

let conversationConfig = litert_lm_conversation_config_create(
    engine,
    sessionConfig,
    systemMessageJSON,
    nil,
    nil,
    false
)

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

The current sample app includes pinned Gemma 4 examples:

- `Gemma 4 E2B` at about `2.58 GB`
- `Gemma 4 E4B` at about `3.65 GB`

That makes this repository a useful starting point if you want to put Gemma 4 directly on mobile iOS hardware instead of routing inference through a server.

Open it here:

```text
Examples/LiteRTLMAppleExample/LiteRTLMAppleExample.xcodeproj
```

If you want to point the sample at different models, update:

`Examples/LiteRTLMAppleExample/LiteRTLMAppleExample/ModelCatalog.swift`

## Why Developers Use This Instead Of Wiring Up Upstream Directly

You can absolutely integrate LiteRT-LM by starting from upstream. This repository is useful when you want to move faster and keep the Apple packaging work out of your application repository.

In practice, that means:

- you do not need to manually export the iOS shared engine dylib yourself
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
5. builds device and simulator dylibs with `bazelisk`
6. creates fresh XCFrameworks
7. refreshes the public `engine.h` header exposed by this package

### Requirements

- `git`
- `git-lfs`
- `bazelisk`
- `xcodebuild`
- Xcode command line tools

Updated outputs land in:

- `Artifacts/LiteRTLMEngineCPU.xcframework`
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
| `Examples/LiteRTLMAppleExample/` | SwiftUI sample app for download and inference |

## Related Repositories

If you want the official upstream sources and the broader Google reference apps around this ecosystem, these are the most relevant repositories:

- [`google-ai-edge/LiteRT-LM`](https://github.com/google-ai-edge/LiteRT-LM) is the upstream LiteRT-LM project this package is built from.
- [`google-ai-edge/gallery`](https://github.com/google-ai-edge/gallery) is Google's on-device ML and GenAI gallery app, which is a useful reference if you want to see how Google presents and experiments with local model experiences.

## Versioning

Swift Package Manager resolves this package from Git tags. If you are integrating it into another project, use a tagged release instead of an arbitrary commit when possible.

Current published release:

- `v0.2.0`

## Upstream Pin

- upstream repository: `https://github.com/google-ai-edge/LiteRT-LM.git`
- pinned revision: `e4d5da404e54eeea7903ae23d81fe8447cb3e089`
- configuration source: `scripts/subscripts/common.sh`

## Compatibility Notes

- The package manifest declares `iOS 13.0`.
- The package is iOS-only.
- The checked-in simulator XCFramework slices are `arm64` only.
- The current `GemmaModelConstraintProvider` simulator slice has a minimum iOS simulator version of `26.2`, so recent simulator runtimes or a real device are the safest path when validating the sample app.
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
