# Gemma 4 E4B GPU Performance Notes

This note captures the May 2026 iPhone 17 Pro Max comparison between this sample app and Google's AI Edge Gallery app for Gemma 4 E4B multimodal inference.

## Device

- Device: Rogerio's iPhone 17 Pro Max
- CoreDevice identifier: `CC1CADAF-F0B4-55B7-A69C-825ECB48E6C9`
- Hardware: `iPhone18,2`
- OS: iOS `26.4.2`

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

## Current conclusion

The performance gap is not primarily an image-size issue. Edge Gallery is fast because its E4B path uses:

- Main model on GPU.
- Vision encoder on GPU.
- Vision adapter on CPU.
- Parallel section loading.
- Several GPU advanced settings that are not currently exposed/configured by this package.
- A different Google-hosted E4B model artifact name than the sample app's Hugging Face artifact.

The current sample app fix proves `vision_backend=gpu` can work correctly, but it does not match Edge Gallery performance because it deliberately avoids the main GPU executor.

## Next investigation path

To match Edge Gallery, investigate these in order:

1. Test the exact Edge Gallery E4B artifact in this sample app:
   `gemma4_4b_v09_obfus_fix_all_modalities_thinking.litertlm`.
2. Re-test `backend=gpu vision_backend=gpu` using that artifact.
3. Compare LiteRT-LM engine settings with Edge Gallery and expose missing C API knobs if needed:
   `convert_weights_on_gpu`, `share_constant_tensors`, `optimize_shader_compilation`, `disable_delegate_clustering`, `sampler_handles_input`, `allow_src_quantized_fc_conv_ops`, and parallel section loading.
4. Check whether Edge Gallery is using a newer or different LiteRT-LM revision than the pinned Google source used by this repo's patch/build flow.
5. Check whether the GPU accelerator linkage matters for main-GPU E4B:
   Edge Gallery logs static GPU accelerator registration, while this repo currently packages the Metal accelerator for dynamic loading.

## Useful local log artifacts

These files were generated during the investigation and may exist only in the local worktree:

```text
.worktree/e4b-default-vision-gpu-img1500-max448.log
.worktree/e4b-default-vision-gpu-img1245.log
.worktree/e2b-default-vision-gpu-img1500-max448-after-fallback.log
.worktree/e4b-17pm-default-vision-gpu-img1500-max448.log
.worktree/edge-gallery-17pm-console.log
```
