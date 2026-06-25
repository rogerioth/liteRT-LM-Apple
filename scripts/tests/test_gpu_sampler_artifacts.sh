#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
tmp_dir="$(mktemp -d)"

cleanup() {
  rm -rf "${tmp_dir}"
}
trap cleanup EXIT

engine_framework="${repo_root}/Artifacts/LiteRTLMEngineCPU.xcframework/ios-arm64/LRE.framework"
sampler_framework="${repo_root}/Artifacts/LiteRtTopKMetalSampler.xcframework/ios-arm64/LTMTS.framework"
accelerator_framework="${repo_root}/Artifacts/LiteRtMetalAccelerator.xcframework/ios-arm64/LMA.framework"

engine="${engine_framework}/LRE"
sampler="${sampler_framework}/LTMTS"
accelerator="${accelerator_framework}/LMA"

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

require_install_name() {
  local dylib="$1"
  local expected="$2"
  local description="$3"
  local install_name

  install_name="$(otool -D "${dylib}" | awk 'NR == 2 { print }')"
  if [[ "${install_name}" != "${expected}" ]]; then
    echo "FAIL: ${description} has unexpected dynamic library install name: ${dylib}" >&2
    echo "Expected: ${expected}" >&2
    echo "Actual:   ${install_name}" >&2
    exit 1
  fi
}

require_plist_value() {
  local plist="$1"
  local key="$2"
  local expected="$3"
  local description="$4"
  local value

  value="$(/usr/libexec/PlistBuddy -c "Print :${key}" "${plist}")"
  if [[ "${value}" != "${expected}" ]]; then
    echo "FAIL: ${description} has unexpected ${key}: ${plist}" >&2
    echo "Expected: ${expected}" >&2
    echo "Actual:   ${value}" >&2
    exit 1
  fi
}

require_file "${engine}" "iOS engine framework binary"
require_file "${sampler}" "iOS TopK Metal sampler framework binary"
require_file "${accelerator}" "iOS Metal accelerator framework binary"
require_file "${sampler_framework}/Info.plist" "iOS TopK Metal sampler framework Info.plist"

require_ios_arm64_dylib "${engine}" "iOS engine"
require_ios_arm64_dylib "${sampler}" "iOS TopK Metal sampler"
require_ios_arm64_dylib "${accelerator}" "iOS Metal accelerator"

require_install_name "${engine}" "@rpath/LRE.framework/LRE" "iOS engine"
require_install_name "${sampler}" "@rpath/LTMTS.framework/LTMTS" "iOS TopK Metal sampler"
require_install_name "${accelerator}" "@rpath/LMA.framework/LMA" "iOS Metal accelerator"

require_plist_value "${sampler_framework}/Info.plist" "CFBundleExecutable" "LTMTS" "iOS TopK Metal sampler framework"
require_plist_value "${sampler_framework}/Info.plist" "CFBundlePackageType" "FMWK" "iOS TopK Metal sampler framework"
require_plist_value "${sampler_framework}/Info.plist" "CFBundleSupportedPlatforms:0" "iPhoneOS" "iOS TopK Metal sampler framework"

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

echo "PASS: TopK Metal sampler artifacts are valid iOS arm64 frameworks with expected install names and satisfied LiteRT ABI imports."
