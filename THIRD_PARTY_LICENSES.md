# Composants tiers / Third-party components

mSLICE embarque deux programmes en ligne de commande, `ffmpeg` et `ffprobe` (dans `mSLICE.app/Contents/Helpers`), compilés par ce dépôt (`ffmpeg/build_ffmpeg.sh`) à partir de la source officielle de FFmpeg **sans modification**. Ils sont lancés comme des processus séparés ; remplacer `ffmpeg` et `ffprobe` par une autre version est possible en les remplaçant dans ce dossier.

mSLICE bundles two command-line programs, `ffmpeg` and `ffprobe` (in `mSLICE.app/Contents/Helpers`), built by this repository (`ffmpeg/build_ffmpeg.sh`) from the official, unmodified FFmpeg source. They run as separate processes; you can swap in another build by replacing them in that folder.

| Composant | Version | Licence | Fichier |
| --- | --- | --- | --- |
| FFmpeg (libavcodec, libavformat, libavfilter, libswscale, libswresample, libavutil) | 8.0, configuré **sans** `--enable-gpl` ni `--enable-nonfree` | GNU LGPL 2.1 ou ultérieure | `licenses/ffmpeg-COPYING.LGPLv2.1.txt` |
| LAME (encodage MP3) | 3.100 | GNU LGPL 2 | `licenses/lame-COPYING.txt` |
| mpg123 (décodeur lié à LAME) | 1.32 | GNU LGPL 2.1 | `licenses/mpg123-COPYING.txt` |
| Opus (encodage Opus) | 1.5 | BSD 3 clauses | `licenses/opus-COPYING.txt` |
| libvpx (VP8 / VP9) | 1.15 | BSD 3 clauses | `licenses/libvpx-LICENSE.txt` |

- Source de FFmpeg : https://ffmpeg.org/releases/ffmpeg-8.0.tar.xz (https://ffmpeg.org/ — code source, correspondant exactement aux binaires, avec la configuration décrite dans `ffmpeg/build_ffmpeg.sh`).
- H.264, HEVC et ProRes sont encodés par VideoToolbox (matériel d'Apple), l'audio AAC par AudioToolbox : aucun encodeur GPL (x264, x265) n'est embarqué.
- Les licences sont aussi copiées dans l'appli : `mSLICE.app/Contents/Resources/Licenses`.
- « FFmpeg » est une marque de Fabrice Bellard, https://ffmpeg.org/. mSLICE n'est ni approuvé ni affilié au projet FFmpeg.
