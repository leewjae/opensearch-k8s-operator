#!/usr/bin/env bash

set -euo pipefail

dockerfile_path="${1:-Dockerfile}"
go_mod_path="${2:-go.mod}"
main_go_path="${3:-main.go}"

parse_semver() {
  local raw="${1#v}"
  local major minor patch
  IFS='.' read -r major minor patch <<< "${raw}"
  patch="${patch%%[^0-9]*}"

  if [[ -z "${major}" || -z "${minor}" || -z "${patch}" ]]; then
    return 1
  fi
  echo "${major} ${minor} ${patch}"
}

version_ge() {
  local left="$1"
  local right="$2"
  local l_major l_minor l_patch
  local r_major r_minor r_patch

  read -r l_major l_minor l_patch < <(parse_semver "${left}") || return 1
  read -r r_major r_minor r_patch < <(parse_semver "${right}") || return 1

  if (( l_major > r_major )); then
    return 0
  elif (( l_major < r_major )); then
    return 1
  fi

  if (( l_minor > r_minor )); then
    return 0
  elif (( l_minor < r_minor )); then
    return 1
  fi

  (( l_patch >= r_patch ))
}

if [[ ! -f "${dockerfile_path}" ]]; then
  echo "ERROR: Dockerfile not found: ${dockerfile_path}" >&2
  exit 1
fi

if [[ ! -f "${go_mod_path}" ]]; then
  echo "ERROR: go.mod not found: ${go_mod_path}" >&2
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

x_net_line="$(
  grep -E '^[[:space:]]*golang.org/x/net[[:space:]]+v[0-9]+\.[0-9]+\.[0-9]+' "${go_mod_path}" | head -n 1 || true
)"
if [[ -z "${x_net_line}" ]]; then
  echo "ERROR: unable to find golang.org/x/net version in ${go_mod_path}" >&2
  exit 1
fi

x_net_version="$(
  echo "${x_net_line}" | sed -E 's/.*(v[0-9]+\.[0-9]+\.[0-9]+).*/\1/'
)"
if ! version_ge "${x_net_version}" "v0.23.0"; then
  echo "ERROR: golang.org/x/net ${x_net_version} is below secure baseline for CVE-2023-44487 (requires >= v0.23.0)" >&2
  exit 1
fi

proxy_image_files=()
while IFS= read -r file; do
  [[ -n "${file}" ]] && proxy_image_files+=("${file}")
done < <(grep -R -l --include='*.yaml' --include='*.yml' 'image:.*kube-rbac-proxy' config charts 2>/dev/null || true)
if (( ${#proxy_image_files[@]} > 0 )); then
  missing_http2_disable=()
  for file in "${proxy_image_files[@]}"; do
    if ! grep -q -- '--http2-disable=true' "${file}"; then
      missing_http2_disable+=("${file}")
    fi
  done
  if (( ${#missing_http2_disable[@]} > 0 )); then
    echo "ERROR: kube-rbac-proxy image is present but --http2-disable=true is missing in:" >&2
    printf '  - %s\n' "${missing_http2_disable[@]}" >&2
    exit 1
  fi
elif [[ -f "${main_go_path}" ]]; then
  if ! grep -q 'WithAuthenticationAndAuthorization' "${main_go_path}"; then
    echo "ERROR: no kube-rbac-proxy sidecar detected and ${main_go_path} does not enable WithAuthenticationAndAuthorization" >&2
    exit 1
  fi
fi

echo "Security baseline checks passed:"
echo "  - Go toolchain: ${go_version}"
echo "  - golang.org/x/net: ${x_net_version}"
if (( ${#proxy_image_files[@]} > 0 )); then
  echo "  - kube-rbac-proxy HTTP/2 hardening: --http2-disable=true present"
else
  echo "  - kube-rbac-proxy sidecar: not used (controller-runtime authz filter active)"
fi
