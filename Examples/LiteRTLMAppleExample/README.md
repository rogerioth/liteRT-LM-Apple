# LiteRTLMAppleExample

This example app shows the intended integration path for this repository:

- fetch `LiteRTLMApple` from GitHub through Swift Package Manager
- download a pinned `.litertlm` model into local app storage
- initialize LiteRT-LM with a cache directory
- run single-turn inference from SwiftUI
- exercise the same flow on iPhone, iPad, Apple Vision Pro, or Mac

## Open The Project

```text
Examples/LiteRTLMAppleExample/LiteRTLMAppleExample.xcodeproj
```

The project is configured to resolve `LiteRTLMApple` from the GitHub `main` branch through Swift Package Manager so the sample reflects the latest unreleased package state, including the new visionOS slices and multimodal image input.

If you are running on a physical iOS device, choose your signing team in Xcode before building.

For visionOS validation, choose `Apple Vision Pro` or `Any visionOS Device` in Xcode. The checked-in visionOS device and simulator slices are Apple Silicon only and are currently derived from the packaged iOS device and iOS simulator dylibs because upstream does not ship dedicated visionOS binaries.

For native Mac validation, choose `My Mac` in Xcode. The checked-in macOS slice is Apple Silicon only and requires `macOS 14.0+`.

For Mac Catalyst validation, choose a Mac Catalyst destination in Xcode. The checked-in Catalyst slice is Apple Silicon only and is currently derived from the packaged Apple Silicon iOS simulator dylib because upstream does not ship a dedicated Catalyst binary.

The current checked-in iOS simulator, visionOS simulator, and Catalyst artifacts are `arm64` only, so Intel simulator or Intel Catalyst builds are not supported by this repository as-is.

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
