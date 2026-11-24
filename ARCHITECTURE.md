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


## 9. Défilement instantané (v1.1)

Pendant qu'on déplace la tête de lecture, `Scrub.swift` décode en matériel (AVAssetReader → VideoToolbox) le groupe d'images qui contient l'instant visé, depuis son
image clé, et affiche les images par une `AVSampleBufferDisplayLayer` posée sur le lecteur. L'image clé arrive en ≈ 20 ms, les suivantes à plusieurs centaines d'images par
seconde ; revenir dans un groupe décodé est instantané et exact à l'image. AVPlayer n'est sollicité qu'au relâchement (position exacte) puis la couche s'efface.
Réserve d'images : 3 % de la RAM, 400 Mo au plus, libérée après 12 s sans demande et sous pression mémoire. Fichiers pivotés ou audio seul : AVPlayer comme avant.

## 10. Pilotage par un agent (v1.1)

- **Noyau commun** (`AgentCore.swift`, sans interface) : 17 outils (état, sondage, silences, image d'un instant, morceaux, aperçu et export, élagage en lot, ouverture, tête de lecture).
  Garde-fous appliqués par le noyau, quel que soit l'agent : nouveaux fichiers seulement (jamais d'écrasement, de suppression ni de corbeille), écriture limitée au dossier du fichier
  source (ou sous-dossier, liens symboliques résolus) et au dossier d'export de l'utilisateur, chemins sans caractères de contrôle, nombres finis, journal `agent.log` (rotation 1 Mo).
  Désactivé par défaut : réglage « Autoriser un agent à piloter mSLICE » (Réglages ▸ Agent).
- **Serveur MCP** `mSLICE.app/Contents/MacOS/mslice-mcp` (stdio, JSON-RPC 2.0) : compilé avec le noyau seul. Appli ouverte, l'appel est transmis par une prise Unix (`agent.sock`, droits 0600,
  8 clients au plus) et exécuté dans l'appli : la timeline se met à jour en direct. Appli fermée, l'outil s'exécute sans fenêtre ; les morceaux sont gardés par fichier (`SessionStore`).
- **Panneau de discussion** (onglet « Agent » du panneau de droite) : moteurs Claude Code (CLI de l'utilisateur, abonnement, relié à `mslice-mcp`), API Anthropic, ou service compatible OpenAI
  (Ollama, LM Studio, OpenAI, OpenRouter…). Les deux derniers exécutent la boucle d'outils dans l'appli. Clés dans le Trousseau, envoyées seulement en HTTPS (ou vers le réseau local).
- Essais : `scripts/mcp_e2e.py` (serveur autonome, garde-fous, entrées hostiles), `--selftest-ui` (pont vers l'appli ouverte, panneau avec `scripts/mock_llm.py` via `MSLICE_TEST_LLM`,
  Claude Code réel via `MSLICE_TEST_CLAUDE=1`), `MSLICE_PERF=1` (mémoire et processeur par étape).

## 11. Trouver : analyse native des scènes et des sons (v1.2)

- **Analyse** (`Sources/Analysis/`, sans interface, compilée aussi dans `mslice-mcp`) : une seule passe de décodage matériel (`AVAssetReader`, 512 px, toutes les images) ; chaque image sert à la détection des coupures
  (miniatures de luminance 32×18 et de chrominance 16×9×2 comparées à l'image précédente : coupures exactes à l'image près, 72 sur 75 identiques à ffmpeg) et une image toutes les 0,5 s part en `VNClassifyImageRequest`
  (1 303 étiquettes, dix meilleures gardées). En parallèle, l'audio est décodé en 16 kHz mono et classé par `SNClassifySoundRequest` (fenêtres de 1,5 s toutes les 0,5 s, 303 types). Aucune image n'est conservée ;
  le décodeur n'a que trois images en attente (mémoire bornée). Formats que macOS ne lit pas : même proxy que le lecteur (`Proxies.swift`).
- **Processus séparé** (`AnalysisRunner`) : l'appli lance `mslice-mcp --analyze <fichier>` (JSON de progression sur la sortie standard, « cancel », « pause », « resume » sur l'entrée standard ; il s'arrête si l'appli disparaît).
  Vision et SoundAnalysis chargent ≈ 30 Mo de modèles qu'elles ne rendent pas : dans un processus à part, tout revient au système à la fin (l'appli garde la même empreinte avant et après), et un plantage d'un modèle d'Apple
  ne touche pas l'appli. Une analyse à la fois, qualité de service « utilitaire », pause pendant la lecture et l'export. Mesuré : 28 min en 25 s, 58 Mo de pic dans le processus d'analyse, 0 % processeur au repos.
