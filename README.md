# mSLICE

## About

**mSLICE** is a small, fast macOS tool that does one thing: cut pieces out of audio and video files. Mark an in and an out point with the **I** and **O** keys, keep as many pieces as you like in the same file, and export them as separate numbered files or as one merged file. With *No re-encoding* (direct stream copy) a multi‑gigabyte rush is trimmed in a fraction of a second, with no quality loss. The playhead follows the mouse frame by frame, a **Find** tab spots scenes (fire, crowd, night, vehicles…) and sounds (speech, music, laughter, gunfire…) with the models built into macOS — nothing leaves your Mac — and turns their passages into pieces, and an optional AI agent (chat panel or MCP server) can cut, merge and export on request — it only ever creates new files. Part of the **DESKTOP MAC TOOLKIT**.

## À propos

mSLICE sert à **élaguer** des fichiers audio et vidéo : retirer les 10 ou 20 premières secondes où il ne se passe rien, la fin enregistrée « par sécurité », ou extraire plusieurs morceaux d'une longue séquence.

- **Bistouri aux touches I / O** : `I` pose l'entrée, `O` la sortie et crée le morceau ; plusieurs morceaux par fichier ; poignées à glisser sur la timeline.
- **Timeline précise et réactive** : règle avec images clés, vignettes, forme d'onde, zoom (⌘ + molette, pincement), déplacement de la vue zoomée (molette, ou bouton de la molette enfoncé et glissé), lecture J K L, image par image (← →), image clé par image clé (↑ ↓).
- **Sans recompression** (copie directe des flux) : instantané, aucune perte. En copie directe, une vidéo ne peut démarrer que sur une image clé : l'entrée se cale sur l'image clé précédente et l'interface l'indique.
- **Export** : un fichier par morceau (`nom_01`, `nom_02`… la numérotation continue, rien n'est jamais écrasé) ou un seul fichier fusionné.
- **Formats** : tout ce que ffprobe sait lire en entrée (MOV, MP4, MKV, AVI, WebM, MXF, MTS, WAV, AIFF, MP3, AAC, FLAC, OGG, Opus…). En sortie : MP4, MOV, MKV, WebM, MP3, M4A, WAV, FLAC, AIFF, Opus, ou le conteneur d'origine.
- **Recompression** (au choix) : H.264 / H.265 / ProRes en matériel (VideoToolbox), VP9 pour le WebM.
- **Clic droit dans le Finder** : « Extraire des morceaux avec mSLICE… » et « Élaguer début et fin avec mSLICE… » (lot : retire X s au début et Y s à la fin de plusieurs fichiers, ou les silences d'ouverture et de fin).
- **Défilement instantané** : la tête de lecture suit la souris image par image, même sur du H.264 long GOP (décodage matériel, réserve d'images libérée au repos).
- **Trouver** (onglet du panneau de droite) : le bouton « Analyser » repère, avec les modèles intégrés à macOS (Vision, SoundAnalysis ; rien n'est téléchargé, rien ne sort du Mac), les plans, une quarantaine de familles de scènes (feu, foule, nuit, véhicules, animaux…) et de sons (parole, musique, rires, coups de feu, explosions…) : environ 1 s par minute de vidéo, dans un processus séparé (aucune mémoire gardée au repos), résultat gardé. On choisit des critères combinables **ET / SAUF** (« vêtements et costumes SAUF musique »), avec l'option « plans entiers » qui cale les passages sur les coupures ; une piste de résultats apparaît sous la forme d'onde ; « Ajouter N morceaux » les pose comme des morceaux ordinaires (⌘Z annule). Un modèle externe **optionnel** (téléchargé seulement si vous l'acceptez, empreinte vérifiée, supprimable) est prévu pour reconnaître les personnages.
- **Pilotage par un agent** (désactivé par défaut) : un panneau de discussion (Claude Code, API Anthropic, Ollama / LM Studio / OpenAI…) et un serveur MCP (`mslice-mcp`, pour Claude Code, Claude Desktop, Cursor, Codex, Gemini CLI) découpent, fusionnent et exportent à votre demande, et cherchent des scènes ou des sons (`analyze_media`, `find_scenes`). L'agent crée de nouveaux fichiers ; il ne supprime ni n'écrase jamais rien.
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

## Installation

Téléchargez le `.zip` de la dernière [release](https://github.com/starbudweiser/mSLICE/releases/latest), décompressez-le et glissez **mSLICE.app** dans vos Applications. L'appli est signée et notarisée par Apple ; elle exige un Mac Apple Silicon sous macOS 14 ou plus récent, et se met à jour toute seule. Au premier lancement, elle active l'extension du clic droit (Réglages Système ▸ Extensions ▸ Finder si macOS le demande).

## Moteur

ffmpeg et ffprobe **LGPL** statiques sont embarqués (`Contents/Helpers`) : `ffmpeg/build_ffmpeg.sh` les compile depuis la source officielle, sans GPL (H.264 / HEVC / ProRes passent par VideoToolbox, MP3 par LAME, Opus par libopus, VP9 par libvpx). Aucun accès réseau.

## Construire

```bash
DEV=1 ./build_app.sh          # mSLICE DEV.app (dans le dossier du projet)
./build_app.sh                # mSLICE.app, installée dans ~/Applications/Applications Personnelles
```

Serveur MCP : `mSLICE.app/Contents/MacOS/mslice-mcp` (réglages ▸ Agent : boutons de copie pour Claude Code, Claude Desktop, Cursor, Codex, Gemini CLI). Essais : `scripts/mcp_e2e.py`.

Essais sans fenêtre : `mSLICE --selftest <fichier>` (export), `--selftest-editor <fichier>` (bistouri), `--selftest-ui <fichier>` (interface), `--selftest-batch <fichier>` (lot), `--check-l10n`.

## Licence

mSLICE est publié sous licence MIT (voir `LICENSE`). Il embarque FFmpeg (LGPL 2.1), LAME, mpg123, Opus et libvpx : voir `THIRD_PARTY_LICENSES.md` et le dossier `licenses/`.

## Support / Soutenir

mSLICE est gratuit. Si l'outil vous sert, vous pouvez soutenir le projet : https://github.com/sponsors/starbudweiser
