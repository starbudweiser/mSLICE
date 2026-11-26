#!/bin/bash
# Publie une version de mSLICE : compile (Apple Silicon, ffmpeg embarqué), signe Developer ID, notarise, agrafe, crée la release GitHub vX.Y.Z.
# L'appli installée se met à jour toute seule depuis cette release (Updater.swift).
# Usage : ./release.sh 1.0.0            (notes : _tools/changelogs/mSLICE_<version>.txt, 4 langues obligatoires)
#   NO_PUBLISH=1   : compile et notarise seulement ; le paquet reste dans ~/Library/Caches/mSLICE-release/<version>/
#   PUBLISH_ONLY=1 : publie le paquet déjà préparé (sans recompiler ni renotariser)
#   REPUBLISH=1    : remplace une release existante
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${1:?Usage : ./release.sh <version>}"
TAG="v$VERSION"
TOOLS=/Volumes/SKYRIM/TOOLS/MAC/_tools
OUT="$HOME/Library/Caches/mSLICE-release/$VERSION"
ZIP="$OUT/mSLICE-$VERSION-macOS-arm64.zip"
[ -z "$(git status --porcelain --untracked-files=no)" ] || { echo "Modifications non commitées : commitez d'abord." >&2; exit 1; }
if git rev-parse "$TAG" >/dev/null 2>&1 && [ -z "${REPUBLISH:-}" ]; then echo "$TAG existe déjà (REPUBLISH=1 pour remplacer cette release)." >&2; exit 1; fi

if [ -z "${PUBLISH_ONLY:-}" ]; then
  [ -f "$TOOLS/changelogs/mSLICE_$VERSION.txt" ] || { echo "Notes manquantes : $TOOLS/changelogs/mSLICE_$VERSION.txt" >&2; exit 1; }
  rm -rf "${OUT:?}"; mkdir -p "$OUT"
  # Les binaires ffmpeg sont arm64 : pas de paquet universel. Compilation sans installer sur ce Mac.
  VERSION="$VERSION" NO_INSTALL=1 ./build_app.sh
  DIST="$OUT/notarized" "$TOOLS/notarize_app.sh" "$PWD/mSLICE.app"
  /usr/bin/ditto -c -k --keepParent "$OUT/notarized/mSLICE.app" "$ZIP"
  (cd "$OUT" && shasum -a 256 "$(basename "$ZIP")" > "$(basename "$ZIP").sha256")
  python3 "$TOOLS/release_notes.py" mSLICE "$VERSION" --sha "$ZIP.sha256" -o "$OUT/notes.md"
  rm -rf "${PWD:?}/mSLICE.app"
  # l'appli notarisée n'est plus utile une fois zippée : la laisser ferait apparaître une version de plus dans « Ouvrir avec » (Launch Services l'enregistre)
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$OUT/notarized/mSLICE.app" >/dev/null 2>&1 || true
  rm -rf "$OUT/notarized"
fi
[ -f "$ZIP" ] && [ -f "$ZIP.sha256" ] && [ -f "$OUT/notes.md" ] || { echo "Paquet introuvable dans $OUT : lancez d'abord sans PUBLISH_ONLY." >&2; exit 1; }
if [ -n "${NO_PUBLISH:-}" ]; then echo "Paquet prêt (non publié) : $ZIP"; exit 0; fi

git tag -a "$TAG" -m "mSLICE $VERSION" 2>/dev/null || true
git push origin main
git push origin "$TAG" 2>/dev/null || true
if [ -n "${REPUBLISH:-}" ]; then
  gh release upload "$TAG" "$ZIP" "$ZIP.sha256" --clobber
  gh release edit "$TAG" --notes-file "$OUT/notes.md"
else
  gh release create "$TAG" "$ZIP" "$ZIP.sha256" --title "mSLICE $VERSION" --notes-file "$OUT/notes.md"
fi
echo "OK : release $TAG publiée"
