# Sample App Guide

The sample app under `Examples/LiteRTLMAppleExample/` is the fastest way to see this package doing useful work.

## What It Demonstrates

- selecting a pinned LiteRT-LM model
- downloading the model into local app storage
- storing runtime cache data separately
- running single-turn inference from SwiftUI
- printing structured runtime and download logs into the Xcode console

## Current Pinned Models

- `Gemma 4 E2B`
- `Gemma 4 E4B`

These models are pinned in `Examples/LiteRTLMAppleExample/LiteRTLMAppleExample/ModelCatalog.swift`.

## Important Files

- `ContentView.swift`: the sample app interface
- `InferenceViewModel.swift`: presentation state and action orchestration
- `ModelStore.swift`: local file management and model downloads
- `LiteRTLMRuntime.swift`: the Swift wrapper around the LiteRT-LM C API
- `ConsoleLog.swift`: structured `print` logging for Xcode

## What To Change First

If you want to adapt the example for your own use, the most common starting points are:

- update `ModelCatalog.swift` to point at different `.litertlm` assets
- adjust the prompt and response flow in `InferenceViewModel.swift`
- evolve `LiteRTLMRuntime.swift` into a reusable app-specific service

## Why The Sample Matters

This repository is most compelling when it gets you from package installation to local Gemma 4 inference quickly.

The example app is where that promise becomes concrete.
