#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
    echo "Usage: $0 <debug|release> [output-app-path]" >&2
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
        echo "Usage: $0 <debug|release> [output-app-path]" >&2
        exit 64
        ;;
esac

if [[ "${QRGO_SKIP_BUILD:-0}" != "1" ]]; then
    "$script_dir/build.sh" "$configuration"
fi

binary_path="$repo_root/.build/$configuration/qrgo"
if [[ ! -x "$binary_path" ]]; then
    echo "Expected executable at $binary_path. Run scripts/build.sh $configuration first." >&2
    exit 1
fi

version="${QRGO_APP_VERSION:-${GITHUB_REF_NAME:-}}"
if [[ -z "$version" ]]; then
    version="$(git -C "$repo_root" describe --tags --abbrev=0 2>/dev/null || echo "0.0.0")"
fi
version="${version#v}"

app_path="${2:-$repo_root/.build/$configuration/QRGo.app}"
contents_path="$app_path/Contents"
macos_path="$contents_path/MacOS"
resources_path="$contents_path/Resources"

rm -rf "$app_path"
mkdir -p "$macos_path" "$resources_path"

cp "$repo_root/Packaging/QRGo.app/Info.plist" "$contents_path/Info.plist"
cp "$repo_root/Packaging/QRGo.app/QRGo.icns" "$resources_path/QRGo.icns"
cp "$binary_path" "$macos_path/QRGo"
chmod 755 "$macos_path/QRGo"

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$contents_path/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $version" "$contents_path/Info.plist"
plutil -lint "$contents_path/Info.plist" >/dev/null

echo "$app_path"
