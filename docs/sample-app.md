# Sample App Guide

The sample app under `Examples/LiteRTLMAppleExample/` is the fastest way to see this package doing useful work on iPhone, iPad, Apple Vision Pro, native Mac, and Mac Catalyst.

## What It Demonstrates

- selecting a pinned LiteRT-LM model
- downloading the model into local app storage
- storing runtime cache data separately
- running single-turn inference from SwiftUI
- attaching a photo and running multimodal inference against Gemma 4
- using the GPU main / CPU vision profile by default for Gemma 4 image prompts
- per-call configuration through the `LiteRTLMRuntimeOptions` struct
- displaying initialization, TTFT, prefill, and decode benchmark metrics
- printing structured runtime and download logs into the Xcode console
- resolving the package remotely through GitHub Swift Package Manager

## Current Pinned Models

- `Gemma 4 E2B`
- `Gemma 4 E4B`

These models are pinned in `Examples/LiteRTLMAppleExample/LiteRTLMAppleExample/ModelCatalog.swift`.

## Important Files

- `ContentView.swift`: the sample app interface
- `InferenceViewModel.swift`: presentation state and action orchestration
- `ModelStore.swift`: local file management and model downloads
- `LiteRTLMRuntime.swift`: the Swift wrapper around the LiteRT-LM C API
- `LiteRTLMRuntimeOptions.swift`: per-call configuration struct passed to the runtime
- `ImageDataNormalizer.swift`: EXIF-aware 1024px PNG normalization for Photos picker output, including HEIC inputs
- `PhaseTiming.swift`: app-side wall-clock timing for setup, image normalization, engine creation, send, parse, and total runtime
- `SmokeTestRunner.swift`: DEBUG-only device smoke runner used by `devicectl`
- `ConsoleLog.swift`: structured `print` logging for Xcode
- `LiteRTLMAppleExample.xcodeproj/project.pbxproj`: the cross-platform target and SPM dependency settings

## Runtime Defaults

`LiteRTLMRuntimeOptions()` ships with these defaults:

- `backend`: `.gpu`
- `visionBackend`: runtime resolves to `.cpu` for Gemma 4 image prompts (E2B and E4B), otherwise mirrors `backend` when an image is attached, otherwise no vision executor
- `maxNumImages`: `1`
- `mainActivationDataType`: runtime resolves to `.float16` on GPU main
- `maxNumTokens`: runtime resolves to `384` on GPU main
- `advanced.gpuConvertWeightsOnGpu`: runtime resolves to `false` for E4B on GPU main
- `advanced.gpuCacheCompiledShadersOnly`: runtime resolves to `true` on GPU main
- `visionGPU.cacheCompiledShadersOnly`: runtime resolves to `true` when vision is GPU
- `cpuKernelMode`: runtime resolves to `.builtin` for E4B main-CPU + vision-GPU; otherwise upstream default
- session max output tokens: `256` (currently hard-coded in `LiteRTLMRuntime`)
- `benchmark`: `true`

There are no environment-variable overrides. Per-call tuning happens through `LiteRTLMRuntimeOptions`; mutate any field on the struct before calling `generateResponse(modelURL:cacheDirectory:inputs:options:)`.

## Current Branch Setup

The sample project resolves `LiteRTLMApple` from the GitHub `main` branch instead of the last tagged release. That keeps the example closer to the real remote-consumption path while the visionOS and multimodal work is still in flight ahead of the next release cut.

## What To Change First

If you want to adapt the example for your own use, the most common starting points are:

- update `ModelCatalog.swift` to point at different `.litertlm` assets
- adjust the default runtime profile in `LiteRTLMRuntime.swift`
- adjust the prompt and response flow in `InferenceViewModel.swift`
- evolve `LiteRTLMRuntime.swift` into a reusable app-specific service

## Why The Sample Matters

This repository is most compelling when it gets you from package installation to local Gemma 4 inference quickly on the Apple device you already have in front of you.

The example app is where that promise becomes concrete.
