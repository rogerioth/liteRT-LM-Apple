# Gemma 4 E4B GPU Performance Notes

This note captures the May 2026 iPhone comparison between this sample app and Google's AI Edge Gallery app for Gemma 4 E4B multimodal inference.

## Device

- Device: Rogerio's iPhone 17 Pro Max
- CoreDevice identifier: `CC1CADAF-F0B4-55B7-A69C-825ECB48E6C9`
- Hardware: `iPhone18,2`
- OS: iOS `26.4.2`
- Also tested on Rogerio's iPhone 16 Pro Max
- CoreDevice identifier: `70755C95-F229-5DA3-82B3-23B3156E3AD0`

## Current sample app behavior

The sample app's `LiteRTLMRuntimeOptions()` resolves to this profile for an E4B image prompt:

```text
backend=gpu
vision_backend=cpu                     # Gemma 4 default (see "Vision encoder correctness")
main_activation_data_type=FLOAT16
max_num_tokens=384
max_output_tokens=256
gpu_convert_weights_on_gpu=false       # E4B default
gpu_cache_compiled_shaders_only=true
benchmark=enabled
```

This is the normal sample-app path. There are no environment-variable overrides; per-call tuning happens through `LiteRTLMRuntimeOptions`. To run E4B with the all-GPU profile that this document originally tracked, mutate the struct before calling:

```swift
var options = LiteRTLMRuntimeOptions()
options.visionBackend = .gpu                       // override the Gemma 4 CPU default
options.visionActivationDataType = .float32        // see "Vision encoder correctness"
let result = try await runtime.generateResponse(
    modelURL: modelURL, cacheDirectory: cacheDirectory,
    inputs: inputs, options: options
)
```

Representative app log for a default Gemma 4 image prompt:

```text
Created engine settings backend=gpu vision_backend=cpu(default).
TIMING runtime phase=engine_settings_configure ... backend=gpu vision_backend=cpu max_num_tokens=384 benchmark=enabled.
Applied engine settings: max_num_images=1 max_num_tokens=384 main_activation_data_type=float16 ... .
Advanced bool settings: ... gpuConvertWeightsOnGpu=false(default) ... gpuCacheCompiledShadersOnly=true(default) ... .
Vision-GPU bool settings: ... cacheCompiledShadersOnly=unset ... .
```

(`cacheCompiledShadersOnly` resolves to `unset` here because vision is CPU; on the diagnostic vision-GPU path it resolves to `true(default)`.)

Observed smoke tests on iPhone 16 Pro Max:

- E4B + PNG with default options (`backend=gpu`, `vision_backend=cpu`): passes; the dog photo is correctly identified as "a white dog ... sleeping soundly".
- E2B + PNG with default options: passes; the dog photo is correctly identified as "a dog sleeping peacefully".
- E4B + PNG with `options.visionBackend = .gpu` (FP16 default): completes but produces "a crowd of people" — wrong.
- E2B + PNG with `options.visionBackend = .gpu` (FP16 default): completes but produces "a person's face and upper body" — wrong.
- E4B + PNG with `options.visionBackend = .gpu` and `options.visionActivationDataType = .float32`: warm-cache run produces "a white dog sleeping" — correct; cold-cache run is killed by iOS with signal 9.
- A no-override E4B smoke run on iPhone 16 Pro Max completes in roughly `14s` total with `conversation_send_and_parse` around `12s`.
- On iPhone 17 Pro Max, a cold cache using full serialized GPU artifacts was killed by iOS with signal 9 immediately after `message_json_encode` at about `3104 MB` process physical footprint. The runtime defaults set `gpuCacheCompiledShadersOnly = true` on both main and vision GPU executors and `gpuConvertWeightsOnGpu = false` for E4B specifically; with those, an iPhone 17 Pro Max fresh-cache smoke run completed at pre-`send_message` footprint around `2899 MB`.

## Vision encoder correctness

