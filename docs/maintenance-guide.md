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
3. Fetches Git LFS-backed prebuilt dependencies required by upstream.
4. Applies the local export patch.
5. Builds device and simulator dylibs with `bazelisk`.
6. Repackages them as XCFrameworks.
7. Refreshes the public `engine.h` header exposed by this package.

## When To Run It

Run the rebuild flow when:

- you want to update the upstream pinned revision
- you need to regenerate the XCFrameworks
- you want to verify that checked-in artifacts still reproduce cleanly

## Release Model

Swift Package Manager versions this repository from Git tags.

In practice, publishing means:

1. push the commit you want on `main`
2. create a semver tag
3. push the tag
4. create a GitHub release

## Files That Usually Change During Maintenance

- `Artifacts/LiteRTLMEngineCPU.xcframework`
- `Artifacts/GemmaModelConstraintProvider.xcframework`
- `Sources/LiteRTLMApple/include/engine.h`
- `README.md` when user-facing setup or compatibility notes change
