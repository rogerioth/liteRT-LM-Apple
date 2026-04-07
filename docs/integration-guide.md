# Integration Guide

This package exists to make LiteRT-LM feel like a normal Swift Package Manager dependency in an iOS, tvOS, visionOS, macOS, or Mac Catalyst app.

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
    .package(url: "https://github.com/rogerioth/liteRT-LM-Apple.git", from: "0.2.3")
]
```

If you are evaluating this feature branch before the next tagged release, you can point SPM at the in-flight branch instead:

```swift
dependencies: [
    .package(url: "https://github.com/rogerioth/liteRT-LM-Apple.git", branch: "feat/tvos-support")
]
```

## What You Import

```swift
import LiteRTLMApple
```

The package exposes the upstream LiteRT-LM C surface directly through the packaged headers and binary targets. It does not try to hide the upstream API behind a large Swift abstraction layer.

## Platform Notes

- This branch supports `iOS 13.0+`.
- This branch supports `tvOS 13.0+`.
- This branch supports `visionOS 1.0+`.
- This branch supports Apple Silicon `macOS 14.0+`.
- This branch supports Apple Silicon Mac Catalyst.
- The checked-in iOS simulator, tvOS simulator, visionOS simulator, Mac Catalyst, and macOS slices are `arm64` only.
- The current tvOS device and simulator slices are derived from the packaged iOS device and iOS simulator dylibs because upstream does not publish dedicated tvOS binaries yet.
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

## When To Use The Sample App First

If your real goal is "prove Gemma 4 can run on this device," start with the sample app before building your own runtime layer.

That path gives you:

- pinned model download URLs
- local storage handling
- cache directory creation
- inference execution
- benchmark collection
- Xcode console logging for downloads and runtime setup
- one tested SwiftUI flow that now works on iPhone, iPad, Apple TV, Apple Vision Pro, native Mac, and Mac Catalyst
