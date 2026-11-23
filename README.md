# mSLICE

## About

**mSLICE** is a small, fast macOS tool that does one thing: cut pieces out of audio and video files. Mark an in and an out point with the **I** and **O** keys, keep as many pieces as you like in the same file, and export them as separate numbered files or as one merged file. With *No re-encoding* (direct stream copy) a multi‑gigabyte rush is trimmed in a fraction of a second, with no quality loss. Part of the **DESKTOP MAC TOOLKIT**.

## À propos

mSLICE sert à **élaguer** des fichiers audio et vidéo : retirer les 10 ou 20 premières secondes où il ne se passe rien, la fin enregistrée « par sécurité », ou extraire plusieurs morceaux d'une longue séquence.

- **Bistouri aux touches I / O** : `I` pose l'entrée, `O` la sortie et crée le morceau ; plusieurs morceaux par fichier ; poignées à glisser sur la timeline.
- **Timeline précise et réactive** : règle avec images clés, vignettes, forme d'onde, zoom (⌘ + molette, pincement), lecture J K L, image par image (← →), image clé par image clé (↑ ↓).
- **Sans recompression** (copie directe des flux) : instantané, aucune perte. En copie directe, une vidéo ne peut démarrer que sur une image clé : l'entrée se cale sur l'image clé précédente et l'interface l'indique.
- **Export** : un fichier par morceau (`nom_01`, `nom_02`… la numérotation continue, rien n'est jamais écrasé) ou un seul fichier fusionné.
- **Formats** : tout ce que ffprobe sait lire en entrée (MOV, MP4, MKV, AVI, WebM, MXF, MTS, WAV, AIFF, MP3, AAC, FLAC, OGG, Opus…). En sortie : MP4, MOV, MKV, WebM, MP3, M4A, WAV, FLAC, AIFF, Opus, ou le conteneur d'origine.
- **Recompression** (au choix) : H.264 / H.265 / ProRes en matériel (VideoToolbox), VP9 pour le WebM.
- **Clic droit dans le Finder** : « Extraire des morceaux avec mSLICE… » et « Élaguer début et fin avec mSLICE… » (lot : retire X s au début et Y s à la fin de plusieurs fichiers, ou les silences d'ouverture et de fin).
- Les originaux ne sont jamais modifiés ; option « mettre l'original à la corbeille » après l'export.
- Quatre langues (français, anglais, espagnol, italien), thème clair / sombre / auto, mise à jour automatique.

## Raccourcis

| Touche | Action |
| --- | --- |
| `I` / `O` | entrée / sortie (crée le morceau) |
| `Espace`, `J` `K` `L` | lecture, vitesses |
| `←` `→`, `⇧←` `⇧→` | une image, une seconde |
| `↑` `↓` | image clé suivante / précédente |
| `[` `]` | morceau précédent / suivant |
| `⌫`, `⌘Z` | supprimer le morceau, annuler |
| `⌘↩` | extraire |

## Moteur

ffmpeg et ffprobe **LGPL** statiques sont embarqués (`Contents/Helpers`) : `ffmpeg/build_ffmpeg.sh` les compile depuis la source officielle, sans GPL (H.264 / HEVC / ProRes passent par VideoToolbox, MP3 par LAME, Opus par libopus, VP9 par libvpx). Aucun accès réseau.

## Construire

```bash
DEV=1 ./build_app.sh          # mSLICE DEV.app (dans le dossier du projet)
./build_app.sh                # mSLICE.app, installée dans ~/Applications/Applications Personnelles
```

Essais sans fenêtre : `mSLICE --selftest <fichier>` (export), `--selftest-editor <fichier>` (bistouri), `--selftest-ui <fichier>` (interface), `--selftest-batch <fichier>` (lot), `--check-l10n`.

## Support / Soutenir

mSLICE est gratuit. Si l'outil vous sert, vous pouvez soutenir le projet : https://github.com/sponsors/starbudweiser
