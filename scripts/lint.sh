#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
cd "$repo_root"

if ! command -v swiftlint >/dev/null 2>&1; then
    if ! command -v brew >/dev/null 2>&1; then
        echo "SwiftLint is required but Homebrew is not installed." >&2
        echo "Install SwiftLint manually: https://github.com/realm/SwiftLint" >&2
        exit 69
    fi

    echo "SwiftLint not found. Installing with Homebrew..." >&2
    if ! HOMEBREW_NO_ENV_HINTS=1 HOMEBREW_NO_INSTALL_CLEANUP=1 brew install --quiet swiftlint >/dev/null 2>&1; then
        echo "Failed to install SwiftLint with Homebrew. Run 'brew install swiftlint' for details." >&2
        exit 69
    fi
fi

swiftlint lint --strict --quiet
