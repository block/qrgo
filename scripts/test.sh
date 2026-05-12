#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
cd "$repo_root"

"$script_dir/install-xcsift.sh"

swift test "$@" 2>&1 | xcsift -f toon -w
