#!/usr/bin/env bash
set -euo pipefail

GRAPHIFY_VERSION="0.9.50"

if command -v uv >/dev/null 2>&1; then
  uv tool install "graphifyy==${GRAPHIFY_VERSION}" --force
elif command -v pipx >/dev/null 2>&1; then
  pipx install "graphifyy==${GRAPHIFY_VERSION}" --force
else
  python3 -m pip install --user --disable-pip-version-check "graphifyy==${GRAPHIFY_VERSION}"
  export PATH="${HOME}/.local/bin:${PATH}"
fi

command -v graphify >/dev/null 2>&1 || {
  echo "graphify is not on PATH after installation" >&2
  exit 1
}

graphify install --project --platform codex
graphify update .

printf '\nGraphify is ready. Committable outputs live in graphify-out/.\n'
