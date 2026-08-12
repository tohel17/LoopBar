#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "This script must run on macOS." >&2
    exit 1
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
version_file="$repo_root/Sources/Resources/version.txt"
version="$(tr -d '[:space:]' < "$version_file")"
output_dmg="${1:-$repo_root/dist/LoopBar-$version.dmg}"
notary_profile="${NOTARY_KEYCHAIN_PROFILE:-LoopBar}"
sparkle_account="${SPARKLE_KEY_ACCOUNT:-LoopBar}"

usage() {
    cat <<'EOF'
Build, Developer ID-sign, notarize, staple, and validate a LoopBar DMG.

Usage:
  bash scripts/release.sh [output.dmg]

Optional environment variables:
  CODE_SIGN_IDENTITY       Developer ID certificate name or SHA-1 hash.
                           Auto-detected when exactly one is installed.
  NOTARY_KEYCHAIN_PROFILE  notarytool Keychain profile (default: LoopBar).
  SPARKLE_KEY_ACCOUNT      Sparkle signing-key account (default: LoopBar).

One-time setup:
  xcrun notarytool store-credentials "LoopBar" \
    --apple-id "you@example.com" --team-id "TEAMID"
EOF
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    usage
    exit 0
fi

if [[ ! -f "$version_file" || -z "$version" ]]; then
    echo "Missing or empty version file: $version_file" >&2
    exit 1
fi

if [[ "$output_dmg" != *.dmg ]]; then
    echo "Release output must use the .dmg extension: $output_dmg" >&2
    exit 1
fi

if ! grep -F "## $version " "$repo_root/CHANGELOG.md" >/dev/null; then
    echo "CHANGELOG.md has no release section for version $version." >&2
    echo "Rename the Unreleased section before starting the notarization run." >&2
    exit 1
fi

signing_identity="${CODE_SIGN_IDENTITY:-}"
if [[ -z "$signing_identity" ]]; then
    identities=()
    while IFS= read -r identity_hash; do
        if [[ -n "$identity_hash" ]]; then
            identities+=("$identity_hash")
        fi
    done < <(
        security find-identity -v -p codesigning \
            | awk '/"Developer ID Application:/ { print $2 }'
    )

    case "${#identities[@]}" in
        0)
            echo "No valid Developer ID Application identity was found." >&2
            echo "Install one in Keychain Access before releasing." >&2
            exit 1
            ;;
        1)
            signing_identity="${identities[0]}"
            ;;
        *)
            echo "Multiple Developer ID Application identities were found:" >&2
            printf '  %s\n' "${identities[@]}" >&2
            echo "Set CODE_SIGN_IDENTITY to the intended certificate hash." >&2
            exit 1
            ;;
    esac
fi

echo "[1/8] Synchronizing app version and incrementing bundle version"
"$script_dir/sync-version.sh"

echo "[2/8] Building and signing LoopBar.app"
CODE_SIGN_IDENTITY="$signing_identity" \
    "$script_dir/build-dmg.sh" "$output_dmg"

generate_keys="$repo_root/.build/artifacts/sparkle/Sparkle/bin/generate_keys"
if [[ ! -x "$generate_keys" ]]; then
    echo "Missing Sparkle tool: $generate_keys" >&2
    exit 1
fi
configured_public_key="$(
    /usr/libexec/PlistBuddy -c "Print :SUPublicEDKey" \
        "$repo_root/dist/LoopBar.app/Contents/Info.plist"
)"
keychain_public_key="$("$generate_keys" --account "$sparkle_account" -p)"
if [[ "$configured_public_key" != "$keychain_public_key" ]]; then
    echo "The Sparkle key in Info.plist does not match Keychain account '$sparkle_account'." >&2
    echo "Refusing to publish an update that installed apps cannot verify." >&2
    exit 1
fi

echo "[3/8] Signing the DMG"
codesign --force --timestamp --sign "$signing_identity" "$output_dmg"
codesign --verify --verbose=2 "$output_dmg"

echo "[4/8] Submitting to Apple's notary service"
xcrun notarytool submit "$output_dmg" \
    --keychain-profile "$notary_profile" \
    --wait

echo "[5/8] Stapling and validating the notarization ticket"
xcrun stapler staple "$output_dmg"
xcrun stapler validate "$output_dmg"

echo "[6/8] Assessing the DMG with Gatekeeper"
spctl --assess \
    --type open \
    --context context:primary-signature \
    --verbose=4 \
    "$output_dmg"

echo "[7/8] Calculating SHA-256 and updating the Homebrew cask"
checksum="$(shasum -a 256 "$output_dmg" | awk '{ print $1 }')"
checksum_file="$output_dmg.sha256"
printf '%s  %s\n' "$checksum" "$(basename "$output_dmg")" > "$checksum_file"
"$script_dir/update-cask.sh" "$version" "$output_dmg"

echo "[8/8] Signing the Sparkle update and generating appcast.xml"
generate_appcast="$repo_root/.build/artifacts/sparkle/Sparkle/bin/generate_appcast"
if [[ ! -x "$generate_appcast" ]]; then
    echo "Missing Sparkle tool: $generate_appcast" >&2
    echo "Run 'swift package resolve' and try again." >&2
    exit 1
fi

work_parent="${TMPDIR:-/tmp}"
work_parent="${work_parent%/}"
appcast_work_dir="$(mktemp -d "$work_parent/loopbar-appcast.XXXXXX")"
cleanup_appcast_work_dir() {
    case "$appcast_work_dir" in
        "$work_parent"/loopbar-appcast.*) rm -rf -- "$appcast_work_dir" ;;
        *) echo "Refusing to remove unexpected temporary path: $appcast_work_dir" >&2 ;;
    esac
}
trap cleanup_appcast_work_dir EXIT

cp "$output_dmg" "$appcast_work_dir/"
release_archive_name="$(basename "$output_dmg" .dmg)"
release_notes="$appcast_work_dir/$release_archive_name.md"
awk -v version="$version" '
    /^## / {
        if (found) exit
        if (index($0, "## " version " ") == 1) found = 1
    }
    found { print }
' "$repo_root/CHANGELOG.md" > "$release_notes"

"$generate_appcast" \
    --account "$sparkle_account" \
    --download-url-prefix "https://github.com/tohel17/LoopBar/releases/download/$version/" \
    --link "https://github.com/tohel17/LoopBar/releases/tag/$version" \
    --embed-release-notes \
    --maximum-versions 1 \
    -o "$repo_root/appcast.xml" \
    "$appcast_work_dir"
xmllint --noout "$repo_root/appcast.xml"

echo
echo "Release ready: $output_dmg"
echo "SHA-256: $checksum"
echo "Checksum file: $checksum_file"
echo "Homebrew cask: $repo_root/Casks/loopbar.rb"
echo "Sparkle feed: $repo_root/appcast.xml"
echo
echo "Publish the DMG and checksum on GitHub under tag $version, then commit"
echo "and push appcast.xml and Casks/loopbar.rb so installed copies can update."
