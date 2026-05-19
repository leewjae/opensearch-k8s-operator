#!/usr/bin/env bash

set -euo pipefail

dockerfile_path="${1:-Dockerfile}"

if [[ ! -f "${dockerfile_path}" ]]; then
  echo "ERROR: Dockerfile not found: ${dockerfile_path}" >&2
  exit 1
fi

go_image_line="$(
  grep -E '^FROM[[:space:]]+.*golang:[0-9]+\.[0-9]+\.[0-9]+' "${dockerfile_path}" | head -n 1 || true
)"

if [[ -z "${go_image_line}" ]]; then
  echo "ERROR: unable to find a golang:<major>.<minor>.<patch> base image in ${dockerfile_path}" >&2
  exit 1
fi

go_version="$(
  echo "${go_image_line}" | sed -E 's/.*golang:([0-9]+\.[0-9]+\.[0-9]+).*/\1/'
)"

IFS='.' read -r go_major go_minor go_patch <<< "${go_version}"

if [[ -z "${go_major}" || -z "${go_minor}" || -z "${go_patch}" ]]; then
  echo "ERROR: failed to parse Go version from Dockerfile: ${go_version}" >&2
  exit 1
fi

# CVE-2023-45288 (GO-2024-2687) is fixed in Go 1.21.9 and 1.22.2.
# Keep this check to prevent regressions to known-vulnerable toolchain versions.
if (( go_major == 1 )); then
  if (( go_minor < 21 )); then
    echo "ERROR: Go ${go_version} is below the secure baseline for CVE-2023-45288" >&2
    exit 1
  fi

  if (( go_minor == 21 && go_patch < 9 )); then
    echo "ERROR: Go ${go_version} is vulnerable to CVE-2023-45288 (requires >= 1.21.9)" >&2
    exit 1
  fi

  if (( go_minor == 22 && go_patch < 2 )); then
    echo "ERROR: Go ${go_version} is vulnerable to CVE-2023-45288 (requires >= 1.22.2)" >&2
    exit 1
  fi
fi

echo "Go toolchain baseline check passed: ${go_version}"
