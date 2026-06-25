#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
tmp_dir="$(mktemp -d)"

cleanup() {
  rm -rf "${tmp_dir}"
}
trap cleanup EXIT

fake_bin="${tmp_dir}/bin"
upstream_dir="${tmp_dir}/LiteRT-LM"
artifacts_dir="${tmp_dir}/Artifacts"
headers_dir="${tmp_dir}/Headers"
command_log="${tmp_dir}/commands.log"

mkdir -p \
  "${fake_bin}" \
  "${upstream_dir}/c" \
  "${upstream_dir}/prebuilt/ios_arm64" \
  "${upstream_dir}/prebuilt/ios_sim_arm64" \
  "${upstream_dir}/prebuilt/macos_arm64"

printf '/* test engine header */\n' > "${upstream_dir}/c/engine.h"
printf 'fake Mach-O constraint\n' > "${upstream_dir}/prebuilt/ios_arm64/libGemmaModelConstraintProvider.dylib"
printf 'fake Mach-O constraint\n' > "${upstream_dir}/prebuilt/ios_sim_arm64/libGemmaModelConstraintProvider.dylib"
printf 'fake Mach-O constraint\n' > "${upstream_dir}/prebuilt/macos_arm64/libGemmaModelConstraintProvider.dylib"
printf 'fake Mach-O metal accelerator\n' > "${upstream_dir}/prebuilt/ios_arm64/libLiteRtMetalAccelerator.dylib"
printf 'fake Mach-O metal accelerator\n' > "${upstream_dir}/prebuilt/ios_sim_arm64/libLiteRtMetalAccelerator.dylib"
printf 'fake Mach-O metal accelerator\n' > "${upstream_dir}/prebuilt/macos_arm64/libLiteRtMetalAccelerator.dylib"
printf 'fake Mach-O topk metal sampler\n' > "${upstream_dir}/prebuilt/ios_arm64/libLiteRtTopKMetalSampler.dylib"
printf 'fake Mach-O topk metal sampler\n' > "${upstream_dir}/prebuilt/macos_arm64/libLiteRtTopKMetalSampler.dylib"

cat > "${fake_bin}/bazelisk" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail

printf 'bazelisk %s\n' "$*" >> "${COMMAND_LOG}"

target="${*: -1}"
case "$target" in
  //c:engine_shared|//c:engine_cpu_shared)
    ;;
  *)
    echo "Unexpected Bazel target: ${target}" >&2
    exit 1
    ;;
esac

output_root=""
for arg in "$@"; do
  case "${arg}" in
    --config=ios_arm64)
      output_root="${UPSTREAM_DIR}/bazel-out/ios_arm64-opt/bin/c"
      ;;
    --config=ios_sim_arm64)
      output_root="${UPSTREAM_DIR}/bazel-out/ios_sim_arm64-opt/bin/c"
      ;;
    --config=macos_arm64)
      output_root="${UPSTREAM_DIR}/bazel-out/darwin_arm64-opt/bin/c"
      ;;
  esac
done

if [[ -z "${output_root}" ]]; then
  echo "No recognized Apple output config in: $*" >&2
  exit 1
fi

library_name="lib${target#//c:}.dylib"
mkdir -p "${output_root}"
printf 'fake Mach-O engine for %s\n' "${target}" > "${output_root}/${library_name}"
STUB

cat > "${fake_bin}/xcrun" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail

printf 'xcrun %s\n' "$*" >> "${COMMAND_LOG}"

if [[ "$1" == "vtool" && "$2" == "-show-build" ]]; then
  printf 'minos 17.0\n'
  printf 'sdk 18.0\n'
  exit 0
fi

output=""
input="${*: -1}"
while (($#)); do
  case "$1" in
    -output)
      output="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

if [[ -z "${output}" ]]; then
  echo "xcrun stub expected -output" >&2
  exit 1
fi

mkdir -p "$(dirname "${output}")"
cp "${input}" "${output}"
STUB

cat > "${fake_bin}/xcodebuild" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail

printf 'xcodebuild %s\n' "$*" >> "${COMMAND_LOG}"

output=""
frameworks=()
while (($#)); do
  case "$1" in
    -framework)
      frameworks+=("$2")
      shift 2
      ;;
    -output)
      output="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

for framework in "${frameworks[@]}"; do
  framework_name="$(basename "${framework}" .framework)"
  case "${framework}" in
    *maccatalyst-framework*|*macos-arm64-framework*)
      if [[ -e "${framework}/Info.plist" ]]; then
        echo "Expected versioned ${framework_name}.framework to omit root Info.plist: ${framework}" >&2
        exit 1
      fi
      info_plist="${framework}/Versions/Current/Resources/Info.plist"
      if [[ ! -f "${info_plist}" ]]; then
        echo "Expected versioned ${framework_name}.framework Info.plist under Versions/Current/Resources: ${framework}" >&2
        exit 1
      fi
      if ! grep -q '<key>LSMinimumSystemVersion</key>' "${info_plist}"; then
        echo "Expected versioned ${framework_name}.framework Info.plist to declare LSMinimumSystemVersion: ${framework}" >&2
        exit 1
      fi
      if ! grep -q '<string>MacOSX</string>' "${info_plist}"; then
        echo "Expected versioned ${framework_name}.framework Info.plist to declare MacOSX support: ${framework}" >&2
        exit 1
      fi
      if [[ ! -L "${framework}/${framework_name}" ]]; then
        echo "Expected versioned ${framework_name}.framework root executable symlink: ${framework}" >&2
        exit 1
      fi
      if [[ ! -L "${framework}/Headers" || ! -L "${framework}/Modules" || ! -L "${framework}/Resources" ]]; then
        echo "Expected versioned ${framework_name}.framework root Headers/Modules/Resources symlinks: ${framework}" >&2
        exit 1
      fi
      ;;
    *)
      if [[ ! -f "${framework}/Info.plist" ]]; then
        echo "Expected shallow ${framework_name}.framework root Info.plist: ${framework}" >&2
        exit 1
      fi
      if ! grep -q '<key>MinimumOSVersion</key>' "${framework}/Info.plist"; then
        echo "Expected shallow ${framework_name}.framework Info.plist to declare MinimumOSVersion: ${framework}" >&2
        exit 1
      fi
      if [[ -e "${framework}/Versions" ]]; then
        echo "Expected shallow ${framework_name}.framework to omit Versions directory: ${framework}" >&2
        exit 1
      fi
      ;;
  esac