The local C wrapper forces vision GPU activations to FP16 to dodge a Metal texture-allocation ceiling. Upstream LiteRT-LM's vision executor defaults to FP32 "for backward compatibility with previous launched models", and the Gemma 4 family was launched expecting that default. Forcing FP16 produces semantically wrong embeddings on Metal — the dog test photo is described as "a crowd of people" (E4B) or "a person's face and upper body" (E2B). Forcing FP32 vision (`options.visionActivationDataType = .float32`) restores correctness but exceeds iOS cold-start memory limits when paired with the GPU main executor.

CPU vision sidesteps both failure modes: correct embeddings, no Metal memory pressure. That is why the sample app's default for Gemma 4 image prompts is `vision_backend=cpu`.

## Why the sample app can still be slower than Edge Gallery

The old minutes-long path was caused by CPU fallback in the sample app runtime defaults. That fallback is no longer the default. If a current build takes minutes, check the runtime log line that starts with `Created engine settings`; for a default Gemma 4 image prompt it should show `backend=gpu vision_backend=cpu(default)`.

The remaining performance gap versus Edge Gallery is from other factors:

- the public Hugging Face E4B artifact exposes different main signatures (`prefill_1024`, `prefill_128`, `decode`, `verify`) than the observed Edge Gallery artifact (`prefill_16`, `prefill_256`, `decode`, `verify`);
- the checked-in package does not currently bundle the optional Metal/WebGPU top-k sampler dylibs, so sampling falls back to CPU even when main and vision executors use GPU;
- the public artifact still has a larger eager GPU compilation and memory footprint than the observed Edge Gallery path.

Earlier attempts before the release-vision-resources fix showed:

- `backend=cpu vision_backend=gpu` with default XNNPack CPU kernels reaches prefill, then fails with XNNPack reshape errors.
- `backend=cpu vision_backend=gpu cpu_kernel_mode=builtin` completed but was slow because main prefill/decode ran on CPU.
- `backend=gpu vision_backend=gpu` with large token budgets failed with memory mapping / allocation issues on device.

## Google AI Edge Gallery comparison

Google AI Edge Gallery bundle:

```text
com.google.AIEdgeGallery
```

Observed Edge Gallery E4B model:

```text
Gemma-4-E4B-it
gemma4_4b_v09_obfus_fix_all_modalities_thinking.litertlm
https://dl.google.com/google-ai-edge-gallery/android/gemma4/20260325/gemma4_4b_v09_obfus_fix_all_modalities_thinking.litertlm
```

Edge Gallery's validated runtime settings show that it is not using the same execution path as this sample app:

```text
MainExecutorSettings: backend: GPU
activation_data_type: FLOAT32
max_tokens: 4000
max_num_images: 10
advanced_settings:
  gpu_madvise_original_shared_tensors: true
  convert_weights_on_gpu: true
  wait_for_weights_conversion_complete_in_benchmark: true
  optimize_shader_compilation: true
  share_constant_tensors: true
  sampler_handles_input: true
  allow_src_quantized_fc_conv_ops: true
  disable_delegate_clustering: true
VisionExecutorSettings:
  EncoderBackend: GPU
  AdapterBackend: CPU
ParallelFileSectionLoading: true
```

Edge Gallery also logs statically registered accelerators:

```text
Statically linked GPU accelerator registered.
CPU accelerator registered.
```

For the observed multimodal prompt, Edge Gallery resized the image and completed prefill quickly:

```text
Sending message: ... imageData(1383501 bytes), text("Describe this in detail")
Resize image from 2304x3072 to 672x912 which will result in 2394 patches to fit the max_num_patches: 2520 limit.
RunPrefillAsync status: OK
RunDecodeAsync
```

The timestamps in the console log put Edge Gallery prefill at roughly 2.1 seconds after image preprocessing started. This is consistent with Edge Gallery using the main GPU executor, not CPU built-in kernels.

## Main-GPU retests

Retests on the iPhone 16 Pro Max used the rebuilt local LiteRT-LM dylib and the public Hugging Face artifact:

