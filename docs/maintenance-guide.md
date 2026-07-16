# Maintenance Guide

This repository keeps the public Swift package thin, but it still needs a repeatable way to rebuild the checked-in Apple artifacts from upstream LiteRT-LM.

## One-Pass Rebuild

Use:

```bash
./scripts/buildall.sh
```

That top-level script is the public entrypoint. It delegates to the helper scripts in `scripts/subscripts/`.

## What The Rebuild Does

1. Clones the pinned upstream LiteRT-LM repository into `.worktree/LiteRT-LM`.
2. Checks out the configured upstream revision.
3. Fetches Git LFS-backed prebuilt dependencies required by upstream, including the official TopK Metal sampler overlay.
4. Applies the local export patch.
5. Builds iOS device, iOS simulator, and macOS dylibs with `bazelisk`.
6. Derives an Apple Silicon Mac Catalyst slice from the iOS simulator dylib.
7. Derives visionOS device and simulator slices from the packaged iOS outputs.
8. Repackages them as XCFrameworks.
9. Refreshes the public `engine.h` header exposed by this package.

## When To Run It

Run the rebuild flow when:

- you want to update the upstream pinned revision
- you want to refresh or re-check the official TopK Metal sampler overlay revision
- you need to regenerate the XCFrameworks
- you want to verify that checked-in artifacts still reproduce cleanly

## Release Model

Swift Package Manager versions this repository from Git tags.

In practice, publishing means:

1. push the commit you want on `main`
2. create a semver tag
3. push the tag
4. create a GitHub release

If the sample project is temporarily following a feature branch through remote SPM during development, switch it back to a tagged version requirement as part of the release cut.

## Files That Usually Change During Maintenance

- `Artifacts/LiteRTLMEngineCPU.xcframework`
- `Artifacts/LiteRtMetalAccelerator.xcframework`
- `Artifacts/LiteRtTopKMetalSampler.xcframework`
- `Artifacts/GemmaModelConstraintProvider.xcframework`
- `Sources/LiteRTLMApple/include/engine.h`
- `README.md` when user-facing setup or compatibility notes change

The current Catalyst and visionOS packaging is intentionally explicit about upstream limitations: LiteRT-LM does not publish dedicated Catalyst or visionOS dylibs today, so this repository derives those slices from the packaged iOS outputs and validates them through Xcode.

## Upstream Pins

The engine source and TopK Metal sampler overlay are configured separately in `scripts/subscripts/common.sh`.

- engine source: `UPSTREAM_BASE_REVISION_DEFAULT`
- official TopK Metal sampler overlay: `UPSTREAM_TOPK_SAMPLER_REVISION_DEFAULT`

Keep those pins separate until the engine source revision is moved to a Google LiteRT-LM revision that already contains the usable iOS sampler export set and the local patch is refreshed against that revision.