done

if [[ -z "${output}" ]]; then
  echo "xcodebuild stub expected -output" >&2
  exit 1
fi

mkdir -p "${output}"
printf '<plist />\n' > "${output}/Info.plist"
STUB

cat > "${fake_bin}/install_name_tool" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail

printf 'install_name_tool %s\n' "$*" >> "${COMMAND_LOG}"
STUB

cat > "${fake_bin}/codesign" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail

printf 'codesign %s\n' "$*" >> "${COMMAND_LOG}"
STUB

cat > "${fake_bin}/file" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail

printf '%s: Mach-O 64-bit dynamically linked shared library arm64\n' "$1"
STUB

cat > "${fake_bin}/nm" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail

printf 'nm %s\n' "$*" >> "${COMMAND_LOG}"

case "${*: -1}" in
  *libLiteRtTopKMetalSampler.dylib)
    printf '0000000000000000 T _LiteRtTopKMetalSampler_UpdateConfig\n'
    ;;
esac
STUB

chmod +x "${fake_bin}/bazelisk" "${fake_bin}/xcrun" "${fake_bin}/xcodebuild" "${fake_bin}/install_name_tool" "${fake_bin}/codesign" "${fake_bin}/file" "${fake_bin}/nm"

export COMMAND_LOG="${command_log}"
export UPSTREAM_DIR="${upstream_dir}"
PATH="${fake_bin}:${PATH}" \
  "${repo_root}/scripts/subscripts/build_xcframeworks.sh" \
    --source-dir "${upstream_dir}" \
    --artifacts-dir "${artifacts_dir}" \
    --public-headers-dir "${headers_dir}" \
  > "${tmp_dir}/build.log"

if grep -q '//c:engine_cpu_shared' "${command_log}"; then
  echo "FAIL: build_xcframeworks.sh still builds the CPU-only engine target." >&2
  cat "${command_log}" >&2
  exit 1
fi

engine_builds="$(grep -c '//c:engine_shared' "${command_log}" || true)"
if [[ "${engine_builds}" -ne 3 ]]; then
  echo "FAIL: expected 3 engine_shared builds, found ${engine_builds}." >&2
  cat "${command_log}" >&2
  exit 1
fi

if ! grep -q 'LiteRtMetalAccelerator.xcframework' "${command_log}"; then
  echo "FAIL: expected the Metal accelerator dylib to be packaged as an XCFramework." >&2
  cat "${command_log}" >&2
  exit 1
fi

if ! grep -q 'LiteRtTopKMetalSampler.xcframework' "${command_log}"; then
  echo "FAIL: expected the TopK Metal sampler dylib to be packaged as an XCFramework." >&2
  cat "${command_log}" >&2
  exit 1
fi

if ! grep -q '^nm -gU .*libLiteRtTopKMetalSampler.dylib' "${command_log}"; then
  echo "FAIL: expected the TopK Metal sampler exports to be validated before packaging." >&2
  cat "${command_log}" >&2
  exit 1
fi

if grep -q -- '-library ' "${command_log}"; then
  echo "FAIL: expected XCFrameworks to be created from framework bundles, not standalone dylibs." >&2
  cat "${command_log}" >&2
  exit 1
fi

if ! grep -q -- '-framework .*LRE.framework' "${command_log}"; then
  echo "FAIL: expected the engine to be packaged as a framework bundle." >&2
  cat "${command_log}" >&2
  exit 1
fi

if ! grep -q 'GMCP.framework/GMCP' "${command_log}"; then
  echo "FAIL: expected the engine install name to reference the Gemma framework bundle." >&2
  cat "${command_log}" >&2
  exit 1
fi

framework_signs="$(grep -c '^codesign ' "${command_log}" || true)"
if [[ "${framework_signs}" -ne 24 ]]; then
  echo "FAIL: expected 24 framework signing passes, found ${framework_signs}." >&2
  cat "${command_log}" >&2
  exit 1
fi

echo "PASS: build_xcframeworks.sh packages the GPU-capable engine target as framework bundles."
