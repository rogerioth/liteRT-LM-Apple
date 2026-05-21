#!/usr/bin/env bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

upstream_dir="${UPSTREAM_CLONE_DIR_DEFAULT}"
artifacts_dir="${ARTIFACTS_DIR_DEFAULT}"
public_headers_dir="${PUBLIC_HEADERS_DIR_DEFAULT}"
tmp_dir="$(mktemp -d)"

cleanup() {
  rm -rf "${tmp_dir}"
}
trap cleanup EXIT

while (($#)); do
  case "$1" in
    --source-dir)
      upstream_dir="$2"
      shift 2
      ;;
    --artifacts-dir)
      artifacts_dir="$2"
      shift 2
      ;;
    --public-headers-dir)
      public_headers_dir="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      echo "Usage: $0 [--source-dir PATH] [--artifacts-dir PATH] [--public-headers-dir PATH]" >&2
      exit 1
      ;;
  esac
done

require_cmd bazelisk
require_cmd xcodebuild
require_cmd xcrun
require_cmd install
require_cmd install_name_tool
require_cmd codesign
require_cmd file

mkdir -p "${artifacts_dir}" "${public_headers_dir}"

extract_build_setting() {
  local input="$1"
  local setting="$2"

  xcrun vtool -show-build "${input}" | awk -v key="${setting}" '$1 == key { print $2; exit }'
}

retag_build_version() {
  local platform="$1"
  local input="$2"
  local output="$3"
  local minos_override="${4:-}"
  local minos sdk

  minos="${minos_override:-$(extract_build_setting "${input}" minos)}"
  sdk="$(extract_build_setting "${input}" sdk)"

  if [[ -z "${minos}" || -z "${sdk}" ]]; then
    echo "Failed to extract build settings from ${input}." >&2
    exit 1
  fi

  xcrun vtool \
    -set-build-version "${platform}" "${minos}" "${sdk}" \
    -replace \
    -output "${output}" \
    "${input}" >/dev/null 2>&1
}

framework_install_name() {
  local framework_name="$1"
  local executable_name="$2"

  printf '@rpath/%s.framework/%s' "${framework_name}" "${executable_name}"
}

write_framework_info_plist() {
  local framework_dir="$1"
  local framework_name="$2"
  local executable_name="$3"

  cat > "${framework_dir}/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleExecutable</key>
	<string>${executable_name}</string>
	<key>CFBundleIdentifier</key>
	<string>com.rogerioth.litertlm.${framework_name}</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>${framework_name}</string>
	<key>CFBundlePackageType</key>
	<string>FMWK</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
</dict>
</plist>
PLIST
}

