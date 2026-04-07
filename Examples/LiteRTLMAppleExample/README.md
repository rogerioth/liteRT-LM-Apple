# LiteRTLMAppleExample

This example app shows the intended integration path for this repository:

- fetch `LiteRTLMApple` from GitHub through Swift Package Manager
- download a pinned `.litertlm` model into local app storage
- initialize LiteRT-LM with a cache directory
- run single-turn inference from SwiftUI
- exercise the same flow on iPhone, iPad, or Mac

## Open The Project

```text
Examples/LiteRTLMAppleExample/LiteRTLMAppleExample.xcodeproj
```

On `feat/macos-support`, the project is configured to resolve `LiteRTLMApple` from the matching GitHub branch through Swift Package Manager so the sample reflects the in-progress macOS package state.

If you are running on a physical iOS device, choose your signing team in Xcode before building.

For Mac validation, choose `My Mac` in Xcode. The checked-in macOS slice is Apple Silicon only and requires `macOS 14.0+`.

The current checked-in simulator artifacts are `arm64` only, so Intel simulator builds are not supported by this repository as-is.

## What The App Demonstrates

- a real remote Swift Package Manager dependency on this GitHub repository
- deterministic Hugging Face download URLs for pinned models
- model storage under Application Support
- cache storage under Caches
- a small Swift wrapper around the C conversation API
- structured `print` logging for downloads, runtime setup, inference, and errors in the Xcode console

## Changing The Models

Model metadata lives in `LiteRTLMAppleExample/ModelCatalog.swift`.

Update that file if you want the sample to point at different LiteRT-LM `.litertlm` assets.
