#!/bin/bash
# Builds QuadStatus.app. Pass --install to drop it in ~/Applications, start it at login and launch it.
set -euo pipefail
cd "$(dirname "$0")"

NAME="QuadStatus"
OUT="build.noindex"
APP="$OUT/$NAME.app"
BUNDLE_ID="io.github.chocholous.quadstatus"
VERSION="$(plutil -extract CFBundleShortVersionString raw Resources/Info.plist)"

# Universal, so the same bundle runs on Apple silicon and Intel.
# QUADSTATUS_ARCHS narrows it, e.g. to "arm64" on a CI runner without Rosetta.
ARCHS=()
for arch in ${QUADSTATUS_ARCHS:-arm64 x86_64}; do ARCHS+=(--arch "$arch"); done

if [[ "${1:-}" == "--icon" ]]; then
  echo "==> Generating Resources/AppIcon.icns"
  SET="$(mktemp -d)/AppIcon.iconset"
  swiftc -O Sources/$NAME/StatusIcon.swift Sources/$NAME/BatteryMonitor.swift \
      Sources/$NAME/VolumeMonitor.swift Sources/$NAME/NetworkMonitor.swift \
      Tools/GenerateIcon.swift -o /tmp/quadstatus-icon
  /tmp/quadstatus-icon "$SET"
  iconutil -c icns "$SET" -o Resources/AppIcon.icns
  rm -rf "$(dirname "$SET")" /tmp/quadstatus-icon
  echo "Done: Resources/AppIcon.icns"
  exit 0
fi

if [[ "${1:-}" == "--previews" ]]; then
  echo "==> Rendering docs/preview/*.png"
  TOOL="$(mktemp -d)/render-previews"
  swiftc -O Sources/$NAME/StatusIcon.swift Sources/$NAME/BatteryMonitor.swift \
      Sources/$NAME/VolumeMonitor.swift Sources/$NAME/NetworkMonitor.swift \
      Tools/RenderPreviews.swift -o "$TOOL"
  "$TOOL" docs/preview
  /usr/bin/trash "$(dirname "$TOOL")"
  exit 0
fi

# The icon is generated from the badge code; regenerate it if it went missing.
[[ -f Resources/AppIcon.icns ]] || "$0" --icon

echo "==> Building (universal)"
swift build -c release --scratch-path .build.noindex "${ARCHS[@]}"
BIN="$(swift build -c release --scratch-path .build.noindex "${ARCHS[@]}" --show-bin-path)/$NAME"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
# Build products live in *.noindex directories: Spotlight skips those by name.
# (.metadata_never_index only works at a volume root, not per directory.)
cp "$BIN" "$APP/Contents/MacOS/$NAME"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"

echo "==> Signing (ad-hoc; fine for local use)"
codesign --force --sign - --identifier "$BUNDLE_ID" "$APP"

if [[ "${1:-}" == "--dmg" ]]; then
  echo "==> Building $NAME-$VERSION.dmg"
  STAGE="$(mktemp -d)"
  # ditto + xattr: copying with cp picks up Finder metadata that invalidates the
  # signature once it is inside the image.
  ditto "$APP" "$STAGE/$NAME.app"
  xattr -cr "$STAGE/$NAME.app"
  ln -s /Applications "$STAGE/Applications"
  rm -f "$OUT/$NAME-$VERSION.dmg"
  hdiutil create -volname "$NAME" -srcfolder "$STAGE" -ov -format UDZO \
      "$OUT/$NAME-$VERSION.dmg" >/dev/null
  rm -rf "$STAGE"
  echo "Done: $OUT/$NAME-$VERSION.dmg"
  exit 0
fi

if [[ "${1:-}" == "--install" ]]; then
  DEST="$HOME/Applications/$NAME.app"
  echo "==> Installing to $DEST"
  pkill -x "$NAME" || true
  mkdir -p "$HOME/Applications"
  [[ -e "$DEST" ]] && /usr/bin/trash "$DEST"
  ditto "$APP" "$DEST"
  # Starts it at login (a LaunchAgent pointing at this copy; see LoginAgent.swift).
  "$DEST/Contents/MacOS/$NAME" --register-login
  # Opening straight after replacing the bundle races LaunchServices (error -609),
  # so register it explicitly and give it a moment.
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
      -f "$DEST" || true
  sleep 1
  # --register-login has usually started it already (RunAtLoad).
  pgrep -x "$NAME" >/dev/null || open "$DEST" || { sleep 2; open "$DEST"; }
  echo "Launched — look at the right side of the menu bar."
else
  echo "Done: $APP"
  echo "Try it:  open $APP        Install:  ./build.sh --install        Disk image:  ./build.sh --dmg"
fi
