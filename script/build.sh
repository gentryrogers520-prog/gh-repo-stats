#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${ROOT_DIR}/dist"
ENTRYPOINT="${ROOT_DIR}/gh-repo-stats"
RELEASE_TAG="${1:-dev}"
REPOSITORY_NAME="${GITHUB_REPOSITORY##*/}"

if [[ -z "${REPOSITORY_NAME}" || "${REPOSITORY_NAME}" == "${GITHUB_REPOSITORY}" ]]; then
  REPOSITORY_NAME="$(basename "${ROOT_DIR}")"
fi

if [[ ! -f "${ENTRYPOINT}" ]]; then
  echo "Expected extension entrypoint at ${ENTRYPOINT}" >&2
  exit 1
fi

if ! command -v go >/dev/null 2>&1; then
  echo "go is required to build release artifacts" >&2
  exit 1
fi

mkdir -p "${DIST_DIR}"
rm -f "${DIST_DIR}"/*

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

SCRIPT_BASE64="$(base64 "${ENTRYPOINT}" | tr -d '\n')"

cat > "${TMP_DIR}/main.go" <<'EOF'
package main

import (
	"encoding/base64"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
)

const scriptBase64 = "__SCRIPT_BASE64__"

func findBash() (string, error) {
	if bashPath, err := exec.LookPath("bash"); err == nil {
		return bashPath, nil
	}

	if runtime.GOOS != "windows" {
		return "", errors.New("bash is required to run gh-repo-stats")
	}

	candidates := []string{
		"C:\\Program Files\\Git\\bin\\bash.exe",
		"C:\\Program Files\\Git\\usr\\bin\\bash.exe",
		"C:\\Program Files (x86)\\Git\\bin\\bash.exe",
		"C:\\Program Files (x86)\\Git\\usr\\bin\\bash.exe",
	}

	for _, candidate := range candidates {
		if _, err := os.Stat(candidate); err == nil {
			return candidate, nil
		}
	}

	return "", errors.New("bash is required to run gh-repo-stats; install Git Bash or add bash to PATH")
}

func main() {
	scriptContents, err := base64.StdEncoding.DecodeString(scriptBase64)
	if err != nil {
		fmt.Fprintf(os.Stderr, "decode embedded script: %v\n", err)
		os.Exit(1)
	}

	tmpDir, err := os.MkdirTemp("", "gh-repo-stats-*")
	if err != nil {
		fmt.Fprintf(os.Stderr, "create temp dir: %v\n", err)
		os.Exit(1)
	}
	defer os.RemoveAll(tmpDir)

	scriptPath := filepath.Join(tmpDir, "gh-repo-stats.sh")
	if err := os.WriteFile(scriptPath, scriptContents, 0o700); err != nil {
		fmt.Fprintf(os.Stderr, "write embedded script: %v\n", err)
		os.Exit(1)
	}

	bashPath, err := findBash()
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}

	args := append([]string{scriptPath}, os.Args[1:]...)
	cmd := exec.Command(bashPath, args...)
	cmd.Stdin = os.Stdin
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	cmd.Env = os.Environ()

	if err := cmd.Run(); err != nil {
		var exitErr *exec.ExitError
		if errors.As(err, &exitErr) {
			os.Exit(exitErr.ExitCode())
		}

		fmt.Fprintf(os.Stderr, "run gh-repo-stats: %v\n", err)
		os.Exit(1)
	}
}
EOF

python - "${TMP_DIR}/main.go" "${SCRIPT_BASE64}" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
path.write_text(path.read_text().replace("__SCRIPT_BASE64__", sys.argv[2]))
PY

targets=(
  "darwin amd64"
  "darwin arm64"
  "linux amd64"
  "linux arm64"
  "windows amd64"
  "windows arm64"
)

for target in "${targets[@]}"; do
  read -r goos goarch <<< "${target}"

  extension=""
  if [[ "${goos}" == "windows" ]]; then
    extension=".exe"
  fi

  output_path="${DIST_DIR}/${REPOSITORY_NAME}_${RELEASE_TAG}_${goos}-${goarch}${extension}"
  echo "Building ${output_path}"

  GO111MODULE=off \
  CGO_ENABLED=0 \
  GOOS="${goos}" \
  GOARCH="${goarch}" \
  go build -trimpath -ldflags="-s -w" -o "${output_path}" "${TMP_DIR}/main.go"
done
