#!/bin/zsh
# Purpose: Ensure Xcode Cloud enters the configured xcodebuild step with a ready Tuist workspace.
# Responsibilities:
# - Resolve the repository root and expected workspace path.
# - Activate mise if it is already installed by the post-clone step.
# - Regenerate the Tuist workspace only when the expected workspace is missing.
# - Print the workspace and scheme used by the workflow for easier debugging.
# Inputs:
# - CI_PRIMARY_REPOSITORY_PATH or GITHUB_WORKSPACE (optional).
# - CI_SCHEME or CI_XCODE_SCHEME (optional, defaults to generate_sleep_data).
# Outputs:
# - A verified or regenerated `generate_sleep_data.xcworkspace`.
# Non-Goals:
# - Does not run tests.
# - Does not invoke xcodebuild directly.

set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
scheme="${CI_SCHEME:-${CI_XCODE_SCHEME:-generate_sleep_data}}"

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

if ! repo_root="$(resolve_repo_root)"; then
  echo "[ci_pre_xcodebuild] Unable to resolve repository root"
  exit 1
fi

workspace_path="${repo_root}/generate_sleep_data.xcworkspace"
echo "[ci_pre_xcodebuild] repo_root=${repo_root}"
echo "[ci_pre_xcodebuild] scheme=${scheme}"
echo "[ci_pre_xcodebuild] workspace_path=${workspace_path}"

cd "${repo_root}"

if command -v mise >/dev/null 2>&1; then
  eval "$(mise activate zsh --shims)"
fi

if [[ ! -d "${workspace_path}" ]]; then
  if ! command -v mise >/dev/null 2>&1; then
    echo "[ci_pre_xcodebuild] Workspace is missing and mise is unavailable"
    exit 1
  fi

  echo "[ci_pre_xcodebuild] Workspace missing. Regenerating Tuist workspace."
  mise x -- tuist generate
fi

echo "[ci_pre_xcodebuild] Workspace is ready for Xcode Cloud."