```text
gemma-4-E4B-it.litertlm
size: 3654467584 bytes
sha256: f335f2bfd1b758dc6476db16c0f41854bd6237e2658d604cbe566bcefd00a7bc
main section signatures: decode, prefill_1024, prefill_128, verify
extra section: tf_lite_mtp_drafter, backend_constraint=cpu
```

This SHA-256 matches the current Hugging Face resolver `x-linked-etag` for
`litert-community/gemma-4-E4B-it-litert-lm` on May 2, 2026, so the local file is
not a stale pre-update artifact.

The Edge Gallery artifact is different:

```text
gemma4_4b_v09_obfus_fix_all_modalities_thinking.litertlm
main section signatures: decode, prefill_16, prefill_256, verify
no tf_lite_mtp_drafter section observed
```

Historical main-GPU outcomes before the release-vision-resources fix:

- `backend=gpu vision_backend=gpu max_tokens=4000 max_num_images=10`: failed during main GPU `CompiledModel::Create` with `Failed to allocate id<MTLTexture>`.
- After exposing the remaining upstream GPU diagnostics, the iPhone 16 Pro Max baseline still failed in the same phase. It initialized `decode` and `prefill_1024` from serialized GPU data, then failed allocating a Metal texture while preparing the `prefill_128` signature. This confirms the failure is in eager main-model GPU signature compilation, before image-specific vision inference.
- Running with a fresh isolated cache subdirectory produced the same failure, so stale serialized GPU programs are not the root cause.
- `gpu_convert_weights_on_gpu=false`: main GPU compilation progressed farther, through `prefill_128`, then failed allocating a Metal texture while preparing `verify`.
- `gpu_share_constant_tensors=false`: worse; the app was killed by signal 9 during the first main-GPU delegate setup.
- `gpu_external_tensor_mode=true`: failed like baseline at `prefill_128`.
- `gpu_cache_compiled_shaders_only=true`: changed the initialization path from serialized data to graph, but still failed at `prefill_128`.
- `main_activation_data_type=FLOAT16`: main GPU setup progressed far enough to reach the vision path. At `max_tokens=4000`, the per-layer embedder mmap failed and vision GPU crashed. At `max_tokens=512`, main and per-layer embedder initialized, then the vision encoder failed allocating Metal textures.
- `main_activation_data_type=FLOAT16 max_tokens=512 vision_backend=cpu`: the engine was created and image preprocessing reached `RunPrefillAsync`, then the CPU vision encoder failed in XNNPack reshape. This isolates the all-GPU remaining failure to vision encoder Metal allocation after the main model has already consumed memory.
- `prefill_batch_sizes=16,256`: setting was applied, but LiteRT logged `Too many prefill batch sizes=2 for magic numbers of prefill lengths=0`, kept `prefill_1024` and `prefill_128`, and failed the same way.
- `activation_data_type=FLOAT16`: main GPU compilation progressed, then the process crashed while bringing up the E4B vision path.
- `max_tokens=2048 max_num_images=1`: main GPU compiled, but the per-layer embedder mmap failed and the vision encoder failed to allocate Metal textures.
- `max_tokens=1024 max_num_images=1`: per-layer embedder mapped, but the vision encoder section failed to mmap.
- `max_tokens=512 max_num_images=1`: per-layer embedder and vision model mapping progressed farther, then the vision encoder crashed during GPU initialization.
- `main_activation_data_type=FLOAT16 max_tokens=512 max_num_images=1 vision_gpu_convert_weights_on_gpu=false`: still failed in the vision encoder Metal texture allocation path.
- `main_activation_data_type=FLOAT16 max_tokens=512 max_num_images=1 vision_gpu_cache_compiled_shaders_only=true`: changed the vision delegate path from serialized data to graph compilation, but still failed allocating Metal textures.
- `main_activation_data_type=FLOAT16 max_tokens=512 max_num_images=1 vision_gpu_share_constant_tensors=false`: reached vision delegate setup, then terminated with `std::bad_alloc`.
- `main_activation_data_type=FLOAT16 max_tokens=512 max_num_images=1 vision_gpu_madvise_original_shared_tensors=false`: still failed allocating Metal textures.
- `main_activation_data_type=FLOAT16 vision_activation_data_type=FLOAT16 max_tokens=512 max_num_images=1`: still failed allocating Metal textures.

