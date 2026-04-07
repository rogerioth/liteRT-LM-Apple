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
require_cmd install
require_cmd file

mkdir -p "${artifacts_dir}" "${public_headers_dir}"

pushd "${upstream_dir}" >/dev/null
bazelisk build --config=ios_arm64 //c:engine_cpu_shared
bazelisk build --config=ios_sim_arm64 //c:engine_cpu_shared
popd >/dev/null

device_engine_input="${upstream_dir}/bazel-out/ios_arm64-opt/bin/c/libengine_cpu_shared.dylib"
sim_engine_input="${upstream_dir}/bazel-out/ios_sim_arm64-opt/bin/c/libengine_cpu_shared.dylib"
device_constraint_input="${upstream_dir}/prebuilt/ios_arm64/libGemmaModelConstraintProvider.dylib"
sim_constraint_input="${upstream_dir}/prebuilt/ios_sim_arm64/libGemmaModelConstraintProvider.dylib"

device_engine_staged="${tmp_dir}/ios-arm64/libLiteRTLMEngineCPU.dylib"
sim_engine_staged="${tmp_dir}/ios-arm64-simulator/libLiteRTLMEngineCPU.dylib"
device_constraint_staged="${tmp_dir}/ios-arm64/libGemmaModelConstraintProvider.dylib"
sim_constraint_staged="${tmp_dir}/ios-arm64-simulator/libGemmaModelConstraintProvider.dylib"
headers_staged="${tmp_dir}/Headers"
empty_headers_staged="${tmp_dir}/EmptyHeaders"

mkdir -p \
  "$(dirname "${device_engine_staged}")" \
  "$(dirname "${sim_engine_staged}")" \
  "${headers_staged}" \
  "${empty_headers_staged}"

for dylib in "${device_constraint_input}" "${sim_constraint_input}"; do
  if ! file "${dylib}" | grep -q "Mach-O"; then
    echo "Expected a Mach-O dylib but found something else: ${dylib}" >&2
    echo "Run ./scripts/buildall.sh again and ensure git-lfs materializes the prebuilt binaries." >&2
    exit 1
  fi
done

install -m 0644 "${upstream_dir}/c/engine.h" "${public_headers_dir}/engine.h"
install -m 0644 "${upstream_dir}/c/engine.h" "${headers_staged}/engine.h"
touch "${empty_headers_staged}/.gitkeep"
install -m 0755 "${device_engine_input}" "${device_engine_staged}"
install -m 0755 "${sim_engine_input}" "${sim_engine_staged}"
install -m 0755 "${device_constraint_input}" "${device_constraint_staged}"
install -m 0755 "${sim_constraint_input}" "${sim_constraint_staged}"

rm -rf \
  "${artifacts_dir}/LiteRTLMEngineCPU.xcframework" \
  "${artifacts_dir}/GemmaModelConstraintProvider.xcframework"

xcodebuild -create-xcframework \
  -library "${device_engine_staged}" -headers "${empty_headers_staged}" \
  -library "${sim_engine_staged}" -headers "${empty_headers_staged}" \
  -output "${artifacts_dir}/LiteRTLMEngineCPU.xcframework"

xcodebuild -create-xcframework \
  -library "${device_constraint_staged}" -headers "${empty_headers_staged}" \
  -library "${sim_constraint_staged}" -headers "${empty_headers_staged}" \
  -output "${artifacts_dir}/GemmaModelConstraintProvider.xcframework"

echo "Updated package artifacts:"
echo "  ${artifacts_dir}/LiteRTLMEngineCPU.xcframework"
echo "  ${artifacts_dir}/GemmaModelConstraintProvider.xcframework"
echo "  ${public_headers_dir}/engine.h"
