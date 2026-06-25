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
mac_engine_framework="${repo_root}/Artifacts/LiteRTLMEngineCPU.xcframework/macos-arm64/LRE.framework"
mac_sampler_framework="${repo_root}/Artifacts/LiteRtTopKMetalSampler.xcframework/macos-arm64/LTMTS.framework"
mac_accelerator_framework="${repo_root}/Artifacts/LiteRtMetalAccelerator.xcframework/macos-arm64/LMA.framework"

engine="${engine_framework}/LRE"
sampler="${sampler_framework}/LTMTS"
accelerator="${accelerator_framework}/LMA"
mac_engine="${mac_engine_framework}/Versions/A/LRE"
mac_sampler="${mac_sampler_framework}/Versions/A/LTMTS"
mac_accelerator="${mac_accelerator_framework}/Versions/A/LMA"

require_file() {
  local path="$1"
  local description="$2"

  if [[ ! -f "${path}" ]]; then
    echo "FAIL: missing ${description}: ${path}" >&2
    exit 1
  fi
}

require_arm64_dylib_platform() {
  local path="$1"
  local description="$2"
  local expected_platform="$3"
  local platform_name="$4"
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
        if ($2 == platform) {
          found_platform = 1
        }
        in_build_version = 0
      }
      END { exit found_platform ? 0 : 1 }
    ' platform="${expected_platform}"; then
    echo "FAIL: ${description} is not tagged as ${platform_name} platform ${expected_platform}: ${path}" >&2
    otool -l "${path}" | awk '/LC_BUILD_VERSION/{show=1} show{print} show && /ntools/{show=0}' >&2
    exit 1
  fi
}

require_ios_arm64_dylib() {
  require_arm64_dylib_platform "$1" "$2" "2" "iOS"
}

require_macos_arm64_dylib() {
  require_arm64_dylib_platform "$1" "$2" "1" "macOS"
}

require_topk_exports() {
  local dylib="$1"
  local description="$2"

  for symbol in \
    LiteRtTopKMetalSampler_Create \
    LiteRtTopKMetalSampler_Destroy \
    LiteRtTopKMetalSampler_SampleToIdAndScoreBuffer \
    LiteRtTopKMetalSampler_UpdateConfig \
    LiteRtTopKMetalSampler_CanHandleInput \
    LiteRtTopKMetalSampler_HandlesInput \
    LiteRtTopKMetalSampler_SetInputTensorsAndInferenceFunc; do
    require_export "${dylib}" "${symbol}" "${description}"
  done
}

require_engine_abi_exports() {
  local dylib="$1"
  local description="$2"

  for symbol in \
    LiteRtCreateModelFromFd \
    LiteRtGetBlockWiseQuantization; do
    require_export "${dylib}" "${symbol}" "${description}"
  done
}

require_litert_imports_satisfied() {
  local sampler_dylib="$1"
  local engine_dylib="$2"
  local label="$3"
  local sampler_undefined="${tmp_dir}/${label}-sampler-undefined.txt"
  local engine_exports="${tmp_dir}/${label}-engine-exports.txt"
  local missing_symbols="${tmp_dir}/${label}-missing-symbols.txt"

  nm -u "${sampler_dylib}" \
    | awk '/_LiteRt/ { symbol = $1; sub(/^_/, "", symbol); print symbol }' \
    | sort -u > "${sampler_undefined}"

  nm -gU "${engine_dylib}" \
    | awk '/ _LiteRt/ { symbol = $NF; sub(/^_/, "", symbol); print symbol }' \
    | sort -u > "${engine_exports}"

  comm -23 "${sampler_undefined}" "${engine_exports}" > "${missing_symbols}"

  if [[ -s "${missing_symbols}" ]]; then
    echo "FAIL: ${label} TopK Metal sampler imports LiteRT symbols not exported by LRE:" >&2
    cat "${missing_symbols}" >&2
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
require_file "${mac_engine}" "macOS engine framework binary"
require_file "${mac_sampler}" "macOS TopK Metal sampler framework binary"
require_file "${mac_accelerator}" "macOS Metal accelerator framework binary"
require_file "${mac_sampler_framework}/Versions/A/Resources/Info.plist" "macOS TopK Metal sampler framework Info.plist"

require_ios_arm64_dylib "${engine}" "iOS engine"
require_ios_arm64_dylib "${sampler}" "iOS TopK Metal sampler"
require_ios_arm64_dylib "${accelerator}" "iOS Metal accelerator"
require_macos_arm64_dylib "${mac_engine}" "macOS engine"
require_macos_arm64_dylib "${mac_sampler}" "macOS TopK Metal sampler"
require_macos_arm64_dylib "${mac_accelerator}" "macOS Metal accelerator"

require_install_name "${engine}" "@rpath/LRE.framework/LRE" "iOS engine"
require_install_name "${sampler}" "@rpath/LTMTS.framework/LTMTS" "iOS TopK Metal sampler"
require_install_name "${accelerator}" "@rpath/LMA.framework/LMA" "iOS Metal accelerator"
require_install_name "${mac_engine}" "@rpath/LRE.framework/LRE" "macOS engine"
require_install_name "${mac_sampler}" "@rpath/LTMTS.framework/LTMTS" "macOS TopK Metal sampler"
require_install_name "${mac_accelerator}" "@rpath/LMA.framework/LMA" "macOS Metal accelerator"

require_plist_value "${sampler_framework}/Info.plist" "CFBundleExecutable" "LTMTS" "iOS TopK Metal sampler framework"
require_plist_value "${sampler_framework}/Info.plist" "CFBundlePackageType" "FMWK" "iOS TopK Metal sampler framework"
require_plist_value "${sampler_framework}/Info.plist" "CFBundleSupportedPlatforms:0" "iPhoneOS" "iOS TopK Metal sampler framework"
require_plist_value "${mac_sampler_framework}/Versions/A/Resources/Info.plist" "CFBundleExecutable" "LTMTS" "macOS TopK Metal sampler framework"
require_plist_value "${mac_sampler_framework}/Versions/A/Resources/Info.plist" "CFBundlePackageType" "FMWK" "macOS TopK Metal sampler framework"
require_plist_value "${mac_sampler_framework}/Versions/A/Resources/Info.plist" "CFBundleSupportedPlatforms:0" "MacOSX" "macOS TopK Metal sampler framework"
require_plist_value "${mac_sampler_framework}/Versions/A/Resources/Info.plist" "LSMinimumSystemVersion" "14.0" "macOS TopK Metal sampler framework"

require_topk_exports "${sampler}" "iOS TopK Metal sampler"
require_topk_exports "${mac_sampler}" "macOS TopK Metal sampler"
require_engine_abi_exports "${engine}" "iOS LiteRT-LM engine compatibility ABI"
require_engine_abi_exports "${mac_engine}" "macOS LiteRT-LM engine compatibility ABI"
require_litert_imports_satisfied "${sampler}" "${engine}" "iOS"
require_litert_imports_satisfied "${mac_sampler}" "${mac_engine}" "macOS"

echo "PASS: TopK Metal sampler artifacts are valid iOS/macOS arm64 frameworks with expected install names and satisfied LiteRT ABI imports."
