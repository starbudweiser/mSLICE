# mSLICE — architecture proposée (à valider avant tout code)

Appli macOS 14+ (testée sur macOS 27), Swift / SwiftUI + AppKit, design **Flat Mat** (Socle), 4 langues (FR, EN, ES, IT), DESKTOP MAC TOOLKIT, dossier d'installation « Applications Personnelles ». Bundle id de dev `fr.stephan.mslice.dev`, version locale `fr.stephan.mslice`.

## 1. Principe : vitesse et précision

| Besoin | Choix technique |
| --- | --- |
| Lecture et scrub instantanés | `AVPlayer` pour tout ce que macOS lit (MOV, MP4, M4V, ProRes, H.264, HEVC, WAV, AIFF, MP3, AAC, CAF). Seek « tolérance zéro » = précis à l'image. |
| Formats exotiques en entrée (MKV, AVI, WebM, MXF, MTS, FLV, WMV, FLAC, OGG, Opus, AC3…) | `ffprobe` lit tout. Si les flux sont lisibles par Apple : **remux sans perte** (`-c copy`, quelques secondes) vers un proxy `.mov` en cache. Sinon : proxy basse définition encodé en matériel (VideoToolbox). L'export, lui, repart toujours du fichier d'origine. |
| Timeline réactive | Vue AppKit sur calque (`CALayer`) : pics audio en **pyramide de résolutions** (calculés une fois, en cache disque) → zoom et défilement sans recalcul ; vignettes via `AVAssetImageGenerator`. Aucun calcul sur le fil principal. |
| Coupe sans perte juste | Index des **images clés** (`ffprobe -skip_frame nokey`) chargé en tâche de fond ; l'aimant colle I / O dessus ; l'interface affiche l'image clé réelle où la coupe tombera. Audio seul : coupe exacte à l'échantillon / trame. |
| Export | `ffmpeg` / `ffprobe` **embarqués** (processus séparés, dans `Contents/Helpers`, signés et notarisés avec l'appli). Pas de dépendance à Homebrew. |

## 2. Modules

- **Core** : `Project` (un fichier ouvert), `Segment` (id, entrée, sortie, nom), `ExportPlan` (mode fusion / séparés, format, passthrough, dossier), `MediaInfo` (flux, durée, images clés).
- **Probe** : lance `ffprobe`, produit `MediaInfo` + index des images clés.
- **Playback** : `AVPlayer`, proxy (remux ou transcodage), horloge de la timeline.
- **WaveformCache** : pics multi-résolutions, vignettes, cache dans `~/Library/Caches/mSLICE/`.
- **Timeline** : vue AppKit (zoom, défilement, poignées d'entrée / sortie, lecture, aimant).
- **Scalpel** : raccourcis `I` entrée, `O` sortie, `⌫` suppression, `←→` image, `⇧←→` 1 s, `J K L`, `Espace`, `⌘↩` exporter. Un seul gestionnaire d'événements clavier, au niveau de la fenêtre.
- **Exporter** : construit les commandes `ffmpeg`, exécute une file (un seul calcul lourd à la fois, via `calcul-lourd` pour les recompressions), progression, annulation, nommage `<nom>_01`, `_02`… sans jamais écraser un fichier existant (la numérotation continue).
- **BatchTrim** : « Élaguer début et fin » en lot (X s / Y s, ou détection : `silencedetect` audio, option image noire / figée) ; produit un `Project` à un morceau par fichier, puis l'exporte.
- **FinderBridge** : extension Finder + schéma d'URL `mslice://open?files=…` / `mslice://trim?files=…`.
- **Settings / Updater / About** : réglages, mise à jour automatique (modèle `mBACKUP/Sources/Updater.swift`), fenêtre « À propos » et lien « ♥ Soutenir le projet » (modèles Socle), textes `Loc` en 4 langues.

## 3. Export (ffmpeg)

- **Sans recompression (passthrough)** : `ffmpeg -ss <image clé ≤ entrée> -to <sortie> -i src -map 0 -c copy -avoid_negative_ts make_zero out.ext`. Tous les flux sont copiés (pistes audio, sous-titres, timecode). La coupe vidéo tombe sur l'image clé précédente : l'interface le montre et propose **« Précis aux bords »** (v1.1) : seules les images autour de la coupe sont recompressées, le reste est copié, puis collé.
- **Fusion sans recompression** : un fichier par morceau (copie), puis `concat` demuxer. Même codec garanti, c'est la même source.
- **Recompresser** : H.264 / HEVC / ProRes en matériel (`*_videotoolbox`), audio AAC / MP3 / FLAC / WAV / AIFF / Opus. Sortie conteneurs : **MP4, MOV, MKV, WebM** (WebM : VP9 + Opus), **M4A, MP3, WAV, FLAC, AIFF, OGG**.
- Le build `ffmpeg` embarqué est un build **LGPL** (sans libx264 / libx265, qui sont GPL) : l'encodage H.264 / HEVC passe par VideoToolbox. (Le `ffmpeg` Homebrew de ce Mac est en GPL et ne sera pas embarqué.)
- Les originaux ne sont jamais modifiés. Option : « Mettre l'original à la corbeille après l'export » (corbeille, jamais suppression).

## 4. Clic droit dans le Finder (choix : entrée directe)

- **Extension Finder** (`FIFinderSync`, cible `.appex` dans l'appli) qui surveille `/` et `/Volumes` et ajoute en haut du menu : « Extraire des morceaux avec mSLICE… » (un ou plusieurs fichiers) et « Élaguer début et fin avec mSLICE… » (plusieurs fichiers : lot). Elle n'apparaît que pour les types audio / vidéo (UTI `public.audiovisual-content`).
- L'extension envoie les chemins à l'appli par `mslice://` (NSWorkspace) ; l'appli se lance en second plan si besoin.
- Au premier lancement, l'appli active l'extension (`pluginkit`) et indique dans les réglages si elle est « Active » ; sinon un bouton ouvre les Réglages Système.
- **Risque à lever en premier (spike d'une heure)** : une extension Finder signée avec notre certificat local « sKYCRASH Local Signing » peut ne pas être enregistrée par `pluginkit` (il faut parfois un Developer ID). Si c'est le cas, la version locale utilise un repli **Action rapide** (workflow dans `~/Library/Services`, sous-menu « Actions rapides ») et l'entrée directe n'existe que dans la version notarisée.

## 5. Données et persistance

- `~/Library/Application Support/mSLICE/sessions/<empreinte-du-fichier>.json` : morceaux de chaque fichier, restaurés à la réouverture.
- Réglages dans `UserDefaults` ; aucun secret. Caches purgeables dans `~/Library/Caches/mSLICE/`.
- Aucune donnée personnelle dans l'appli ni dans les maquettes ; version de test vierge possible (identifiant et dossier de données distincts).

## 6. Intégration à l'environnement

- Compilation : script de build avec `sign_app.sh`, icône (`--icon assets/*.icns`), ajout à la liste `APPS` de `_tools/build_all.sh`, installation dans `~/Applications/Applications Personnelles`.
- Icône d'appli sans effet + icône de dossier bleu nuit (`icone_dossier.sh`, iCONIQ collection « MES APPLICATIONS »).
- Dépôt GitHub `starbudweiser/mSLICE` (privé au début), `release.sh` avec notarisation, `.github/FUNDING.yml`, section « About » du README en anglais.
- Pendant les itérations : version `.dev` + mise à jour de ta version locale, sans notarisation ni push (règle du 10/11/2026).

## 7. Plan de réalisation

1. Spike : extension Finder avec la signature locale ; build ffmpeg LGPL embarquable.
2. Noyau : sonde, index des images clés, export sans recompression (séparés + fusion), nommage numéroté. Tests sur MOV / MP4 / MKV / WAV.
3. Lecteur + timeline + scalpel I / O + multi-morceaux (écran « Éditeur »).
4. Recompression et formats de sortie, file d'export, écrans « Export en cours / terminé ».
5. Élagage en lot et détection de silences ; extension Finder ; réglages, mise à jour, À propos, 4 langues.
6. Icônes, build, installation locale ; notarisation seulement sur ta demande.

## 8. Hors périmètre de la v1

Montage multi-pistes, effets, sous-titres, « Précis aux bords » (prévu en v1.1), transcodage par lot vers des préréglages de plateforme.
