You are working in /Users/rogeriohirooka/git/liteRT-LM-Apple, the Apple wrapper/source repo used by Lirum AI’s LiteRT-LM integration.

Goal: investigate and, if feasible, fix the LiteRT-LM GPU sampler fallback on iOS.

Context:
- In the Lirum AI iOS app, Gemma 4 E4B image + follow-up regression now passes, but every generation logs:
  "GPU sampler unavailable. Falling back to CPU sampling."
- The runtime attempts to load:
  - libLiteRtTopKMetalSampler.dylib
  - libLiteRtTopKWebGpuSampler.dylib
- They are not present in the app/framework search paths, so token sampling falls back to CPU.
- Local docs already say this is expected with the checked-in package:
  /Users/rogeriohirooka/git/liteRT-LM-Apple/docs/troubleshooting.md
  /Users/rogeriohirooka/git/liteRT-LM-Apple/docs/e4b-gpu-performance-notes.md
- Consequence: likely latency/CPU/battery overhead during decoding, especially long outputs. It is not believed to be the cause of the image follow-up crash.

Tasks:
1. Inspect the LiteRT-LM Apple source/sample and identify how GPU sampler dylibs are supposed to be provided, built, bundled, signed, and loaded on iOS.
2. Check current upstream LiteRT-LM status for iOS sampler prebuilts/targets. Be careful: verify any found dylib with `file`, `lipo -info`, and `otool -l`; do not assume a macOS dylib is valid for iOS arm64.
3. Determine whether we can fix this in liteRT-LM-Apple by:
   - bundling a valid iOS arm64 `libLiteRtTopKMetalSampler.dylib`,
   - wrapping it as an Apple framework,
   - patching the load path used by LiteRT-LM,
   - building the sampler from source,
   - or updating docs/logging if upstream cannot currently support it.
4. Make the sample app exercise the same path. The sample should either:
   - successfully use GPU sampling with no fallback warning, or
   - clearly log why CPU sampling is still expected.
5. Benchmark/verify on the connected iPhone if possible. Preferred device:
   id=00008140-00067C422093C01C
6. After fixing/sample changes, re-run or provide instructions for validating from Lirum AI:
   /Users/rogeriohirooka/git/lirum-ai-ios
   Focused regression:
   xcodebuild test -project 'Lirum AI.xcodeproj' -scheme 'Lirum AI' -destination 'id=00008140-00067C422093C01C' -parallel-testing-enabled NO -only-testing:'Lirum AITests/LiteRTLMImageInferenceTests'

Useful evidence:
- Lirum logs show `dlopen(libLiteRtTopKMetalSampler.dylib)` searching app Frameworks, LRE.framework, PackageFrameworks, and app root, then failing with “no such file”.
- `samplerHandlesInput` exists as an advanced option but was unset in passing runs; do not assume it fixes missing dylibs without proving it.
- Current stable Lirum runtime uses GPU main executor and CPU vision executor for Gemma 4 image prompts. Do not regress this; GPU vision produced incorrect embeddings for Gemma 4 in previous testing.

Expected deliverable:
- A clear root-cause summary.
- Any source/sample/package changes needed.
- Exact verification commands and results.
- Whether this is fixed locally, blocked by upstream, or needs a LiteRT-LM upstream patch.
- If creating commits, use simple conventional commits and do not add any AI co-author trailers.

- Also update this with the google's official implementation upstream...
