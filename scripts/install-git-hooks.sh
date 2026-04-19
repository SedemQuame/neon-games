#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "${REPO_ROOT}" ]]; then
  echo "Failed to determine repository root." >&2
  exit 1
fi

HOOK_PATH="${REPO_ROOT}/.githooks/pre-push"
if [[ ! -f "${HOOK_PATH}" ]]; then
  echo "Missing hook file: ${HOOK_PATH}" >&2
  exit 1
fi

chmod +x "${HOOK_PATH}"
git -C "${REPO_ROOT}" config core.hooksPath .githooks

echo "Installed git hooks from .githooks"
echo "Configured core.hooksPath=.githooks"
