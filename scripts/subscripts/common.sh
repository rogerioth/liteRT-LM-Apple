#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
UPSTREAM_URL_DEFAULT="https://github.com/google-ai-edge/LiteRT-LM.git"
UPSTREAM_BASE_REVISION_DEFAULT="7d1923daaaa1e5143f77f0adb105188e53e8485e"
UPSTREAM_CLONE_DIR_DEFAULT="${REPO_ROOT}/.worktree/LiteRT-LM"
PATCH_FILE_DEFAULT="${REPO_ROOT}/patches/0001-export-ios-shared-engine-dylib.patch"
ARTIFACTS_DIR_DEFAULT="${REPO_ROOT}/Artifacts"
PUBLIC_HEADERS_DIR_DEFAULT="${REPO_ROOT}/Sources/LiteRTLMApple/include"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

log_section() {
  echo
  echo "==> $*"
}

log_info() {
  echo "  -> $*"
}
