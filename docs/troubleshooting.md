# Troubleshooting

This project is intentionally simple to consume, but a few issues show up repeatedly when developers evaluate local Apple-device inference.

## The Package Resolves, But The Sample App Does Not Run In My Simulator

The checked-in simulator artifacts are `arm64` only.

That means:

- Apple Silicon simulator environments are the intended path
- Intel simulator environments are not supported by the current checked-in slices

## The Mac Build Is Unavailable On My Intel Machine

The checked-in macOS slice is `arm64` only.

That means:

- Apple Silicon Macs are the intended path for native macOS validation
- Intel Macs are not supported by the current checked-in package artifacts

## The Simulator Build Complains About Deployment Target Or Platform Versions

The current `GemmaModelConstraintProvider` simulator slice has a minimum iOS simulator version of `26.2`.

If the simulator path is giving you trouble:

- use a recent simulator runtime
- or validate on a physical device instead

## The Mac Build Succeeds, But The App Fails To Launch

The sample app depends on dylibs that need to be discoverable from the app bundle at runtime.

If you customize the sample target and break launch on macOS, make sure the target still includes:

- `@executable_path/../Frameworks` in `LD_RUNPATH_SEARCH_PATHS`
- the packaged dylibs inside `Contents/Frameworks`

## Downloads Fail Or Stop Midway

Check the Xcode console first. The sample app logs:

- download start
- progress updates
- HTTP failures
- finalization errors
- runtime setup errors

That logging is one of the main reasons the example app is worth using before you build your own UI.

## The Model Files Are Very Large

That is expected.

The current example Gemma 4 models are multi-gigabyte downloads, so plan for:

- disk space
- time to download
- real-device testing when you care about practical latency

## The Rebuild Pipeline Fails Early

Make sure the machine has:

- `git`
- `git-lfs`
- `bazelisk`
- `xcodebuild`
- Xcode command line tools

Then rerun:

```bash
./scripts/buildall.sh
```
