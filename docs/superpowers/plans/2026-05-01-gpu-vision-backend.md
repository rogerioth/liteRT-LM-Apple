# GPU Vision Backend Implementation Plan

> Historical implementation note: this plan records the GPU packaging work as it was designed in May 2026 and is not the current API reference. For current method names, parameters, sample defaults, and troubleshooting guidance, use `README.md`, `docs/integration-guide.md`, `docs/sample-app.md`, and `docs/troubleshooting.md`.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship one LiteRT-LM Apple engine binary that keeps CPU execution working and can also register the GPU/Metal vision backend on iOS.

**Architecture:** Keep the SwiftPM public surface stable while changing the native artifact source from the upstream CPU-only shared target to a GPU-capable shared target that depends on `:engine`. Add a shell regression test that fails when packaging drifts back to `engine_cpu_shared`.

**Tech Stack:** Bash packaging scripts, Bazel/Bazelisk, Xcode XCFramework tooling, LiteRT-LM C API, Swift sample smoke runner.

---

### Task 1: Script Regression Test

**Files:**
- Create: `scripts/tests/test_gpu_engine_packaging.sh`

- [ ] **Step 1: Write the failing test**

Create a shell test that runs `scripts/subscripts/build_xcframeworks.sh` with fake `bazelisk`, `xcrun`, `xcodebuild`, and `file` commands, then asserts the script builds `//c:engine_shared` and never builds `//c:engine_cpu_shared`.

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash scripts/tests/test_gpu_engine_packaging.sh`

Expected before implementation: FAIL because the script currently invokes `//c:engine_cpu_shared`.

- [ ] **Step 3: Commit the failing test**

Run: `git add scripts/tests/test_gpu_engine_packaging.sh && git commit -m "test: cover GPU-capable engine packaging"`

### Task 2: GPU-Capable Shared Target

**Files:**
- Modify: `patches/0001-export-ios-shared-engine-dylib.patch`
- Modify: `scripts/subscripts/build_xcframeworks.sh`

- [ ] **Step 1: Update the upstream patch**

Change the added Bazel shared target from `engine_cpu_shared` depending on `:engine_cpu` to `engine_shared` depending on `:engine`, preserving the packaged install name for SwiftPM compatibility.

- [ ] **Step 2: Update the packaging script**

Change Bazel build labels and generated dylib input paths from `engine_cpu_shared` / `libengine_cpu_shared.dylib` to `engine_shared` / `libengine_shared.dylib`.

- [ ] **Step 3: Run the script regression test**

Run: `bash scripts/tests/test_gpu_engine_packaging.sh`

Expected after implementation: PASS.

- [ ] **Step 4: Commit script and patch changes**

Run: `git add patches/0001-export-ios-shared-engine-dylib.patch scripts/subscripts/build_xcframeworks.sh && git commit -m "build: package GPU-capable LiteRT engine"`

### Task 3: Artifact Build And Device Verification

**Files:**
- Modify: `Artifacts/LiteRTLMEngineCPU.xcframework/**`
- Modify: `Sources/LiteRTLMApple/include/engine.h`

- [ ] **Step 1: Rebuild artifacts**

Run: `./scripts/buildall.sh`

If disk space runs out, clear DerivedData and Bazel caches, then rerun.

- [ ] **Step 2: Inspect the iOS device dylib**

Run: `otool -L Artifacts/LiteRTLMEngineCPU.xcframework/ios-arm64/libLiteRTLMEngineCPU.dylib` and `nm -m ... | rg "Gpu|Accelerator|Metal"`.

- [ ] **Step 3: Install and smoke-test on the connected iPhone**

Run the sample app smoke runner for E2B CPU, E4B CPU, and E4B with `LITERT_LM_VISION_BACKEND=gpu`, using several images staged in the app data container.

- [ ] **Step 4: Commit rebuilt artifacts if verification improves behavior**

Run: `git add Artifacts Sources/LiteRTLMApple/include/engine.h && git commit -m "build: refresh LiteRT engine artifacts"`
