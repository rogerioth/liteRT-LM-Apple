# Troubleshooting

This project is intentionally simple to consume, but a few issues show up repeatedly when developers evaluate local Apple-device inference.

## The Package Resolves, But The Sample App Does Not Run In My Simulator

The checked-in iOS and visionOS simulator artifacts are `arm64` only.

That means:

- Apple Silicon simulator environments are the intended path
- Intel simulator environments are not supported by the current checked-in slices

## The Mac Build Is Unavailable On My Intel Machine

The checked-in macOS slice is `arm64` only.

That means:

- Apple Silicon Macs are the intended path for native macOS validation
- Intel Macs are not supported by the current checked-in package artifacts

## The Mac Catalyst Build Is Unavailable On My Intel Machine

The checked-in Mac Catalyst slice is also `arm64` only.

That means:

- Apple Silicon Macs are the intended path for Catalyst validation
- Intel Macs are not supported by the current checked-in Catalyst artifact

## The Vision Pro Build Is Unavailable On My Intel Machine

The checked-in visionOS device and simulator slices are also `arm64` only.

That means:

- Apple Silicon Macs are the intended path for Vision Pro simulator validation
- Intel Macs are not supported by the current checked-in visionOS artifacts

## The Simulator Build Complains About Deployment Target Or Platform Versions

The current `GemmaModelConstraintProvider` simulator slice has a minimum iOS simulator version of `26.2`.

If the simulator path is giving you trouble:

- use a recent simulator runtime
- or validate on a physical device instead

## The Catalyst Build Complains About Deployment Target Or Platform Versions

The current Mac Catalyst slice is derived from the Apple Silicon iOS simulator dylib.

That means:

- it currently inherits the iOS-family deployment floor from the packaged simulator binary
- recent Mac Catalyst runtimes on current Xcode releases are the intended validation path
- native macOS is the safer path if you need the lowest-friction Mac validation today

## The visionOS Build Complains About Deployment Target Or Platform Versions

The current visionOS slices are derived from the packaged iOS device and iOS simulator dylibs.

That means:

- the package currently advertises a `visionOS 1.0` floor for the packaged slices
- recent Apple Vision Pro runtimes on current Xcode releases are the intended validation path
- if the simulator path gives you trouble, try a generic `visionOS` build first to verify the device slice resolves

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

## Multimodal

- **App crashes (`EXC_BAD_ACCESS`) inside `SessionBasic::ProcessAndCombineContents` the first time you send an image**: `vision_backend_str` was passed as `NULL` to `litert_lm_engine_settings_create`, so the engine never instantiated `vision_executor_`. Pass `"cpu"` (or `"gpu"`) instead.
- **`DYNAMIC_UPDATE_SLICE` shape mismatch / `Failed to allocate tensors` during prefill of an image prompt**: usually one of two root causes:
  1. `litert_lm_engine_settings_set_max_num_images` was not called, or was called with a value `< 1`. Vision-capable Gemma 4 models require at least `1`.
  2. `litert_lm_engine_settings_set_max_num_tokens` and/or `litert_lm_engine_settings_set_prefill_chunk_size` were set to values that conflict with the model's baked vision-prefill graph or exceed the device memory budget. The sample app uses `max_num_tokens=384` for its GPU profile and leaves `prefill_chunk_size` unset.
- "Model says it cannot see images" or returns generic text when an image is attached: same as the `max_num_images = 0` case above.
- HEIC photos from the iOS Photos library: re-encode to JPEG (or PNG) before sending. The sample app does this via `ImageDataNormalizer`. The engine's stb_image-based decoder does not support HEIC.
- Gemma 4 E4B image inference takes minutes: check the runtime log line that starts with `Created engine settings`. Current sample app builds should show `backend=gpu backend_source=default vision_backend=gpu vision_backend_source=default` for an image prompt. If you see `backend=cpu`, you are on an older build or intentionally using a DEBUG override.
- Gemma 4 E4B is killed by iOS with signal 9 on the first image prompt after clearing the GPU cache: the cold-cache Metal serialization and main GPU weight-conversion paths can exceed the device memory high-water mark before the app reaches image resize or the release-before-prefill hook. Current sample app defaults set `kLiteRtLmAdvancedCacheCompiledShadersOnly` on both the main and vision GPU executors and set main `kLiteRtLmAdvancedConvertWeightsOnGpu=false` for E4B. If you override `LITERT_LM_GPU_CACHE_COMPILED_SHADERS_ONLY=false`, `LITERT_LM_VISION_GPU_CACHE_COMPILED_SHADERS_ONLY=false`, or `LITERT_LM_GPU_CONVERT_WEIGHTS_ON_GPU=true`, expect the older high-memory behavior.
- Gemma 4 E4B crashes during all-GPU vision prefill: current packaged binaries include a local LiteRT-LM patch that releases compiled vision executor resources after image encoding and before LLM prefill. If you disable that path with `LITERT_LM_RELEASE_VISION_EXECUTOR_AFTER_ENCODE=0`, the process can hit the older memory failure.
- `GPU sampler unavailable. Falling back to CPU sampling.`: this warning is currently expected with the checked-in package because the optional Metal/WebGPU top-k sampler dylibs are not bundled. Main and vision executors can still run on GPU; only token sampling falls back.
