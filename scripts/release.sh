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

usage() {
    cat <<'EOF'
Build, Developer ID-sign, notarize, staple, and validate a LoopBar DMG.

Usage:
  bash scripts/release.sh [output.dmg]

Optional environment variables:
  CODE_SIGN_IDENTITY       Developer ID certificate name or SHA-1 hash.
                           Auto-detected when exactly one is installed.
  NOTARY_KEYCHAIN_PROFILE  notarytool Keychain profile (default: LoopBar).

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

echo "[1/7] Synchronizing app version and incrementing bundle version"
"$script_dir/sync-version.sh"

echo "[2/7] Building and signing LoopBar.app"
CODE_SIGN_IDENTITY="$signing_identity" \
    "$script_dir/build-dmg.sh" "$output_dmg"

echo "[3/7] Signing the DMG"
codesign --force --timestamp --sign "$signing_identity" "$output_dmg"
codesign --verify --verbose=2 "$output_dmg"

echo "[4/7] Submitting to Apple's notary service"
xcrun notarytool submit "$output_dmg" \
    --keychain-profile "$notary_profile" \
    --wait

echo "[5/7] Stapling and validating the notarization ticket"
xcrun stapler staple "$output_dmg"
xcrun stapler validate "$output_dmg"

echo "[6/7] Assessing the DMG with Gatekeeper"
spctl --assess \
    --type open \
    --context context:primary-signature \
    --verbose=4 \
    "$output_dmg"

echo "[7/7] Calculating SHA-256"
checksum="$(shasum -a 256 "$output_dmg" | awk '{ print $1 }')"

echo
echo "Release ready: $output_dmg"
echo "SHA-256: $checksum"