These failures happened before prompt-size or image-size choices could matter. The later release-vision-resources fix changed the all-GPU outcome for smaller GPU token budgets, and the current sample default uses `main_activation_data_type=FLOAT16`, `max_num_tokens=384`, CPU-side main GPU weight conversion for E4B, and compiled-shaders-only cache mode for both GPU executors.

Two external signals are worth keeping with the local evidence:

- The public Hugging Face model card currently advertises iPhone 17 Pro GPU results for this same artifact (`1189` prefill tokens/sec, `25.1` decode tokens/sec, `3380` MB CPU/GPU memory), so Google likely has a runtime/configuration path that can make the public file work.
- `google-ai-edge/gallery#692` reports that the public Gallery repository still does not list Gemma 4 in the iOS allowlist and that public iOS LiteRT-LM integration fails before producing a response. The App Store listing also says version `1.0.3` fixed model-initialization crashes, but the corresponding public source path is not visible in the checked-out Gallery tree.

## Current conclusion

The performance gap is not primarily an image-size issue. Edge Gallery is fast because its E4B path uses:

- Main model on GPU.
- Vision encoder on GPU.
- Vision adapter on CPU.
- Parallel section loading.
- A different Google-hosted E4B model artifact than the sample app's Hugging Face artifact.

As of 2026-05-02, E4B can complete with main `gpu` and vision `gpu` on the iPhone 16 Pro Max. The sample app does **not** use that profile by default for Gemma 4 image prompts because the FP16 vision encoder produces semantically wrong embeddings on Metal (see "Vision encoder correctness" above). The default is GPU main + CPU vision; callers can opt into vision GPU by setting `LiteRTLMRuntimeOptions.visionBackend = .gpu` (and `visionActivationDataType = .float32` for correct semantics, with the cold-OOM caveat). The decisive native fix that made vision GPU possible at all was releasing the compiled vision executor resources after image encoding and before LLM prefill — without that, the process reached the first `prefill_128` per-layer embedding lookup and was killed by iOS.

This fixes correctness for all-GPU E4B on device when paired with FP32 vision activations, but it still does not make the public artifact match Edge Gallery's startup/perceived performance. Edge Gallery appears to use a different Google-hosted model artifact with different main signatures and no visible CPU MTP drafter path, while the public artifact still exposes `prefill_1024`, `prefill_128`, `decode`, and `verify`.

The release-vision-executor-after-encode behavior is always-on in the packaged dylib for Apple platforms when the main executor backend is GPU. There is no per-call switch.

## Next investigation path

To match Edge Gallery, the likely required work is one of:

1. Publish/use an E4B artifact exported like Edge Gallery's model, with smaller GPU-compatible main signatures such as `prefill_16` and `prefill_256`.
2. Add upstream LiteRT/LiteRT-LM support for compiling only the signatures that will actually be used, or for lazily compiling signatures instead of compiling the whole `tf_lite_prefill_decode` section in `CompiledModel::Create`.
3. Investigate whether a newer internal LiteRT GPU compiler/runtime has memory behavior that the public LiteRT-LM source does not yet have.
4. Test the upstream memory-reduction change `da1f1ceb` (`Reduce peak memory footprint by unmapping TFLite FlatBuffer for fully accelerated models`) from the LiteRT-LM remote branches. That change is not in the current local source baseline and directly targets peak memory after hardware compilation.
5. Fix the Metal FP16 vision encoder so it stops producing wrong Gemma 4 embeddings, or expose a Metal-friendly FP32 vision path that stays under the iOS cold-start memory ceiling. That would let the sample drop the CPU-vision default for Gemma 4.

