#!/usr/bin/env bash
set -euo pipefail

if command -v xcsift >/dev/null 2>&1; then
    exit 0
fi

if ! command -v brew >/dev/null 2>&1; then
    echo "xcsift is required but Homebrew is not installed." >&2
    echo "Install xcsift manually: https://github.com/ldomaradzki/xcsift" >&2
    exit 69
fi

echo "xcsift not found. Installing with Homebrew..." >&2
if ! HOMEBREW_NO_ENV_HINTS=1 HOMEBREW_NO_INSTALL_CLEANUP=1 brew install --quiet xcsift >/dev/null 2>&1; then
    echo "Failed to install xcsift with Homebrew. Run 'brew install xcsift' for details." >&2
    exit 69
fi
