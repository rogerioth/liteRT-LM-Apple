# LiteRTLMAppleExample

This example app shows the intended integration path for this repository:

- add `LiteRTLMApple` as a local Swift package
- download a pinned `.litertlm` model into local app storage
- initialize LiteRT-LM with a cache directory
- run single-turn inference from SwiftUI

## Open The Project

```text
Examples/LiteRTLMAppleExample/LiteRTLMAppleExample.xcodeproj
```

If you are running on a physical device, choose your signing team in Xcode before building.

The current checked-in simulator artifacts are `arm64` only, so Intel simulator builds are not supported by this repository as-is.

## What The App Demonstrates

- local package linking back to the repository root
- deterministic Hugging Face download URLs for pinned models
- model storage under Application Support
- cache storage under Caches
- a small Swift wrapper around the C conversation API
- structured `print` logging for downloads, runtime setup, inference, and errors in the Xcode console

## Changing The Models

Model metadata lives in `LiteRTLMAppleExample/ModelCatalog.swift`.

Update that file if you want the sample to point at different LiteRT-LM `.litertlm` assets.
