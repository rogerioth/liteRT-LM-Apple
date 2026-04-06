#!/usr/bin/env bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

upstream_dir="${UPSTREAM_CLONE_DIR_DEFAULT}"
patch_file="${PATCH_FILE_DEFAULT}"

while (($#)); do
  case "$1" in
    --source-dir)
      upstream_dir="$2"
      shift 2
      ;;
    --patch-file)
      patch_file="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      echo "Usage: $0 [--source-dir PATH] [--patch-file PATH]" >&2
      exit 1
      ;;
  esac
done

require_cmd git

if git -C "${upstream_dir}" apply --check --reverse "${patch_file}" >/dev/null 2>&1; then
  echo "Patch already present in ${upstream_dir}"
  exit 0
fi

git -C "${upstream_dir}" apply "${patch_file}"

echo "Applied patch:"
echo "  ${patch_file}"

