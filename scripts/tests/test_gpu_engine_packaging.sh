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
  echo "xcodebuild stub expected -output" >&2
  exit 1
fi

mkdir -p "${output}"
printf '<plist />\n' > "${output}/Info.plist"
STUB

cat > "${fake_bin}/file" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail

printf '%s: Mach-O 64-bit dynamically linked shared library arm64\n' "$1"
STUB

chmod +x "${fake_bin}/bazelisk" "${fake_bin}/xcrun" "${fake_bin}/xcodebuild" "${fake_bin}/file"

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

echo "PASS: build_xcframeworks.sh packages the GPU-capable engine target."
