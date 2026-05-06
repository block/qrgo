#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <debug|release>" >&2
    exit 64
fi

configuration="$1"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"

case "$configuration" in
    debug|release)
        ;;
    *)
        echo "Invalid build configuration: $configuration" >&2
        echo "Usage: $0 <debug|release>" >&2
        exit 64
        ;;
esac

cd "$repo_root"
"$script_dir/lint.sh"

if ! command -v xcsift >/dev/null 2>&1; then
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
fi

swift build -c "$configuration" 2>&1 | xcsift -f toon -w
