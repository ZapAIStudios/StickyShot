#!/bin/zsh
# Builds StickyShot.app (Apple silicon + Intel) and a shareable zip in ./dist
set -e
cd "$(dirname "$0")"

APP=dist/StickyShot.app
rm -rf dist build
mkdir -p build "$APP/Contents/MacOS" "$APP/Contents/Resources"

# Some Command Line Tools installs ship a stale duplicate of SwiftBridging's modulemap,
# which breaks every AppKit build. Hide it with an overlay instead of editing system files.
OVERLAY=()
STALE=/Library/Developer/CommandLineTools/usr/include/swift/module.modulemap
if [ -f "$STALE" ] && [ -f "${STALE:h}/bridging.modulemap" ]; then
  : > build/empty.modulemap
  print -r -- "{\"version\":0,\"case-sensitive\":\"false\",\"roots\":[{\"type\":\"file\",\"name\":\"$STALE\",\"external-contents\":\"$PWD/build/empty.modulemap\"}]}" > build/overlay.yaml
  OVERLAY=(-vfsoverlay build/overlay.yaml -Xcc -ivfsoverlay -Xcc build/overlay.yaml)
fi

for arch in arm64 x86_64; do
  swiftc $OVERLAY -O -swift-version 5 -target "$arch-apple-macos13.0" \
    -framework AppKit -framework QuickLookThumbnailing -framework ServiceManagement \
    Sources/main.swift -o "build/StickyShot-$arch"
done
lipo -create build/StickyShot-arm64 build/StickyShot-x86_64 -output "$APP/Contents/MacOS/StickyShot"

cp Resources/Info.plist "$APP/Contents/Info.plist"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"

# Ad-hoc signature: free, but macOS asks people to confirm the first launch.
codesign --force --deep --sign - "$APP"

(cd dist && ditto -c -k --keepParent StickyShot.app StickyShot.zip)
echo "Built $APP and dist/StickyShot.zip"
