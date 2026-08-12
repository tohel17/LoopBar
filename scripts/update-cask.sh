#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
cask_file="$repo_root/Casks/loopbar.rb"
version="${1:-}"
dmg="${2:-}"

usage() {
    echo "Usage: $0 VERSION PATH_TO_DMG" >&2
}

if [[ -z "$version" || -z "$dmg" ]]; then
    usage
    exit 1
fi

if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([._-][0-9A-Za-z]+)*$ ]]; then
    echo "Invalid release version: $version" >&2
    exit 1
fi

if [[ ! -f "$dmg" ]]; then
    echo "DMG does not exist: $dmg" >&2
    exit 1
fi

if [[ ! -f "$cask_file" ]]; then
    echo "Cask does not exist: $cask_file" >&2
    exit 1
fi

checksum="$(shasum -a 256 "$dmg" | awk '{ print $1 }')"
work_parent="${TMPDIR:-/tmp}"
work_parent="${work_parent%/}"
updated_cask="$(mktemp "$work_parent/loopbar-cask.XXXXXX")"
cleanup() {
    rm -f -- "$updated_cask"
}
trap cleanup EXIT

awk -v version="$version" -v checksum="$checksum" '
    /^  version "/ {
        print "  version \"" version "\""
        versions++
        next
    }
    /^  sha256 "/ {
        print "  sha256 \"" checksum "\""
        checksums++
        next
    }
    { print }
    END {
        if (versions != 1 || checksums != 1) exit 1
    }
' "$cask_file" > "$updated_cask"

install -m 644 "$updated_cask" "$cask_file"
echo "Updated Casks/loopbar.rb to $version ($checksum)"
