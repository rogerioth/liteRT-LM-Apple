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
main section signatures: decode, prefill_1024, prefill_128, verify
extra section: tf_lite_mtp_drafter, backend_constraint=cpu
```

The Edge Gallery artifact is different:

```text
gemma4_4b_v09_obfus_fix_all_modalities_thinking.litertlm
main section signatures: decode, prefill_16, prefill_256, verify
no tf_lite_mtp_drafter section observed
```

Observed main-GPU outcomes:

- `backend=gpu vision_backend=gpu max_tokens=4000 max_num_images=10`: failed during main GPU `CompiledModel::Create` with `Failed to allocate id<MTLTexture>`.
- `prefill_batch_sizes=16,256`: setting was applied, but LiteRT logged `Too many prefill batch sizes=2 for magic numbers of prefill lengths=0`, kept `prefill_1024` and `prefill_128`, and failed the same way.
- `activation_data_type=FLOAT16`: main GPU compilation progressed, then the process crashed while bringing up the E4B vision path.
- `max_tokens=2048 max_num_images=1`: main GPU compiled, but the per-layer embedder mmap failed and the vision encoder failed to allocate Metal textures.
- `max_tokens=1024 max_num_images=1`: per-layer embedder mapped, but the vision encoder section failed to mmap.
- `max_tokens=512 max_num_images=1`: per-layer embedder and vision model mapping progressed farther, then the vision encoder crashed during GPU initialization.

These failures happen before prompt-size or image-size choices can matter. The public artifact's all-GPU memory footprint is too high for this runtime/device combination even when the runtime settings are made smaller than Edge Gallery's.

## Current conclusion

The performance gap is not primarily an image-size issue. Edge Gallery is fast because its E4B path uses:

- Main model on GPU.
- Vision encoder on GPU.
- Vision adapter on CPU.
- Parallel section loading.
- A different Google-hosted E4B model artifact than the sample app's Hugging Face artifact.

The current sample app fix proves `vision_backend=gpu` can work correctly, but it does not match Edge Gallery performance because it deliberately avoids the main GPU executor. The all-GPU retests show that exposing more app-level settings is not sufficient for the public E4B artifact: the artifact's main signatures and memory behavior differ from the Edge Gallery artifact.

## Next investigation path

To match Edge Gallery, the likely required work is one of:

1. Publish/use an E4B artifact exported like Edge Gallery's model, with smaller GPU-compatible main signatures such as `prefill_16` and `prefill_256`.
2. Add upstream LiteRT/LiteRT-LM support for compiling only the signatures that will actually be used, or for lazily compiling signatures instead of compiling the whole `tf_lite_prefill_decode` section in `CompiledModel::Create`.
3. Investigate whether a newer internal LiteRT GPU compiler/runtime has memory behavior that the public LiteRT-LM source does not yet have.

The local package now exposes `LITERT_LM_PREFILL_BATCH_SIZES` for diagnostics and for models that do carry prefill-length magic numbers. It does not fix this public E4B artifact because that artifact exposes no prefill-length magic numbers for LiteRT to rewrite.

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
```
