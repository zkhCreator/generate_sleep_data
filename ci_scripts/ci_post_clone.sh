#!/bin/zsh
# Purpose: Prepare the Tuist workspace for Xcode Cloud immediately after repository checkout.
# Responsibilities:
# - Resolve the repository root from Xcode Cloud or script location.
# - Install and activate mise when the CI image does not already have it on PATH.
# - Install the pinned toolchain and generate the Tuist workspace/project.
# - Print the resolved workspace path for Xcode Cloud logs.
# Inputs:
# - CI_PRIMARY_REPOSITORY_PATH or GITHUB_WORKSPACE (optional).
# - Script location as a fallback when CI variables are absent.
# Outputs:
# - Generated `generate_sleep_data.xcworkspace` and `.xcodeproj` under the repository root.
# Non-Goals:
# - Does not run tests.
# - Does not invoke xcodebuild directly.

set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"

resolve_repo_root() {
  local candidate=""
  local normalized=""
  local -a candidates=(
    "${CI_PRIMARY_REPOSITORY_PATH:-}"
    "${GITHUB_WORKSPACE:-}"
    "${script_dir}/.."
  )

  for candidate in "${candidates[@]}"; do
    [[ -z "$candidate" ]] && continue
    normalized="$(cd "$candidate" 2>/dev/null && pwd)" || continue

    if [[ -f "${normalized}/Project.swift" ]]; then
      printf '%s\n' "${normalized}"
      return 0
    fi
  done

  return 1
}

ensure_mise() {
  if command -v mise >/dev/null 2>&1; then
    return 0
  fi

  echo "[ci_post_clone] Installing mise"
  curl -fsSL https://mise.run | MISE_INSTALL_EXT=tar.gz sh
  export PATH="${HOME}/.local/bin:${PATH}"
}

if ! repo_root="$(resolve_repo_root)"; then
  echo "[ci_post_clone] Unable to resolve repository root"
  exit 1
fi

ensure_mise

if ! command -v mise >/dev/null 2>&1; then
  echo "[ci_post_clone] mise is unavailable after installation"
  exit 1
fi

echo "[ci_post_clone] repo_root=${repo_root}"
cd "${repo_root}"

mise install
eval "$(mise activate zsh --shims)"
mise x -- tuist generate

echo "[ci_post_clone] Workspace ready at ${repo_root}/generate_sleep_data.xcworkspace"
