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
"$script_dir/install-xcsift.sh"

swift build -c "$configuration" 2>&1 | xcsift -f toon -w
