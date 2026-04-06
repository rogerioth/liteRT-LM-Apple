#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
UPSTREAM_URL_DEFAULT="https://github.com/google-ai-edge/LiteRT-LM.git"
UPSTREAM_BASE_REVISION_DEFAULT="e4d5da404e54eeea7903ae23d81fe8447cb3e089"
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