wrap_framework() {
  local framework_name="$1"
  local executable_name="$2"
  local input_binary="$3"
  local headers_dir="$4"
  local output_root="$5"
  local module_name
  local framework_dir="${output_root}/${framework_name}.framework"

  module_name="$(printf '%s' "${framework_name}" | tr -cd '[:alnum:]_')"

  rm -rf "${framework_dir}"
  mkdir -p \
    "${framework_dir}/Headers" \
    "${framework_dir}/Modules"

  install -m 0755 "${input_binary}" "${framework_dir}/${executable_name}"
  install -m 0644 "${headers_dir}"/* "${framework_dir}/Headers/"
  write_framework_info_plist "${framework_dir}" "${framework_name}" "${executable_name}"
  cat > "${framework_dir}/Modules/module.modulemap" <<MODULEMAP
framework module ${module_name} {
  umbrella "Headers"
  export *
  module * { export * }
}
MODULEMAP

  install_name_tool \
    -id "$(framework_install_name "${framework_name}" "${executable_name}")" \
    "${framework_dir}/${executable_name}"

  printf '%s\n' "${framework_dir}"
}

sign_framework() {
  local framework_dir="$1"

  codesign --force --sign - --timestamp=none "${framework_dir}" >/dev/null
}

pushd "${upstream_dir}" >/dev/null
bazelisk build --config=ios_arm64 //c:engine_shared
bazelisk build --config=ios_sim_arm64 //c:engine_shared
bazelisk build --config=macos --config=macos_arm64 //c:engine_shared
popd >/dev/null

device_engine_input="${upstream_dir}/bazel-out/ios_arm64-opt/bin/c/libengine_shared.dylib"
sim_engine_input="${upstream_dir}/bazel-out/ios_sim_arm64-opt/bin/c/libengine_shared.dylib"
mac_engine_input="${upstream_dir}/bazel-out/darwin_arm64-opt/bin/c/libengine_shared.dylib"
device_constraint_input="${upstream_dir}/prebuilt/ios_arm64/libGemmaModelConstraintProvider.dylib"
sim_constraint_input="${upstream_dir}/prebuilt/ios_sim_arm64/libGemmaModelConstraintProvider.dylib"
mac_constraint_input="${upstream_dir}/prebuilt/macos_arm64/libGemmaModelConstraintProvider.dylib"
device_metal_accelerator_input="${upstream_dir}/prebuilt/ios_arm64/libLiteRtMetalAccelerator.dylib"
sim_metal_accelerator_input="${upstream_dir}/prebuilt/ios_sim_arm64/libLiteRtMetalAccelerator.dylib"
mac_metal_accelerator_input="${upstream_dir}/prebuilt/macos_arm64/libLiteRtMetalAccelerator.dylib"

device_engine_staged="${tmp_dir}/ios-arm64/libLiteRTLMEngineCPU.dylib"
sim_engine_staged="${tmp_dir}/ios-arm64-simulator/libLiteRTLMEngineCPU.dylib"
catalyst_engine_staged="${tmp_dir}/ios-arm64-maccatalyst/libLiteRTLMEngineCPU.dylib"
mac_engine_staged="${tmp_dir}/macos-arm64/libLiteRTLMEngineCPU.dylib"
vision_engine_staged="${tmp_dir}/xros-arm64/libLiteRTLMEngineCPU.dylib"
vision_sim_engine_staged="${tmp_dir}/xros-arm64-simulator/libLiteRTLMEngineCPU.dylib"
device_constraint_staged="${tmp_dir}/ios-arm64/libGemmaModelConstraintProvider.dylib"
sim_constraint_staged="${tmp_dir}/ios-arm64-simulator/libGemmaModelConstraintProvider.dylib"
catalyst_constraint_staged="${tmp_dir}/ios-arm64-maccatalyst/libGemmaModelConstraintProvider.dylib"
mac_constraint_staged="${tmp_dir}/macos-arm64/libGemmaModelConstraintProvider.dylib"
vision_constraint_staged="${tmp_dir}/xros-arm64/libGemmaModelConstraintProvider.dylib"
vision_sim_constraint_staged="${tmp_dir}/xros-arm64-simulator/libGemmaModelConstraintProvider.dylib"
device_metal_accelerator_staged="${tmp_dir}/ios-arm64/libLiteRtMetalAccelerator.dylib"
sim_metal_accelerator_staged="${tmp_dir}/ios-arm64-simulator/libLiteRtMetalAccelerator.dylib"
catalyst_metal_accelerator_staged="${tmp_dir}/ios-arm64-maccatalyst/libLiteRtMetalAccelerator.dylib"
mac_metal_accelerator_staged="${tmp_dir}/macos-arm64/libLiteRtMetalAccelerator.dylib"
vision_metal_accelerator_staged="${tmp_dir}/xros-arm64/libLiteRtMetalAccelerator.dylib"
vision_sim_metal_accelerator_staged="${tmp_dir}/xros-arm64-simulator/libLiteRtMetalAccelerator.dylib"
headers_staged="${tmp_dir}/Headers"
engine_placeholder_headers_staged="${tmp_dir}/EnginePlaceholderHeaders"
constraint_placeholder_headers_staged="${tmp_dir}/ConstraintPlaceholderHeaders"
metal_accelerator_placeholder_headers_staged="${tmp_dir}/MetalAcceleratorPlaceholderHeaders"

mkdir -p \
  "$(dirname "${device_engine_staged}")" \
  "$(dirname "${sim_engine_staged}")" \
  "$(dirname "${catalyst_engine_staged}")" \
  "$(dirname "${mac_engine_staged}")" \
  "$(dirname "${vision_engine_staged}")" \
  "$(dirname "${vision_sim_engine_staged}")" \
  "${headers_staged}" \
  "${engine_placeholder_headers_staged}" \
  "${constraint_placeholder_headers_staged}" \
  "${metal_accelerator_placeholder_headers_staged}"

for dylib in \
  "${device_constraint_input}" \
  "${sim_constraint_input}" \
  "${mac_constraint_input}" \
  "${device_metal_accelerator_input}" \
  "${sim_metal_accelerator_input}" \
  "${mac_metal_accelerator_input}"; do
  if ! file "${dylib}" | grep -q "Mach-O"; then
    echo "Expected a Mach-O dylib but found something else: ${dylib}" >&2
    echo "Run ./scripts/buildall.sh again and ensure git-lfs materializes the prebuilt binaries." >&2
    exit 1
  fi
done

install -m 0644 "${upstream_dir}/c/engine.h" "${public_headers_dir}/engine.h"
install -m 0644 "${upstream_dir}/c/engine.h" "${headers_staged}/engine.h"
printf '/* Placeholder header to preserve the XCFramework Headers directory in Git. */\n' > "${engine_placeholder_headers_staged}/LiteRTLMEngineCPUPlaceholder.h"
printf '/* Placeholder header to preserve the XCFramework Headers directory in Git. */\n' > "${constraint_placeholder_headers_staged}/GemmaModelConstraintProviderPlaceholder.h"
printf '/* Placeholder header to preserve the XCFramework Headers directory in Git. */\n' > "${metal_accelerator_placeholder_headers_staged}/LiteRtMetalAcceleratorPlaceholder.h"
install -m 0755 "${device_engine_input}" "${device_engine_staged}"
install -m 0755 "${sim_engine_input}" "${sim_engine_staged}"
# Upstream does not publish dedicated Mac Catalyst dylibs, so derive a
# maccatalyst slice from the Apple Silicon iOS simulator build.
retag_build_version maccatalyst "${sim_engine_input}" "${catalyst_engine_staged}"
install -m 0755 "${mac_engine_input}" "${mac_engine_staged}"
# Upstream also does not publish dedicated visionOS dylibs, so derive the
# device and simulator slices from the existing iOS outputs.
retag_build_version visionos "${device_engine_input}" "${vision_engine_staged}" "1.0"
retag_build_version visionossim "${sim_engine_input}" "${vision_sim_engine_staged}" "1.0"
install -m 0755 "${device_constraint_input}" "${device_constraint_staged}"
install -m 0755 "${sim_constraint_input}" "${sim_constraint_staged}"
retag_build_version maccatalyst "${sim_constraint_input}" "${catalyst_constraint_staged}"
install -m 0755 "${mac_constraint_input}" "${mac_constraint_staged}"
retag_build_version visionos "${device_constraint_input}" "${vision_constraint_staged}" "1.0"
retag_build_version visionossim "${sim_constraint_input}" "${vision_sim_constraint_staged}" "1.0"
install -m 0755 "${device_metal_accelerator_input}" "${device_metal_accelerator_staged}"
install -m 0755 "${sim_metal_accelerator_input}" "${sim_metal_accelerator_staged}"
retag_build_version maccatalyst "${sim_metal_accelerator_input}" "${catalyst_metal_accelerator_staged}"
install -m 0755 "${mac_metal_accelerator_input}" "${mac_metal_accelerator_staged}"
retag_build_version visionos "${device_metal_accelerator_input}" "${vision_metal_accelerator_staged}" "1.0"
retag_build_version visionossim "${sim_metal_accelerator_input}" "${vision_sim_metal_accelerator_staged}" "1.0"

rm -rf \
  "${artifacts_dir}/LiteRTLMEngineCPU.xcframework" \
  "${artifacts_dir}/GemmaModelConstraintProvider.xcframework" \
  "${artifacts_dir}/LiteRtMetalAccelerator.xcframework"

engine_framework_name="LRE"
engine_executable_name="LRE"
constraint_framework_name="GMCP"
constraint_executable_name="GMCP"
metal_framework_name="LMA"
metal_executable_name="LMA"

engine_device_framework="$(wrap_framework "${engine_framework_name}" "${engine_executable_name}" "${device_engine_staged}" "${engine_placeholder_headers_staged}" "${tmp_dir}/ios-arm64-framework")"
engine_sim_framework="$(wrap_framework "${engine_framework_name}" "${engine_executable_name}" "${sim_engine_staged}" "${engine_placeholder_headers_staged}" "${tmp_dir}/ios-arm64-simulator-framework")"
engine_catalyst_framework="$(wrap_framework "${engine_framework_name}" "${engine_executable_name}" "${catalyst_engine_staged}" "${engine_placeholder_headers_staged}" "${tmp_dir}/ios-arm64-maccatalyst-framework")"
engine_mac_framework="$(wrap_framework "${engine_framework_name}" "${engine_executable_name}" "${mac_engine_staged}" "${engine_placeholder_headers_staged}" "${tmp_dir}/macos-arm64-framework")"
engine_vision_framework="$(wrap_framework "${engine_framework_name}" "${engine_executable_name}" "${vision_engine_staged}" "${engine_placeholder_headers_staged}" "${tmp_dir}/xros-arm64-framework")"
engine_vision_sim_framework="$(wrap_framework "${engine_framework_name}" "${engine_executable_name}" "${vision_sim_engine_staged}" "${engine_placeholder_headers_staged}" "${tmp_dir}/xros-arm64-simulator-framework")"

constraint_device_framework="$(wrap_framework "${constraint_framework_name}" "${constraint_executable_name}" "${device_constraint_staged}" "${constraint_placeholder_headers_staged}" "${tmp_dir}/ios-arm64-framework")"
constraint_sim_framework="$(wrap_framework "${constraint_framework_name}" "${constraint_executable_name}" "${sim_constraint_staged}" "${constraint_placeholder_headers_staged}" "${tmp_dir}/ios-arm64-simulator-framework")"
constraint_catalyst_framework="$(wrap_framework "${constraint_framework_name}" "${constraint_executable_name}" "${catalyst_constraint_staged}" "${constraint_placeholder_headers_staged}" "${tmp_dir}/ios-arm64-maccatalyst-framework")"
constraint_mac_framework="$(wrap_framework "${constraint_framework_name}" "${constraint_executable_name}" "${mac_constraint_staged}" "${constraint_placeholder_headers_staged}" "${tmp_dir}/macos-arm64-framework")"
constraint_vision_framework="$(wrap_framework "${constraint_framework_name}" "${constraint_executable_name}" "${vision_constraint_staged}" "${constraint_placeholder_headers_staged}" "${tmp_dir}/xros-arm64-framework")"
constraint_vision_sim_framework="$(wrap_framework "${constraint_framework_name}" "${constraint_executable_name}" "${vision_sim_constraint_staged}" "${constraint_placeholder_headers_staged}" "${tmp_dir}/xros-arm64-simulator-framework")"

metal_device_framework="$(wrap_framework "${metal_framework_name}" "${metal_executable_name}" "${device_metal_accelerator_staged}" "${metal_accelerator_placeholder_headers_staged}" "${tmp_dir}/ios-arm64-framework")"
metal_sim_framework="$(wrap_framework "${metal_framework_name}" "${metal_executable_name}" "${sim_metal_accelerator_staged}" "${metal_accelerator_placeholder_headers_staged}" "${tmp_dir}/ios-arm64-simulator-framework")"
metal_catalyst_framework="$(wrap_framework "${metal_framework_name}" "${metal_executable_name}" "${catalyst_metal_accelerator_staged}" "${metal_accelerator_placeholder_headers_staged}" "${tmp_dir}/ios-arm64-maccatalyst-framework")"
metal_mac_framework="$(wrap_framework "${metal_framework_name}" "${metal_executable_name}" "${mac_metal_accelerator_staged}" "${metal_accelerator_placeholder_headers_staged}" "${tmp_dir}/macos-arm64-framework")"
metal_vision_framework="$(wrap_framework "${metal_framework_name}" "${metal_executable_name}" "${vision_metal_accelerator_staged}" "${metal_accelerator_placeholder_headers_staged}" "${tmp_dir}/xros-arm64-framework")"
metal_vision_sim_framework="$(wrap_framework "${metal_framework_name}" "${metal_executable_name}" "${vision_sim_metal_accelerator_staged}" "${metal_accelerator_placeholder_headers_staged}" "${tmp_dir}/xros-arm64-simulator-framework")"

for engine_framework in \
  "${engine_device_framework}" \
  "${engine_sim_framework}" \
  "${engine_catalyst_framework}" \
  "${engine_mac_framework}" \
  "${engine_vision_framework}" \
  "${engine_vision_sim_framework}"; do
  install_name_tool \
    -change \
    "@rpath/libGemmaModelConstraintProvider.dylib" \
    "$(framework_install_name "${constraint_framework_name}" "${constraint_executable_name}")" \
    "${engine_framework}/${engine_executable_name}"
done

for framework in \
  "${engine_device_framework}" \
  "${engine_sim_framework}" \
  "${engine_catalyst_framework}" \
  "${engine_mac_framework}" \
  "${engine_vision_framework}" \
  "${engine_vision_sim_framework}" \
  "${constraint_device_framework}" \
  "${constraint_sim_framework}" \
  "${constraint_catalyst_framework}" \
  "${constraint_mac_framework}" \
  "${constraint_vision_framework}" \
  "${constraint_vision_sim_framework}" \
  "${metal_device_framework}" \
  "${metal_sim_framework}" \
  "${metal_catalyst_framework}" \
  "${metal_mac_framework}" \
  "${metal_vision_framework}" \
  "${metal_vision_sim_framework}"; do
  sign_framework "${framework}"
done

xcodebuild -create-xcframework \
  -framework "${engine_device_framework}" \
  -framework "${engine_sim_framework}" \
  -framework "${engine_catalyst_framework}" \
  -framework "${engine_mac_framework}" \
  -framework "${engine_vision_framework}" \
  -framework "${engine_vision_sim_framework}" \
  -output "${artifacts_dir}/LiteRTLMEngineCPU.xcframework"

xcodebuild -create-xcframework \
  -framework "${constraint_device_framework}" \
  -framework "${constraint_sim_framework}" \
  -framework "${constraint_catalyst_framework}" \
  -framework "${constraint_mac_framework}" \
  -framework "${constraint_vision_framework}" \
  -framework "${constraint_vision_sim_framework}" \
  -output "${artifacts_dir}/GemmaModelConstraintProvider.xcframework"

xcodebuild -create-xcframework \
  -framework "${metal_device_framework}" \
  -framework "${metal_sim_framework}" \
  -framework "${metal_catalyst_framework}" \
  -framework "${metal_mac_framework}" \
  -framework "${metal_vision_framework}" \
  -framework "${metal_vision_sim_framework}" \
  -output "${artifacts_dir}/LiteRtMetalAccelerator.xcframework"

echo "Updated package artifacts:"
echo "  ${artifacts_dir}/LiteRTLMEngineCPU.xcframework"
echo "  ${artifacts_dir}/GemmaModelConstraintProvider.xcframework"
echo "  ${artifacts_dir}/LiteRtMetalAccelerator.xcframework"
echo "  ${public_headers_dir}/engine.h"
