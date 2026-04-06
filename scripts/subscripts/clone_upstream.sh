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
    --dest)
      upstream_dir="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      echo "Usage: $0 [--url URL] [--revision REV] [--dest PATH]" >&2
      exit 1
      ;;
  esac
done

require_cmd git
if ! git lfs version >/dev/null 2>&1; then
  echo "git-lfs is required and must be available as 'git lfs'" >&2
  exit 1
fi

mkdir -p "$(dirname "${upstream_dir}")"

if [[ ! -d "${upstream_dir}/.git" ]]; then
  git clone "${upstream_url}" "${upstream_dir}"
fi

git -C "${upstream_dir}" fetch --tags --prune origin
git -C "${upstream_dir}" reset --hard
git -C "${upstream_dir}" clean -fdx
git -C "${upstream_dir}" checkout "${upstream_revision}"
git -C "${upstream_dir}" lfs install --local
git -C "${upstream_dir}" lfs pull origin "${upstream_revision}"
git -C "${upstream_dir}" lfs checkout

echo "Prepared upstream LiteRT-LM checkout:"
echo "  repo: ${upstream_dir}"
echo "  revision: $(git -C "${upstream_dir}" rev-parse HEAD)"
