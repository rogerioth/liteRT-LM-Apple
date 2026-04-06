#!/usr/bin/env bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

upstream_url="${UPSTREAM_URL_DEFAULT}"
upstream_revision="${UPSTREAM_BASE_REVISION_DEFAULT}"
upstream_dir="${UPSTREAM_CLONE_DIR_DEFAULT}"

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
    *)
      echo "Unknown argument: $1" >&2
      echo "Usage: $0 [--url URL] [--revision REV] [--source-dir PATH]" >&2
      exit 1
      ;;
  esac
done

"${SCRIPT_DIR}/clone_upstream.sh" \
  --url "${upstream_url}" \
  --revision "${upstream_revision}" \
  --dest "${upstream_dir}"

"${SCRIPT_DIR}/apply_patch.sh" \
  --source-dir "${upstream_dir}"

"${SCRIPT_DIR}/build_xcframeworks.sh" \
  --source-dir "${upstream_dir}"

