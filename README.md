# LiteRT-LM-Apple

`LiteRT-LM-Apple` is a local Swift Package that packages the upstream LiteRT-LM iOS C API as prebuilt XCFrameworks.

It is intentionally thin:

- no generated Swift wrapper
- no opinionated runtime layer
- no model assets bundled into the package

You get the upstream `engine.h` surface, packaged so an iOS app can link it from Xcode with minimal friction.

## What This Repository Provides

- `LiteRTLMApple`, a Swift package product for iOS
- `LiteRTLMEngineCPU.xcframework`, built for device and simulator
- `GemmaModelConstraintProvider.xcframework`, built for device and simulator
- a pinned, repeatable refresh pipeline for rebuilding artifacts from upstream
- a complete iOS sample app that downloads a model locally and runs on-device inference

## Repository Layout

| Path | Purpose |
| --- | --- |
| `Package.swift` | Local Swift Package definition |
| `Sources/LiteRTLMApple/include/engine.h` | Public upstream C header exposed to Swift/ObjC |
| `Artifacts/` | Prebuilt XCFramework artifacts consumed by the package |
| `patches/0001-export-ios-shared-engine-dylib.patch` | Local patch applied to upstream LiteRT-LM |
| `scripts/` | Clone, patch, build, package, and refresh helpers |
| `Examples/LiteRTLMAppleExample/` | SwiftUI sample app for local model download and inference |

## Quick Start

### Add The Package To An App

1. Open your Xcode project.
2. Choose `File` -> `Add Package Dependencies...`.
3. Click `Add Local...` and select this repository.
4. Link the `LiteRTLMApple` product to your app target.

Swift can then import the package directly:

```swift
import LiteRTLMApple
```

## Using The C API From Swift

The package exposes the upstream LiteRT-LM C entry points directly. A minimal single-turn flow looks like this:

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

For a complete Swift wrapper that handles engine setup, cache directories, JSON encoding, response extraction, benchmark info, and model download workflow, see the sample app under `Examples/LiteRTLMAppleExample/`.

## Sample iOS App

`Examples/LiteRTLMAppleExample/` contains a complete SwiftUI reference app that demonstrates:

- selecting a pinned LiteRT-LM model
- downloading the `.litertlm` file to local app storage
- running single-turn inference through `LiteRTLMApple`
- surfacing response text and basic benchmark metrics

The sample currently includes pinned Gemma 4 entries derived from the Gallery allowlist workflow:

- `Gemma 4 E2B` (`gemma-4-E2B-it.litertlm`, about 2.58 GB)
- `Gemma 4 E4B` (`gemma-4-E4B-it.litertlm`, about 3.65 GB)

Open the project at:

```text
Examples/LiteRTLMAppleExample/LiteRTLMAppleExample.xcodeproj
```

If you want to point the sample at a different LiteRT-LM model, update `Examples/LiteRTLMAppleExample/LiteRTLMAppleExample/ModelCatalog.swift`.

## Refreshing The Package

### Requirements

- `git`
- `git-lfs`
- `bazelisk`
- `xcodebuild`
- Xcode command line tools

### Rebuild From The Pinned Upstream Revision

```bash
./scripts/buildall.sh
```

That workflow:

1. clones LiteRT-LM into `.worktree/LiteRT-LM`
2. checks out the pinned upstream revision
3. fetches the Git LFS-backed iOS prebuilts needed by upstream
4. applies the local Apple export patch
5. builds device and simulator dylibs with `bazelisk`
6. repackages the results into local XCFrameworks
7. refreshes the public `engine.h` header exposed by this package

`./scripts/refresh_package.sh` and `./scripts/rebuild_package.sh` remain available as compatibility wrappers around the same one-pass orchestration.

Updated outputs land in:

- `Artifacts/LiteRTLMEngineCPU.xcframework`
- `Artifacts/GemmaModelConstraintProvider.xcframework`
- `Sources/LiteRTLMApple/include/engine.h`

## Upstream Pin

- Upstream repository: `https://github.com/google-ai-edge/LiteRT-LM.git`
- Pinned revision: `e4d5da404e54eeea7903ae23d81fe8447cb3e089`
- Configuration source: `scripts/common.sh`

## Notes

- The package is iOS-only.
- The checked-in simulator XCFramework slices are `arm64` only.
- The sample app is intended as a reference integration rather than a production-ready template.
- Large LiteRT-LM model files require significant disk space and are best tested on real hardware for meaningful latency measurements.
