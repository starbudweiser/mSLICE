#!/bin/bash
# Publie une version de mSLICE : compile (Apple Silicon, ffmpeg embarqué), signe Developer ID, notarise, agrafe, crée la release GitHub vX.Y.Z.
# L'appli installée se met à jour toute seule depuis cette release (Updater.swift).
# Usage : ./release.sh 1.0.0      (notes : _tools/changelogs/mSLICE_<version>.txt, 4 langues obligatoires)
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${1:?Usage : ./release.sh <version>}"
TAG="v$VERSION"
TOOLS=/Volumes/SKYRIM/TOOLS/MAC/_tools
[ -z "$(git status --porcelain --untracked-files=no)" ] || { echo "Modifications non commitées : commitez d'abord." >&2; exit 1; }
if git rev-parse "$TAG" >/dev/null 2>&1 && [ -z "${REPUBLISH:-}" ]; then echo "$TAG existe déjà (REPUBLISH=1 pour remplacer cette release)." >&2; exit 1; fi
[ -f "$TOOLS/changelogs/mSLICE_$VERSION.txt" ] || { echo "Notes manquantes : $TOOLS/changelogs/mSLICE_$VERSION.txt" >&2; exit 1; }

WORK="$(mktemp -d)"
# Les binaires ffmpeg sont arm64 : pas de paquet universel. Compilation sans installer sur ce Mac.
VERSION="$VERSION" NO_INSTALL=1 ./build_app.sh
APPDIR="$PWD/mSLICE.app"
DIST="$WORK/notarized" "$TOOLS/notarize_app.sh" "$APPDIR"
ZIP="$WORK/mSLICE-$VERSION-macOS-arm64.zip"
/usr/bin/ditto -c -k --keepParent "$WORK/notarized/mSLICE.app" "$ZIP"
(cd "$WORK" && shasum -a 256 "$(basename "$ZIP")" > "$(basename "$ZIP").sha256")
python3 "$TOOLS/release_notes.py" mSLICE "$VERSION" --sha "$ZIP.sha256" -o "$WORK/notes.md"

git tag -a "$TAG" -m "mSLICE $VERSION" 2>/dev/null || true
git push origin main
git push origin "$TAG" 2>/dev/null || true
if [ -n "${REPUBLISH:-}" ]; then
  gh release upload "$TAG" "$ZIP" "$ZIP.sha256" --clobber
  gh release edit "$TAG" --notes-file "$WORK/notes.md"
else
  gh release create "$TAG" "$ZIP" "$ZIP.sha256" --title "mSLICE $VERSION" --notes-file "$WORK/notes.md"
fi
rm -rf "${WORK:?}" "${APPDIR:?}"
echo "OK : release $TAG publiée"
