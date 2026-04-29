# Multimodal Image Input — Design

**Date:** 2026-04-29
**Status:** Approved for implementation
**Repo:** `liteRT-LM-Apple`

## Context

`liteRT-LM-Apple` ships a Swift Package wrapping the upstream LiteRT-LM C API plus a SwiftUI sample app that runs Gemma 4 on-device. The sample currently exercises only the text-only Conversation path. The C API and the underlying runtime support multimodal input (text, image, audio), but neither the package nor the sample uses that surface today, and the pinned upstream revision is ~144 commits behind `main`.

Goal: take the sample app from text-only to a working text + image flow on every supported Apple platform, validated end-to-end on Mac Catalyst with a real photo and a real Gemma 4 E2B response. Do this on top of upstream HEAD, not the older pinned revision, so the project stays close to the current upstream surface.

## Scope

In scope:
- Bump pinned upstream LiteRT-LM revision to current `main` HEAD (`7d1923daaaa1e5143f77f0adb105188e53e8485e`).
- Refresh `patches/0001-export-ios-shared-engine-dylib.patch` so it applies and produces the same shared-dylib + max-num-images surface against the new tree.
- Rebuild and refresh both `LiteRTLMEngineCPU.xcframework` and `GemmaModelConstraintProvider.xcframework`, including iOS device, iOS simulator (arm64), Apple Silicon macOS, Apple Silicon Mac Catalyst (derived), and Apple Silicon visionOS device + simulator (derived).
- Refresh `Sources/LiteRTLMApple/include/engine.h` from the new upstream header.
- Update `LiteRTLMRuntime.swift` for the new C API:
  - new builder-pattern `litert_lm_conversation_config_create()` plus setters, replacing the previous 6-argument call;
  - apply `litert_lm_engine_settings_set_max_num_images(settings, 1)` on the vision-capable models;
  - adapt to the new `litert_lm_set_min_log_level` scale (was `0=INFO/1=WARNING/2=ERROR/3=FATAL`, now `0=VERBOSE/1=DEBUG/2=INFO/3=WARNING/4=ERROR/5=FATAL/1000=SILENT`);
  - extend the user message JSON builder to optionally include an image content part of shape `{"type":"image","blob":"<base64>"}` when an image is attached;
  - keep existing renamed primitives (`LiteRtLmInputData`, `LiteRtLmSamplerType`, etc.) consumable from Swift through the standard module shim.
- Sample-app UI changes (option A approved during brainstorming):
  - Inline paperclip / attach button in the existing Prompt card.
  - Selected image shown as a 64-pt thumbnail above the prompt text editor.
  - `xmark.circle` control to remove the attached image.
  - Cross-platform `PhotosPicker` (SwiftUI), with `PHPickerFilter.images`.
  - Optional one-tap "What is this?" prompt chip when an image is attached.
- `InferenceViewModel` extended with `selectedImageData: Data?` and the lifecycle wiring (clear on model switch, clear after a successful run).
- A small Swift assertion (or unit test if a test target already exists) covering the message-JSON builder so we don't silently regress the wire format.
- Documentation updates to reflect: new pinned revision, new C-API surface, image attach flow, supported platforms.

Out of scope:
- Audio input (still possible via the same content-part pattern; not exercised in this change).
- Streaming responses (`litert_lm_conversation_send_message_stream`); current sample uses blocking `send_message` and that is preserved.
- Tool-calling, custom samplers, custom system prompts beyond the existing one.
- A high-level Swift façade over the C API; this remains the thin wrapper the project advertises.

## Architecture

### Package side
1. `scripts/subscripts/common.sh` updates `UPSTREAM_BASE_REVISION_DEFAULT` to `7d1923daaaa1e5143f77f0adb105188e53e8485e`.
2. `patches/0001-export-ios-shared-engine-dylib.patch` is regenerated from the new upstream tree. It still:
   - adds a `cc_binary engine_cpu_shared` target in `c/BUILD` with `linkshared = 1`, `linkstatic = 1`, `install_name=@rpath/libLiteRTLMEngineCPU.dylib` for iOS / macOS targets, depending on `:engine_cpu`;
   - adds `litert_lm_engine_settings_set_max_num_images(LiteRtLmEngineSettings*, int)` to `c/engine.h` and a matching definition in `c/engine.cc` that calls `settings->settings->GetMutableMainExecutorSettings().SetMaxNumImages(...)`. The C++ runtime support already exists upstream (`runtime/executor/llm_executor_settings.h`), so this is a pure surface addition.
