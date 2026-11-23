#!/bin/zsh
# ffmpeg + ffprobe LGPL, statiques, embarqués dans mSLICE (Contents/Helpers). Aucun GPL (pas de libx264 / libx265) : H.264, HEVC et ProRes
# passent par VideoToolbox, l'audio par AudioToolbox, MP3 par LAME, Opus par libopus, WebM/VP9 par libvpx. Pas de réseau.
# Source : tarball ffmpeg 8.0 déjà en cache (qLOOKS) ; aucun téléchargement. Sortie : ~/Library/Caches/mSLICE-ffmpeg/out/bin.
# Relancé seulement si la sortie manque ou si ce script change.
set -euo pipefail
VER=8.0
BASE="$HOME/Library/Caches/mSLICE-ffmpeg"
OUT="$BASE/out"
STAMP="$OUT/.built-$(shasum -a 256 "$0" | cut -c1-12)-$VER"
[ -f "$STAMP" ] && exit 0
mkdir -p "$BASE"; cd "$BASE"
if [ ! -f ffmpeg-$VER.tar.xz ]; then
  SRC="$HOME/Library/Caches/qLOOKS-ffmpeg/ffmpeg-$VER.tar.xz"
  [ -f "$SRC" ] || { echo "Source ffmpeg-$VER.tar.xz introuvable (attendue : $SRC)" >&2; exit 1; }
  cp "$SRC" .
fi
rm -rf ffmpeg-$VER build "$OUT" static; tar xf ffmpeg-$VER.tar.xz; mkdir build

# Bibliothèques statiques seules (le linker préfère sinon les .dylib de Homebrew).
HB=/opt/homebrew/opt
mkdir -p static/lib/pkgconfig static/include
for p in lame opus libvpx mpg123; do
  cp -R $HB/$p/include/* static/include/
  cp $HB/$p/lib/libmp3lame.a $HB/$p/lib/libopus.a $HB/$p/lib/libvpx.a $HB/$p/lib/libmpg123.a static/lib/ 2>/dev/null || true
done
for pc in opus vpx; do
  sed -e "s#^prefix=.*#prefix=$BASE/static#" -e "s#^libdir=.*#libdir=$BASE/static/lib#" -e "s#^includedir=.*#includedir=$BASE/static/include#" "$(ls $HB/opus/lib/pkgconfig/$pc.pc $HB/libvpx/lib/pkgconfig/$pc.pc 2>/dev/null | head -1)" > static/lib/pkgconfig/$pc.pc
done
export PKG_CONFIG_LIBDIR="$BASE/static/lib/pkgconfig"

cd build
../ffmpeg-$VER/configure --prefix="$OUT" --arch=arm64 --target-os=darwin --cc=clang \
  --enable-static --disable-shared --enable-pic --pkg-config-flags=--static \
  --extra-cflags="-I$BASE/static/include -mmacosx-version-min=14.0" --extra-ldflags="-L$BASE/static/lib -mmacosx-version-min=14.0" \
  --disable-autodetect --disable-doc --disable-debug --disable-ffplay --disable-network \
  --extra-libs="-lmpg123 -liconv" --enable-videotoolbox --enable-audiotoolbox --enable-zlib --enable-iconv --enable-libmp3lame --enable-libopus --enable-libvpx
make -j"$(sysctl -n hw.ncpu)"
make install
strip "$OUT/bin/ffmpeg" "$OUT/bin/ffprobe" 2>/dev/null || true
touch "$STAMP"
echo "OK : $OUT/bin/ffmpeg"
