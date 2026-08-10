#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "This script must run on macOS." >&2
    exit 1
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
template_app="$repo_root/dist/LoopBar.app"
version_file="$repo_root/Sources/Resources/version.txt"
version="$(tr -d '[:space:]' < "$version_file")"
output_dmg="${1:-$repo_root/dist/LoopBar-$version.dmg}"
signing_identity="${CODE_SIGN_IDENTITY:--}"

if [[ ! -d "$template_app" ]]; then
    echo "Missing app template: $template_app" >&2
    exit 1
fi

cd "$repo_root"
swift build -c release
bin_dir="$(swift build -c release --show-bin-path)"
built_executable="$bin_dir/LoopBar"

if [[ ! -x "$built_executable" ]]; then
    echo "Release executable was not created: $built_executable" >&2
    exit 1
fi

work_parent="${TMPDIR:-/tmp}"
work_parent="${work_parent%/}"
work_dir="$(mktemp -d "$work_parent/loopbar-package.XXXXXX")"
cleanup() {
    case "$work_dir" in
        "$work_parent"/loopbar-package.*) rm -rf -- "$work_dir" ;;
        *) echo "Refusing to remove unexpected temporary path: $work_dir" >&2 ;;
    esac
}
trap cleanup EXIT

dmg_root="$work_dir/dmg"
staged_app="$dmg_root/LoopBar.app"
mkdir -p "$dmg_root"
ditto "$template_app" "$staged_app"
install -m 755 "$built_executable" "$staged_app/Contents/MacOS/LoopBar"
install -m 644 \
    "$repo_root/Sources/Resources/NotificationLogo.png" \
    "$staged_app/Contents/Resources/NotificationLogo.png"

resource_bundle="$bin_dir/LoopBar_LoopBar.bundle"
if [[ -d "$resource_bundle" ]]; then
    ditto "$resource_bundle" "$staged_app/LoopBar_LoopBar.bundle"
fi

/usr/libexec/PlistBuddy \
    -c "Set :CFBundleShortVersionString $version" \
    "$staged_app/Contents/Info.plist"

if [[ "$signing_identity" == "-" ]]; then
    codesign --force --deep --sign - "$staged_app"
else
    codesign --force --deep --options runtime --timestamp \
        --sign "$signing_identity" "$staged_app"
fi
codesign --verify --deep --strict --verbose=2 "$staged_app"

if ! strings "$staged_app/Contents/MacOS/LoopBar" | grep -F "Launch at Login" >/dev/null; then
    echo "Packaged executable does not contain the Launch at Login feature." >&2
    exit 1
fi

ln -s /Applications "$dmg_root/Applications"
mkdir -p "$(dirname "$output_dmg")"
hdiutil create \
    -volname "LoopBar $version" \
    -srcfolder "$dmg_root" \
    -ov \
    -format UDZO \
    "$output_dmg"

echo "Created $output_dmg"
echo "Install by dragging LoopBar.app onto the Applications shortcut before opening it."
