#!/usr/bin/env bash
# Publishes the version in Resources/Info.plist: builds the disk image, tags the
# commit, creates the GitHub release and points the Homebrew tap's cask at it.
#
#   Tools/release.sh            do it
#   Tools/release.sh --dry-run  build and print what would be published
#
# QUADSTATUS_REPO  GitHub repository of the app   (default chocholous/QuadStatus)
# QUADSTATUS_TAP   local checkout of the tap repo (default ../homebrew-tap)
set -euo pipefail
cd "$(dirname "$0")/.."

REPO="${QUADSTATUS_REPO:-chocholous/QuadStatus}"
TAP="${QUADSTATUS_TAP:-../homebrew-tap}"
CASK="$TAP/Casks/quadstatus.rb"
VERSION="$(plutil -extract CFBundleShortVersionString raw Resources/Info.plist)"
TAG="v$VERSION"
DMG="build.noindex/QuadStatus-$VERSION.dmg"
DRY=false
[[ "${1:-}" == "--dry-run" ]] && DRY=true

fail() { echo "release: $*" >&2; exit 1; }

[[ -z "$(git status --porcelain)" ]] || fail "the working tree has uncommitted changes"
[[ "$(git branch --show-current)" == "main" ]] || fail "release from main"
git fetch --tags origin
[[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] || fail "main is not pushed / not up to date"
git rev-parse -q --verify "refs/tags/$TAG" >/dev/null && fail "$TAG already exists"
[[ -f "$CASK" ]] || fail "no cask at $CASK (set QUADSTATUS_TAP)"
[[ -z "$(git -C "$TAP" status --porcelain)" ]] || fail "the tap has uncommitted changes"

./build.sh --dmg
SHA="$(shasum -a 256 "$DMG" | cut -d' ' -f1)"
echo "==> $DMG"
echo "    sha256 $SHA"

NOTES="$(mktemp)"
cat > "$NOTES" <<EOF
QuadStatus $VERSION

Install: \`brew install --cask chocholous/tap/quadstatus\`, or open the disk image and drag
QuadStatus into Applications.

Not yet signed with an Apple Developer ID or notarized: on first launch open
System Settings → Privacy & Security → Open Anyway.

SHA-256 of QuadStatus-$VERSION.dmg: \`$SHA\`
EOF

if $DRY; then
  echo "==> Dry run. Would tag $TAG, release $REPO with these notes, and set the cask to $VERSION / $SHA:"
  cat "$NOTES"
  /usr/bin/trash "$NOTES"
  exit 0
fi

echo "==> Tagging $TAG and creating the release"
git tag -a "$TAG" -m "QuadStatus $VERSION"
git push origin "$TAG"
gh release create "$TAG" "$DMG" --repo "$REPO" --title "QuadStatus $VERSION" --notes-file "$NOTES"
/usr/bin/trash "$NOTES"

echo "==> Updating the cask"
sed -i '' -e "s/^  version \".*\"/  version \"$VERSION\"/" -e "s/^  sha256 \".*\"/  sha256 \"$SHA\"/" "$CASK"
git -C "$TAP" add Casks/quadstatus.rb
git -C "$TAP" commit -m "quadstatus $VERSION"
git -C "$TAP" push

echo "Done: brew update && brew upgrade --cask quadstatus"
