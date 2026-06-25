#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
tmp_dir="$(mktemp -d)"

cleanup() {
  rm -rf "${tmp_dir}"
}
trap cleanup EXIT

engine="${repo_root}/Artifacts/LiteRTLMEngineCPU.xcframework/ios-arm64/LRE.framework/LRE"
sampler="${repo_root}/Artifacts/LiteRtTopKMetalSampler.xcframework/ios-arm64/LTMTS.framework/LTMTS"
accelerator="${repo_root}/Artifacts/LiteRtMetalAccelerator.xcframework/ios-arm64/LMA.framework/LMA"

require_file() {
  local path="$1"
  local description="$2"

  if [[ ! -f "${path}" ]]; then
    echo "FAIL: missing ${description}: ${path}" >&2
    exit 1
  fi
}

require_ios_arm64_dylib() {
  local path="$1"
  local description="$2"
  local file_output
  local lipo_output

  file_output="$(file "${path}")"
  if [[ "${file_output}" != *"Mach-O 64-bit dynamically linked shared library arm64"* ]]; then
    echo "FAIL: ${description} is not an arm64 Mach-O dylib: ${path}" >&2
    echo "${file_output}" >&2
    exit 1
  fi

  lipo_output="$(lipo -info "${path}")"
  if [[ "${lipo_output}" != *"architecture: arm64"* && "${lipo_output}" != *"are: arm64"* ]]; then
    echo "FAIL: ${description} does not advertise arm64 through lipo: ${path}" >&2
    echo "${lipo_output}" >&2
    exit 1
  fi

  if ! otool -l "${path}" | awk '
      /LC_BUILD_VERSION/ { in_build_version = 1; next }
      in_build_version && /platform/ {
        if ($2 == "2") {
          found_ios = 1
        }
        in_build_version = 0
      }
      END { exit found_ios ? 0 : 1 }
    '; then
    echo "FAIL: ${description} is not tagged as iOS platform 2: ${path}" >&2
    otool -l "${path}" | awk '/LC_BUILD_VERSION/{show=1} show{print} show && /ntools/{show=0}' >&2
    exit 1
  fi
}

require_export() {
  local dylib="$1"
  local symbol="$2"
  local description="$3"

  if ! nm -gU "${dylib}" | awk -v symbol="${symbol}" '$NF == "_" symbol { found = 1 } END { exit found ? 0 : 1 }'; then
    echo "FAIL: ${description} is missing export ${symbol}: ${dylib}" >&2
    exit 1
  fi
}

require_file "${engine}" "iOS engine framework binary"
require_file "${sampler}" "iOS TopK Metal sampler framework binary"
require_file "${accelerator}" "iOS Metal accelerator framework binary"

require_ios_arm64_dylib "${engine}" "iOS engine"
require_ios_arm64_dylib "${sampler}" "iOS TopK Metal sampler"
require_ios_arm64_dylib "${accelerator}" "iOS Metal accelerator"

for symbol in \
  LiteRtTopKMetalSampler_Create \
  LiteRtTopKMetalSampler_Destroy \
  LiteRtTopKMetalSampler_SampleToIdAndScoreBuffer \
  LiteRtTopKMetalSampler_UpdateConfig \
  LiteRtTopKMetalSampler_CanHandleInput \
  LiteRtTopKMetalSampler_HandlesInput \
  LiteRtTopKMetalSampler_SetInputTensorsAndInferenceFunc; do
  require_export "${sampler}" "${symbol}" "TopK Metal sampler"
done

for symbol in \
  LiteRtCreateModelFromFd \
  LiteRtGetBlockWiseQuantization; do
  require_export "${engine}" "${symbol}" "LiteRT-LM engine compatibility ABI"
done

sampler_undefined="${tmp_dir}/sampler-undefined.txt"
engine_exports="${tmp_dir}/engine-exports.txt"
missing_symbols="${tmp_dir}/missing-symbols.txt"

nm -u "${sampler}" \
  | awk '/_LiteRt/ { symbol = $1; sub(/^_/, "", symbol); print symbol }' \
  | sort -u > "${sampler_undefined}"

nm -gU "${engine}" \
  | awk '/ _LiteRt/ { symbol = $NF; sub(/^_/, "", symbol); print symbol }' \
  | sort -u > "${engine_exports}"

comm -23 "${sampler_undefined}" "${engine_exports}" > "${missing_symbols}"

if [[ -s "${missing_symbols}" ]]; then
  echo "FAIL: TopK Metal sampler imports LiteRT symbols not exported by LRE:" >&2
  cat "${missing_symbols}" >&2
  exit 1
fi

echo "PASS: TopK Metal sampler artifacts are valid iOS arm64 binaries with satisfied LiteRT ABI imports."
