# LiteRT-LM-Apple

`LiteRT-LM-Apple` packages the LiteRT-LM C API for iOS as a local Swift Package
with XCFramework artifacts.

The repository owns the full repeatable pipeline:

1. Clone `google-ai-edge/LiteRT-LM` at a pinned base revision.
2. Apply the Apple/iOS shared-library export patch.
3. Build the device and simulator dylibs with `bazelisk`.
4. Package the dylibs into XCFrameworks under `Artifacts/`.
5. Refresh the public C header used by the Swift package target.

## Requirements

- `git`
- `git-lfs`
- `bazelisk`
- `xcodebuild`
- Xcode command line tools

## Refresh The Package

```bash
./scripts/refresh_package.sh
```

That command will:

1. clone LiteRT-LM into `.worktree/LiteRT-LM`
2. check out the pinned upstream revision
3. fetch the Git LFS-backed iOS prebuilt dylibs
4. apply the local Apple/iOS patch
5. build the device and simulator dylibs with `bazelisk`
6. update:

- `Artifacts/LiteRTLMEngineCPU.xcframework`
- `Artifacts/GemmaModelConstraintProvider.xcframework`
- `Sources/LiteRTLMApple/include/engine.h`

## Package Usage

Add the local package at:

```text
/Users/rogeriohirooka/git/liteRT-LM-Apple
```

Then link the `LiteRTLMApple` product from Xcode. Swift code can import the C
module directly:

```swift
import LiteRTLMApple
```

## Upstream Pin

- Upstream URL: `https://github.com/google-ai-edge/LiteRT-LM.git`
- Base revision: `e4d5da404e54eeea7903ae23d81fe8447cb3e089`
- Script config: `scripts/common.sh`
- Patch result matches local work previously validated on device.
