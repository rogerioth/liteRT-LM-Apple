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

The sample app currently runs E4B as:

```text
backend=cpu vision_backend=gpu
cpu_kernel_mode=builtin
```

This is a correctness workaround, not a performance-equivalent configuration. It keeps the vision encoder on GPU, but the main language model prefill/decode path runs on LiteRT built-in CPU kernels. That avoids the E4B + vision-GPU XNNPack reshape failure, but it makes inference take minutes.

Representative app log:

```text
Created engine settings backend=cpu vision_backend=gpu.
Applied engine settings: max_num_images=1 activation_data_type=default max_num_tokens=default prefill_chunk_size=default cpu_kernel_mode=builtin parallel_loading=default benchmark=disabled.
```

Observed successful smoke tests:

- E4B + JPG on iPhone 16 Pro Max: passed with `vision_backend=gpu`, `cpu_kernel_mode=builtin`.
- E4B + PNG on iPhone 16 Pro Max: passed with `vision_backend=gpu`, `cpu_kernel_mode=builtin`.
- E2B + JPG regression: passed with `vision_backend=gpu`, `cpu_kernel_mode=default`.

## Why the sample app is slow

The slow path is expected from the current workaround. The model no longer crashes, but the main executor is CPU-only and uses built-in kernels, which are much slower than the GPU executor.

Earlier attempts showed:

- `backend=cpu vision_backend=gpu` with default XNNPack CPU kernels reaches prefill, then fails with XNNPack reshape errors.
- `backend=gpu vision_backend=gpu` with the current sample app/runtime/model path failed with memory mapping / allocation issues on device.
- The current fallback changes only E4B + main CPU + vision GPU to `cpu_kernel_mode=builtin` so the path is correct but slow.

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

Observed main-GPU outcomes:

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

These failures happen before prompt-size or image-size choices can matter. The public artifact's all-GPU memory footprint is too high for this runtime/device combination even when the runtime settings are made smaller than Edge Gallery's.

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

As of 2026-05-02, E4B can complete with both `LITERT_LM_BACKEND=gpu` and `LITERT_LM_VISION_BACKEND=gpu` on the iPhone 16 Pro Max. The decisive fix was to release the compiled vision executor resources after image encoding and before LLM prefill. Before that release, the process reached the first `prefill_128` per-layer embedding lookup and was killed by iOS. After the release, the same public Hugging Face E4B artifact completes all three prefill chunks.

This fixes correctness for all-GPU E4B on device, but it still does not make the public artifact match Edge Gallery's startup/perceived performance. Edge Gallery appears to use a different Google-hosted model artifact with different main signatures and no visible CPU MTP drafter path, while the public artifact still exposes `prefill_1024`, `prefill_128`, `decode`, and `verify`.

The new runtime switch is:

```text
LITERT_LM_RELEASE_VISION_EXECUTOR_AFTER_ENCODE
```

On Apple platforms it defaults to enabled when the main executor backend is GPU. Set it to `0`, `false`, `no`, or `off` to disable for diagnostics. Set it to `1`, `true`, `yes`, or `on` to force the release.

## Next investigation path

To match Edge Gallery, the likely required work is one of:

1. Publish/use an E4B artifact exported like Edge Gallery's model, with smaller GPU-compatible main signatures such as `prefill_16` and `prefill_256`.
2. Add upstream LiteRT/LiteRT-LM support for compiling only the signatures that will actually be used, or for lazily compiling signatures instead of compiling the whole `tf_lite_prefill_decode` section in `CompiledModel::Create`.
3. Investigate whether a newer internal LiteRT GPU compiler/runtime has memory behavior that the public LiteRT-LM source does not yet have.
4. Test the upstream memory-reduction change `da1f1ceb` (`Reduce peak memory footprint by unmapping TFLite FlatBuffer for fully accelerated models`) from the LiteRT-LM remote branches. That change is not in the current local source baseline and directly targets peak memory after hardware compilation.

The local package now exposes `LITERT_LM_PREFILL_BATCH_SIZES` for diagnostics and for models that do carry prefill-length magic numbers. It does not fix this public E4B artifact because that artifact exposes no prefill-length magic numbers for LiteRT to rewrite.

The local package also exposes these diagnostic switches so future test runs can isolate upstream LiteRT GPU behavior without rebuilding:

```text
LITERT_LM_CACHE_SUBDIRECTORY
LITERT_LM_MAIN_ACTIVATION_DATA_TYPE
LITERT_LM_VISION_ACTIVATION_DATA_TYPE
LITERT_LM_AUDIO_ACTIVATION_DATA_TYPE
LITERT_LM_GPU_EXTERNAL_TENSOR_MODE
LITERT_LM_GPU_HINT_KERNEL_BATCH_SIZE
LITERT_LM_CLEAR_KV_CACHE_BEFORE_PREFILL
LITERT_LM_GPU_MADVISE_ORIGINAL_SHARED_TENSORS
LITERT_LM_GPU_CONVERT_WEIGHTS_ON_GPU
LITERT_LM_GPU_WAIT_FOR_WEIGHTS_CONVERSION_COMPLETE_IN_BENCHMARK
LITERT_LM_GPU_OPTIMIZE_SHADER_COMPILATION
LITERT_LM_GPU_CACHE_COMPILED_SHADERS_ONLY
LITERT_LM_GPU_SHARE_CONSTANT_TENSORS
LITERT_LM_SAMPLER_HANDLES_INPUT
LITERT_LM_GPU_ALLOW_SRC_QUANTIZED_FC_CONV_OPS
LITERT_LM_GPU_HINT_WAITING_FOR_COMPLETION
LITERT_LM_GPU_CONTEXT_LOW_PRIORITY
LITERT_LM_GPU_DISABLE_DELEGATE_CLUSTERING
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
