#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
version_file="$repo_root/Sources/Resources/version.txt"
info_plist="$repo_root/dist/LoopBar.app/Contents/Info.plist"
version=$(tr -d '[:space:]' < "$version_file")

case "$version" in
    ""|*[!0-9A-Za-z._-]*)
        echo "Invalid version in $version_file: $version" >&2
        exit 1
        ;;
esac

if [ ! -f "$info_plist" ]; then
    echo "Packaged Info.plist not found: $info_plist" >&2
    exit 1
fi

# Read current bundle version and increment it
bundle_version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$info_plist")
bundle_version=$((bundle_version + 1))

/usr/libexec/PlistBuddy \
    -c "Set :CFBundleShortVersionString $version" \
    -c "Set :CFBundleVersion $bundle_version" \
    "$info_plist"

echo "Set packaged LoopBar version to $version (bundle version: $bundle_version)"
