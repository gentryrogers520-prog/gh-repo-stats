#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${ROOT_DIR}/dist"
LAUNCHER_SOURCE="${ROOT_DIR}/gh-repo-stats-launcher.go"
RELEASE_TAG="${1:-dev}"
REPO_NAME="${GITHUB_REPOSITORY##*/}"

if [[ -z "${REPO_NAME}" || "${REPO_NAME}" == "${GITHUB_REPOSITORY:-}" ]]; then
  REPO_NAME="$(basename "${ROOT_DIR}")"
fi

if [[ ! -f "${LAUNCHER_SOURCE}" ]]; then
  echo "missing launcher source: ${LAUNCHER_SOURCE}" >&2
  exit 1
fi

if ! command -v go >/dev/null 2>&1; then
  echo "go is required to build release binaries" >&2
  exit 1
fi

rm -rf "${DIST_DIR}"
mkdir -p "${DIST_DIR}"

if [[ -n "${TARGETS:-}" ]]; then
  read -r -a TARGET_LIST <<< "${TARGETS}"
else
  TARGET_LIST=(
    darwin-amd64
    darwin-arm64
    linux-amd64
    linux-arm64
    windows-amd64
    windows-arm64
  )
fi

for target in "${TARGET_LIST[@]}"; do
  goos="${target%-*}"
  goarch="${target#*-}"
  extension=""

  if [[ "${goos}" == "windows" ]]; then
    extension=".exe"
  fi

  output_path="${DIST_DIR}/${REPO_NAME}_${RELEASE_TAG}_${goos}-${goarch}${extension}"

  GOOS="${goos}" GOARCH="${goarch}" CGO_ENABLED=0 \
    go build -trimpath -ldflags="-s -w" -o "${output_path}" "${LAUNCHER_SOURCE}"
done
