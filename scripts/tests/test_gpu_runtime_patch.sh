#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
patch_file="${repo_root}/patches/0001-export-ios-shared-engine-dylib.patch"

require_pattern() {
  local pattern="$1"
  local description="$2"

  if ! grep -q "${pattern}" "${patch_file}"; then
    echo "FAIL: patch is missing ${description}." >&2
    echo "Pattern: ${pattern}" >&2
    exit 1
  fi
}

require_pattern "litert_lm_engine_settings_set_runtime_library_dir" "the C API runtime library directory setter"
require_pattern "EnvironmentOptions::Tag::kRuntimeLibraryDir" "the LiteRT runtime library directory environment option"
require_pattern "GetLitertDispatchLibDir" "the stored runtime library directory lookup"
require_pattern "static_cast<int64_t>(ToLiteRtLogSeverityInt8" "int64 LiteRT min-log-severity environment option"

echo "PASS: LiteRT-LM patch configures the GPU runtime library directory."