3. `scripts/subscripts/build_xcframeworks.sh` continues to run `bazelisk` for iOS device, iOS simulator arm64, and macOS arm64, then derive Catalyst, visionOS device, and visionOS simulator slices via `xcrun vtool -set-build-version`. Two XCFrameworks are emitted as today.
4. `Sources/LiteRTLMApple/include/engine.h` is overwritten from the new `c/engine.h` exactly as today.

### Runtime side (`LiteRTLMRuntime.swift`)
A single new entry point keeps backwards compatibility with the existing call site:

```swift
struct InferenceInputs: Sendable {
    let prompt: String
    let imageData: Data?
}

protocol LiteRTLMRuntimeProtocol: Sendable {
    func generateResponse(
        modelURL: URL,
        cacheDirectory: URL,
        inputs: InferenceInputs
    ) async throws -> InferenceResult
}
```

The legacy `prompt:` overload is removed because the project ships only with this internal call site; we don't owe a deprecation window to external consumers of the sample.

Inside `generateResponseSynchronously`:
- Always call `litert_lm_engine_settings_set_max_num_images(settings, 1)` — Gemma 4 E2B/E4B require it for vision, and it is harmless for text-only.
- `litert_lm_set_min_log_level(3)` (WARNING) replaces the prior `1` (which was WARNING under the old scale and is now DEBUG).
- Conversation config built via the new builder pattern:
  ```swift
  let config = litert_lm_conversation_config_create()
  litert_lm_conversation_config_set_session_config(config, sessionConfig)
  litert_lm_conversation_config_set_system_message(config, systemMessageJSON)
  // tools, messages, extra_context left unset
  ```
- Message JSON construction:
  - If `imageData == nil`, content is `[{"type":"text","text":...}]` exactly as today.
  - Otherwise content is `[{"type":"image","blob":"<base64>"},{"type":"text","text":...}]` (image first, text last — gallery convention).
  - Image bytes are base64-encoded as-is. Caller is expected to pass PNG or JPEG bytes (any stb-decodable format works); the engine handles decode, bicubic resize to the model's baked dim (768×768 for Gemma 4 E2B/E4B), and `[0, 1]` normalization.