- **Index** (`AnalysisIndex`) : `Application Support/mSLICE[ DEV]/index/<clé>.msidx` (même clé que les sessions), liste de propriétés binaire versionnée, ≈ 6 Ko par minute ; un index tronqué, d'une autre version ou
  incohérent est refusé. Il garde les coupures, les meilleures étiquettes par échantillon d'image et par fenêtre de son.
- **Familles** (`Families.swift`) : 45 familles de scènes et 42 de sons (toutes les étiquettes de macOS y sont classées ou cherchables par leur nom brut), traduites dans les 4 langues ; l'essai vérifie qu'aucune étiquette citée n'est inconnue.
- **Requêtes** (`Finder`) : grille de 0,5 s, seuils (image 0,35 ; son 0,5), critères **ET** (intersection) et **SAUF** (un passage qui en chevauche un reste listé « écarté » mais n'entre pas dans les morceaux), trous de moins de 1,5 s comblés,
  passages de moins de 1 s écartés, « plans entiers » (calage sur les coupures) ou marge de 0,3 s, passages voisins (moins de 1,5 s) réunis en un morceau.
- **Interface** (`FindModel`, `FindPanel`, onglet Édition | Trouver | Agent) : avant l'analyse, en cours (annulable), résultats (scènes, sons, carte « Personnages »), sélection avec passages (vignettes à la demande, cases à cocher),
  « Ajouter N morceaux » (annulable d'un coup par ⌘Z), piste de résultats de 14 pt sous la forme d'onde (un clic va au début du passage).
- **Modèle externe optionnel** (`ModelStore`) pour les personnages (macOS n'expose aucune identité de visage ; l'empreinte générique d'Apple mélange les personnes) : jamais embarqué, téléchargé seulement avec l'accord de
  l'utilisateur, HTTPS seulement, taille plafonnée, empreinte SHA-256 vérifiée (et recalculée avant tout usage), installation atomique, suppression à tout moment. Modèle retenu en 1.3 : voir § 12.
- **Agent** : `analyze_media` (plans, familles de scènes et de sons trouvées, avec leurs identifiants) et `find_scenes` (`include` ET, `exclude` SAUF, `whole_shots`, `apply` = none / add / set ; critères `scene:`, `sound:`, `label:`,
  `sound_label:`). Mêmes garde-fous (aucun fichier écrit, aucun morceau supprimé par un ajout). Essais : `--selftest-analysis`, `--selftest-ui` (onglet et pont), `scripts/mcp_e2e.py` (index synthétique pour les combinaisons).

## 12. Trouver : les personnages (v1.3)

- **Modèle** : AuraFace-v1 (fal.ai, ArcFace ResNet-100, Apache 2.0) converti en Core ML palettisé 8 bits (zip de 62,6 Mo, `scripts/convert_character_model.py`), choisi à l'essai (ETAT.md § 9 : AUC 0,998 / 0,980, 1,7 ms par visage ; l'empreinte
  générique d'Apple, DINOv2 et SFace écartés). Hébergé dans une release de `starbudweiser/mSLICE-models`. `ModelFiles` (catalogue, fichiers installés, vérifications ; partagé avec `mslice-mcp`) et `ModelStore` (téléchargement
  avec accord, HTTPS seulement, taille plafonnée, empreinte SHA-256 de l'archive vérifiée) : l'archive est inspectée avant extraction (aucun chemin absolu ni « .. », taille décompressée plafonnée), décompressée dans un dossier de travail
  (aucun lien symbolique toléré), le `.mlpackage` est compilé (`MLModel.compileModel`), seuls le `.mlmodelc`, la licence et la notice sont gardés, et l'empreinte de l'arbre compilé est notée au manifeste puis **recalculée avant chaque
  chargement** (`ModelFiles.verified`) : un modèle remplacé ou altéré n'est jamais chargé.
- **Reconnaissance** (`FaceAnalyzer`, dans `mslice-mcp --faces <fichier>`, même protocole que `--analyze` : progression JSON, cancel / pause / resume, arrêt si l'appli disparaît) : une passe de décodage matériel (jusqu'à 1 920 px), une
  image par seconde, `VNDetectFaceLandmarksRequest` → 5 points → alignement par similitude sur le gabarit ArcFace → 112 × 112 → modèle (moteur neuronal) → empreinte de 512 valeurs normalisées. Mémoire bornée (deux images en attente),
  qualité de service « utilitaire », pause pendant la lecture et l'export. Le modèle est libéré avec le processus.
- **Mesuré** (vidéo de test de 28:05, 1080p, M5 Max) : 22 s, 1 845 visages, 50 personnages (1 617 visages rattachés, 925 suivis), pic de 278 Mo dans le processus (le modèle chargé en occupe l'essentiel : décoder à 1 280 px au lieu de 1 920 ne
  gagne que 30 Mo et ralentit la passe par 2,5), rien de gardé par l'appli ; annulation en 0,1 s ; modèle altéré refusé.
- **Suivis et groupes** (`FaceClustering`) : les visages de deux images voisines d'un même plan (sans coupure entre elles), dont les boîtes se recouvrent et dont les empreintes se ressemblent, forment un suivi ; regroupement par liaison
  moyenne (UPGMA sur les sommes d'empreintes, similarité 0,30 soit une distance de 0,70) en partant des suivis, avec la contrainte stricte « jamais deux visages d'une même image dans un personnage » ; un personnage compte au moins 4 images.
  La séparation d'un personnage relance la liaison sur ses seuls suivis jusqu'à en obtenir deux.
- **Index des visages** (`FaceIndex`, `.msfaces` à côté de `.msidx`, même clé, lié à l'empreinte du modèle) : instant, boîte, taille, suivi, personnage, empreinte quantifiée sur 8 bits (≈ 0,5 Ko par visage) ; noms, personnages écartés. Binaire,
  versionné, refusé s'il est tronqué ou incohérent (comptes, valeurs non finies, instants non triés, groupes hors table). Aucune image n'est gardée : les vignettes rondes sont recalculées depuis la vidéo.
- **Requêtes** : critère `person:<n>` (grille de 0,5 s, couverture = un pas d'échantillonnage autour de chaque visage, prolongée dans un même suivi), donc ET / SAUF avec les scènes et les sons, plans entiers, lissage : tout le reste de `Finder`.
- **Interface** : carte « Personnages » (télécharger → reconnaître → vignettes rondes, 3 par ligne ; clic = ajouter à la sélection ; clic droit = renommer, réunir avec…, séparer en deux, ce n'est pas un personnage) ; vignette dans la pastille du critère ;
  les personnages sont aussi dans le menu « Critère ». Les corrections sont enregistrées en tâche de fond.
- **Agent** : `analyze_media` (`characters=true` : ne télécharge jamais, dit `model_not_installed` sans modèle), `list_subjects`, `name_subject`, et `find_scenes` accepte `person:<id ou nom>` (nom insensible à la casse ; ambigu = erreur).
- Limites : visages seulement (pas de créatures ni de costumes) ; une seule vidéo de test (séries TV) pour les réglages ; les visages de profil, petits (< 32 px) ou flous sont écartés ou mal regroupés ; fusion manuelle prévue pour ces cas.
