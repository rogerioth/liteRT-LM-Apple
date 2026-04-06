#!/usr/bin/env bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

upstream_url="${UPSTREAM_URL_DEFAULT}"
upstream_revision="${UPSTREAM_BASE_REVISION_DEFAULT}"
upstream_dir="${UPSTREAM_CLONE_DIR_DEFAULT}"
artifacts_dir="${ARTIFACTS_DIR_DEFAULT}"
public_headers_dir="${PUBLIC_HEADERS_DIR_DEFAULT}"

while (($#)); do
  case "$1" in
    --url)
      upstream_url="$2"
      shift 2
      ;;
    --revision)
      upstream_revision="$2"
      shift 2
      ;;
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
      echo "Usage: $0 [--url URL] [--revision REV] [--source-dir PATH] [--artifacts-dir PATH] [--public-headers-dir PATH]" >&2
      exit 1
      ;;
  esac
done

log_section "LiteRT-LM Apple full rebuild"
log_info "repo root: ${REPO_ROOT}"
log_info "upstream url: ${upstream_url}"
log_info "upstream revision: ${upstream_revision}"
log_info "source dir: ${upstream_dir}"
log_info "artifacts dir: ${artifacts_dir}"
log_info "public headers dir: ${public_headers_dir}"

log_section "Step 1/3: clone and prepare upstream"
"${SCRIPT_DIR}/clone_upstream.sh" \
  --url "${upstream_url}" \
  --revision "${upstream_revision}" \
  --dest "${upstream_dir}"

log_section "Step 2/3: apply local patch"
"${SCRIPT_DIR}/apply_patch.sh" \
  --source-dir "${upstream_dir}"

log_section "Step 3/3: build dylibs and package xcframeworks"
"${SCRIPT_DIR}/build_xcframeworks.sh" \
  --source-dir "${upstream_dir}" \
  --artifacts-dir "${artifacts_dir}" \
  --public-headers-dir "${public_headers_dir}"

log_section "Build complete"
log_info "LiteRT-LM Apple artifacts are ready."
