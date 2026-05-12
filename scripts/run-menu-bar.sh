#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
launch_agent_label="com.block.qrgo.menubar"

configuration="debug"
if [[ $# -gt 0 ]]; then
    case "$1" in
        debug|release)
            configuration="$1"
            shift
            ;;
    esac
fi

stop_running_menu_bar() {
    /bin/launchctl bootout "gui/$(id -u)/$launch_agent_label" >/dev/null 2>&1 || true

    local pids=()
    local pid
    while IFS= read -r pid; do
        [[ -n "$pid" ]] && pids+=("$pid")
    done < <(pgrep -f "[q]rgo.*--menu-bar-agent" || true)

    if [[ ${#pids[@]} -eq 0 ]]; then
        return
    fi

    echo "Stopping existing QRGo menu bar app..." >&2
    kill "${pids[@]}" >/dev/null 2>&1 || true

    local remaining=()
    for _ in {1..20}; do
        remaining=()
        for pid in "${pids[@]}"; do
            if kill -0 "$pid" >/dev/null 2>&1; then
                remaining+=("$pid")
            fi
        done
        if [[ ${#remaining[@]} -eq 0 ]]; then
            return
        fi
        sleep 0.1
    done

    kill -9 "${remaining[@]}" >/dev/null 2>&1 || true
}

"$script_dir/install-xcsift.sh"
"$script_dir/build.sh" "$configuration"
stop_running_menu_bar

"$repo_root/.build/$configuration/qrgo" --menu-bar "$@"
