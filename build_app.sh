#!/bin/zsh
# Construit mSLICE.app : ffmpeg / ffprobe embarqués (Contents/Helpers), extension Finder (PlugIns), signature locale stable, installation.
#   DEV=1        : édition de développement « mSLICE DEV.app » (bundle id …dev, données à part), dans le dossier du projet, non installée.
#   NO_INSTALL=1 : ne pas installer.   UNIVERSAL=1 : arm64 + x86_64 (publication).   VERSION=x.y.z : version.
set -euo pipefail
cd "$(dirname "$0")"
TOOLS=/Volumes/SKYRIM/TOOLS
VERSION="${VERSION:-$( (git tag --list 'v[0-9]*' --sort=-v:refname 2>/dev/null || true) | head -1 | sed 's/^v//')}"
VERSION="${VERSION:-0.1.0}"
BUILD="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
if [ -n "${DEV:-}" ]; then APP="mSLICE DEV.app"; ID="fr.stephan.mslice.dev"; NAME="mSLICE DEV"; SCHEME="mslice-dev"; OPT=(-Onone -g); else APP="mSLICE.app"; ID="fr.stephan.mslice"; NAME="mSLICE"; SCHEME="mslice"; OPT=(-O); fi
DEST="${MSLICE_INSTALL_DIR:-$HOME/Applications/Applications Personnelles}"

# fichiers communs : Socle et mise à jour automatique, recopiés à chaque build
[ -f "$TOOLS/DESIGN/Socle/swift/Socle.swift" ] && cp "$TOOLS/DESIGN/Socle/swift/Socle.swift" Sources/Socle.swift
for f in Updater.swift UpdaterView.swift; do [ -f "$TOOLS/MAC/_tools/shared/$f" ] && cp "$TOOLS/MAC/_tools/shared/$f" Sources/$f; done
./ffmpeg/build_ffmpeg.sh
FF="$HOME/Library/Caches/mSLICE-ffmpeg/out/bin"

rm -rf "${APP:?}" build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Helpers" "$APP/Contents/PlugIns/FinderExt.appex/Contents/MacOS" build
ARCHS=(arm64); [ -n "${UNIVERSAL:-}" ] && ARCHS=(arm64 x86_64)
for arch in $ARCHS; do
  swiftc $OPT -swift-version 5 -target $arch-apple-macos14.0 -o build/mSLICE-$arch Sources/*.swift
  swiftc $OPT -swift-version 5 -target $arch-apple-macos14.0 -parse-as-library -application-extension -module-name FinderExt -framework FinderSync \
    -Xlinker -e -Xlinker _NSExtensionMain -o build/FinderExt-$arch FinderExt/*.swift
done
if [ ${#ARCHS[@]} -gt 1 ]; then
  lipo -create build/mSLICE-arm64 build/mSLICE-x86_64 -output "$APP/Contents/MacOS/mSLICE"
  lipo -create build/FinderExt-arm64 build/FinderExt-x86_64 -output "$APP/Contents/PlugIns/FinderExt.appex/Contents/MacOS/FinderExt"
else
  cp build/mSLICE-arm64 "$APP/Contents/MacOS/mSLICE"; cp build/FinderExt-arm64 "$APP/Contents/PlugIns/FinderExt.appex/Contents/MacOS/FinderExt"
fi
cp "$FF/ffmpeg" "$FF/ffprobe" "$APP/Contents/Helpers/"

sed -e "s/__ID__/$ID/g" -e "s/__NAME__/$NAME/g" -e "s/__VERSION__/$VERSION/g" -e "s/__BUILD__/$BUILD/g" -e "s/__SCHEME__/$SCHEME/g" Resources/Info.plist > "$APP/Contents/Info.plist"
sed -e "s/__ID__/$ID/g" -e "s/__VERSION__/$VERSION/g" -e "s/__BUILD__/$BUILD/g" -e "s/__SCHEME__/$SCHEME/g" Resources/Finder-Info.plist > "$APP/Contents/PlugIns/FinderExt.appex/Contents/Info.plist"
[ -f assets/mSLICE.icns ] && cp assets/mSLICE.icns "$APP/Contents/Resources/AppIcon.icns"
for l in Resources/*.lproj; do cp -R "$l" "$APP/Contents/Resources/"; done
# licences des composants embarqués (ffmpeg LGPL, LAME, mpg123, Opus, libvpx) et de l'appli
mkdir -p "$APP/Contents/Resources/Licenses"; cp licenses/* LICENSE THIRD_PARTY_LICENSES.md "$APP/Contents/Resources/Licenses/"
rm -rf build

# Signature : tout (ffmpeg, extension), puis l'extension avec ses droits (sandbox), puis l'appli pour sceller l'extension finale.
SIGN="$TOOLS/MAC/_tools/sign_app.sh"
if [ -x "$SIGN" ]; then
  "$SIGN" "$APP"
  SIGN_ENTITLEMENTS="$PWD/Resources/Finder.entitlements" SIGN_NO_DEEP=1 "$SIGN" "$APP/Contents/PlugIns/FinderExt.appex"
  SIGN_NO_DEEP=1 "$SIGN" "$APP"
else codesign --force --deep -s - "$APP"; fi
echo "OK : $APP"

if [ -z "${DEV:-}" ] && [ -z "${NO_INSTALL:-}" ]; then
  mkdir -p "$DEST"
  osascript -e "tell application id \"$ID\" to quit" 2>/dev/null || true
  rm -rf "${DEST:?}/${APP:?}"
  cp -R "$APP" "$DEST/"
  echo "Installée : $DEST/$APP"
fi