The `LiteRTLMRuntimeOptions.prefillBatchSizes` field is exposed for models that do carry prefill-length magic numbers. It does not fix the public E4B artifact because that artifact exposes no prefill-length magic numbers for LiteRT to rewrite.

`LiteRTLMRuntimeOptions` exposes the full upstream tuning surface so future test runs can isolate LiteRT GPU behavior without rebuilding the dylib. The relevant per-call fields are:

```text
backend                         visionBackend                  audioBackend (not yet exposed)
maxNumTokens                    maxNumImages                   minLogLevel
benchmark                       cacheSubdirectory
activationDataType              mainActivationDataType         visionActivationDataType
audioActivationDataType         prefillChunkSize               prefillBatchSizes
parallelLoading                 cpuKernelMode                  gpuExternalTensorMode
gpuHintKernelBatchSize

advanced.clearKvCacheBeforePrefill
advanced.gpuMadviseOriginalSharedTensors
advanced.gpuConvertWeightsOnGpu
advanced.gpuWaitForWeightsConversionCompleteInBenchmark
advanced.gpuOptimizeShaderCompilation
advanced.gpuCacheCompiledShadersOnly
advanced.gpuShareConstantTensors
advanced.samplerHandlesInput
advanced.gpuAllowSrcQuantizedFcConvOps
advanced.gpuHintWaitingForCompletion
advanced.gpuContextLowPriority
advanced.gpuDisableDelegateClustering

visionGPU.madviseOriginalSharedTensors
visionGPU.convertWeightsOnGpu
visionGPU.cacheCompiledShadersOnly
visionGPU.shareConstantTensors
```

## Useful local log artifacts

These files were generated during the investigation and may exist only in the local worktree:

```text
.worktree/e4b-default-vision-gpu-img1500-max448.log
.worktree/e4b-default-vision-gpu-img1245.log
.worktree/e2b-default-vision-gpu-img1500-max448-after-fallback.log
.worktree/e4b-17pm-default-vision-gpu-img1500-max448.log
.worktree/edge-gallery-17pm-console.log
.worktree/e4b-16pm-main-gpu-vision-gpu-edge-settings.log
.worktree/e4b-16pm-main-gpu-vision-gpu-prefill16-256.log
.worktree/e4b-16pm-main-gpu-vision-gpu-max2048.log
.worktree/e4b-16pm-main-gpu-vision-gpu-max2048-img1.log
.worktree/e4b-16pm-main-gpu-vision-gpu-max1024-img1.log
.worktree/e4b-16pm-main-gpu-vision-gpu-max512-img1.log
.worktree/e4b-16pm-diag-baseline-gpu.log
.worktree/e4b-16pm-diag-baseline-fresh.log
.worktree/e4b-16pm-diag-convert-weights-off.log
.worktree/e4b-16pm-diag-share-constants-off.log
.worktree/e4b-16pm-diag-external-tensors-on.log
.worktree/e4b-16pm-diag-cache-compiled-shaders-only.log
.worktree/e4b-16pm-diag-main-fp16.log
.worktree/e4b-16pm-diag-main-fp16-img1.log
.worktree/e4b-16pm-diag-main-fp16-max512-img1.log
.worktree/e4b-16pm-diag-main-gpu-fp16-vision-cpu-max512.log
.worktree/e4b-16pm-diag-main-fp16-max512-img1-vision-convert-off.log
.worktree/e4b-16pm-diag-main-fp16-max512-img1-vision-cache-shaders-only.log
.worktree/e4b-16pm-diag-main-fp16-max512-img1-vision-share-off.log
.worktree/e4b-16pm-diag-main-fp16-max512-img1-vision-madvise-off.log
.worktree/e4b-16pm-diag-main-fp16-vision-fp16-max512-img1.log
.worktree/e4b-16pm-prefill-internal-trace.log
.worktree/e4b-16pm-release-vision-before-prefill.log
.worktree/e4b-16pm-release-vision-clean.log
.worktree/e4b-16pm-release-vision-clean-img1245.log
.worktree/e4b-16pm-release-vision-clean-heic.log
```