### View-model side (`InferenceViewModel.swift`)
- Adds `@Published private(set) var selectedImageData: Data?`.
- Adds `attachImage(_:)` and `clearAttachedImage()` API surface.
- `selectModel(_:)` and `runInference()` reset `selectedImageData` after a successful inference (so the user has to re-attach for the next run; this matches the gallery's per-turn attach UX).
- `runInference()` builds an `InferenceInputs` from `prompt` + `selectedImageData` and forwards it.

### View side (`ContentView.swift`)
- Prompt card gains a small thumbnail row above the `TextEditor`:
  - Visible only when `viewModel.selectedImageData != nil`.
  - Renders the image at 64×64 with rounded corners.
  - Includes an `xmark.circle.fill` button to clear the attachment.
- Above the Run button, a row of two compact buttons:
  - `paperclip` "Attach Image" — opens a `PhotosPicker(filter: .images)`.
  - "What is this?" chip — convenience that sets the prompt text and is hidden if no image is attached.
- `PhotosPicker` selection is loaded as `Data` via `PhotosPickerItem.loadTransferable(type: Data.self)`, then **always re-encoded to JPEG via ImageIO** before storing in the view model. iOS Photos commonly returns HEIC, and the engine's stb_image decoder does not support HEIC — re-encoding to JPEG is the simplest cross-platform guarantee that whatever bytes the engine receives are stb-decodable, and JPEG keeps payload size small. The encode pipeline uses `CGImageSourceCreateWithData` → `CGImageDestinationCreateWithData(..., "public.jpeg", ...)` with `kCGImageDestinationLossyCompressionQuality` of `0.9`, which avoids UIKit/AppKit branching and works on iOS, iPadOS, Mac Catalyst, native macOS, and visionOS uniformly.
- Layout follows the existing `Card` styling — no new visual primitives.

### Cross-platform notes
- `PhotosPicker` is available on iOS 16+, iPadOS 16+, Mac Catalyst 16+, macOS 13+, visionOS 1+. The sample's deployment targets (iOS 26.2 / macOS 14 / visionOS 1.0) all satisfy this.
- On macOS native, `PhotosPicker` opens the user's Photos library. For Catalyst the same path is used. Since the test image we want to validate against lives in `~/Downloads/IMG_1500.jpg`, we keep the picker accessible but do not require Photos: a Photos-library entry for the test image is already present on the dev machine, so we add the file to the user's Photos library before the test if needed. (Alternative: switch to `.fileImporter` if Photos access turns out to be friction during validation.)

## Error handling

- Image transferable load failure → set `errorMessage`, leave `selectedImageData` unchanged.
- Inference failure paths existing today are preserved.
- Engine returns no candidates / empty content → existing `LiteRTLMRuntimeError` path.
- `litert_lm_conversation_config_create()` returning `NULL` → existing error path; the API is exception-free, so we still gate every C-pointer return.
- We do not catch and swallow upstream issue [#1933](https://github.com/google-ai-edge/LiteRT-LM/issues/1933) (E4B vision prefill crash on iOS) — if the model crashes, it crashes loudly. We document the workaround (use E2B for image testing) in `docs/troubleshooting.md`.

## Testing

- **Build matrix.** Verify clean builds for: iOS device, iOS simulator (arm64), macOS native, Mac Catalyst, visionOS device, visionOS simulator. The Catalyst slice is the primary on-device validation target because it is the user's stated focus.
- **Wire-format unit assertion.** A small `#if DEBUG` self-check (or XCTest if a test target exists) verifies that `makeUserMessageJSON(prompt:imageData:)` emits the expected JSON shape for both text-only and text+image cases, including image-first ordering.
- **End-to-end Catalyst test.** Open the sample app on Catalyst, ensure Gemma 4 E2B is downloaded (or download it once during the test), attach `~/Downloads/IMG_1500.jpg`, set the prompt to "What is this?", run inference, and verify a non-empty response that is plausibly about the image's contents. Validation done via computer-use screenshots.
- **Regression check.** Existing text-only flow continues to work without an attached image.
- **Smoke check on the other slices** is best-effort given device availability: at minimum, build and launch on iOS simulator (arm64), confirm app boots; visionOS / native macOS verified via `My Mac` and `Apple Vision Pro` simulator if accessible.

## Risks and mitigations

- **Long bazelisk rebuild from cold.** First-time HEAD build can take 30–60 minutes on the dev machine. Mitigation: kick off `scripts/buildall.sh` early and parallel the Swift-side updates.
- **Patch reapplication friction.** `c/engine.cc` saw heavy refactors (rename + builder pattern). Mitigation: regenerate the patch from a hand-authored copy rather than `git apply`-ing the old one. If the C wrapper grows fragile to write inline, fall back to a tiny `.cc` shim file added by the patch alongside `engine.cc`.
- **Upstream issue #1933 (E4B image prefill crash on iOS).** Mitigation: validate with E2B first; document E4B as text-recommended-only if reproduction confirms the crash on Apple Silicon.
- **Mac Catalyst Photos access.** If `PhotosPicker` is awkward in our Catalyst run, we swap to `.fileImporter`. The change is local to one view and one binding.
- **`max_num_images` API surface drift upstream.** If upstream lands a different name later, we re-export ours under the same name to keep Swift call sites stable; the C++ side is already settled.

## Open follow-ups (out of scope)

- Streaming responses via `litert_lm_conversation_send_message_stream` for a more chat-like UX.
- Audio attachment.
- Multiple-image prompts (the engine supports it via `set_max_num_images(n)`; UI work needed).
- Sample-app side benchmarking specifically for vision prefill.

## References

- Upstream LiteRT-LM repository: https://github.com/google-ai-edge/LiteRT-LM
- Upstream HEAD pinned target: `7d1923daaaa1e5143f77f0adb105188e53e8485e`
- Reference implementation for content-part shape: `kotlin/java/com/google/ai/edge/litertlm/Message.kt:170-176`
- Reference Android image flow: gallery `LlmChatModelHelper.kt:271-281`
- Image preprocessing (engine-side): `runtime/components/preprocessor/stb_image_preprocessor.cc`
- C-API rename commit: `c98468bc24b6d3897df9008a10772bcfc16f2939`
- Conversation builder rewrite landed alongside: `litert_lm_conversation_config_create` zero-arg form
