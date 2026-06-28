#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This script only runs on macOS." >&2
  exit 1
fi

load_env_file() {
  local path="$1"
  if [[ -f "${path}" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "${path}"
    set +a
  fi
}

load_env_file "${REPO_ROOT}/.env"
load_env_file "${REPO_ROOT}/.env.local"

load_env_value_from_file() {
  local key="$1"
  local value="${!key:-}"

  if [[ -n "${value}" && -f "${value}" ]]; then
    export "${key}=$(<"${value}")"
  fi
}

load_env_value_from_file TAURI_SIGNING_PRIVATE_KEY
load_env_value_from_file HEADROOM_UPDATER_PUBLIC_KEY

unset APPLE_SIGNING_IDENTITY

if [[ -z "${HEADROOM_UPDATER_PUBLIC_KEY:-}" || -z "${HEADROOM_UPDATER_ENDPOINTS:-}" ]]; then
  echo "Warning: HEADROOM_UPDATER_PUBLIC_KEY or HEADROOM_UPDATER_ENDPOINTS is missing." >&2
  echo "The DMG will still build, but in-app update checks will be disabled in that app build." >&2
fi

export CI="${CI:-true}"

cd "${REPO_ROOT}"
./scripts/verify-release.sh

if [[ -n "${TARGET:-}" ]]; then
  npx tauri build --bundles dmg --ci --target "${TARGET}"
else
  npx tauri build --bundles dmg --ci
fi

rename_built_dmg() {
  local version="$1"
  local bundle_dir="${REPO_ROOT}/src-tauri/target"

  if [[ -n "${TARGET:-}" ]]; then
    bundle_dir="${bundle_dir}/${TARGET}"
  fi

  bundle_dir="${bundle_dir}/release/bundle/dmg"

  if [[ ! -d "${bundle_dir}" ]]; then
    echo "Expected DMG output directory not found: ${bundle_dir}" >&2
    exit 1
  fi

  shopt -s nullglob
  local dmgs=("${bundle_dir}"/*.dmg)
  shopt -u nullglob

  if [[ ${#dmgs[@]} -eq 0 ]]; then
    echo "No DMG artifact found in ${bundle_dir}." >&2
    exit 1
  fi

  local desired_path="${bundle_dir}/Headroom_${version}.dmg"
  local source_path=""

  for candidate in "${dmgs[@]}"; do
    if [[ "${candidate}" != "${desired_path}" ]]; then
      source_path="${candidate}"
      break
    fi
  done

  if [[ -z "${source_path}" ]]; then
    source_path="${desired_path}"
  fi

  if [[ "${source_path}" != "${desired_path}" ]]; then
    mv -f "${source_path}" "${desired_path}"

    if [[ -f "${source_path}.sig" ]]; then
      mv -f "${source_path}.sig" "${desired_path}.sig"
    fi
  fi

  echo "DMG ready at ${desired_path}"
}

APP_VERSION="$(node -p "require('./package.json').version")"
rename_built_dmg "${APP_VERSION}"
