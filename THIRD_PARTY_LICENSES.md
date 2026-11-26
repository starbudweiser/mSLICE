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
| DeepFilterNet3 (débruitage de la voix, réseau converti en Core ML ; poids inchangés) | 0.5.6 | MIT | `licenses/DeepFilterNet-LICENSE-MIT.txt` |

- Source de FFmpeg : https://ffmpeg.org/releases/ffmpeg-8.0.tar.xz (https://ffmpeg.org/ — code source, correspondant exactement aux binaires, avec la configuration décrite dans `ffmpeg/build_ffmpeg.sh`).
- H.264, HEVC et ProRes sont encodés par VideoToolbox (matériel d'Apple), l'audio AAC par AudioToolbox : aucun encodeur GPL (x264, x265) n'est embarqué.
- Les licences sont aussi copiées dans l'appli : `mSLICE.app/Contents/Resources/Licenses`.
- « FFmpeg » est une marque de Fabrice Bellard, https://ffmpeg.org/. mSLICE n'est ni approuvé ni affilié au projet FFmpeg.

## Modèle optionnel (téléchargé à la demande, jamais embarqué) / Optional model (downloaded on request, never bundled)

Pour reconnaître les personnages, mSLICE peut télécharger, **seulement si l'utilisateur l'accepte** (onglet Trouver), un modèle de reconnaissance de visages. Il est installé dans `Application Support/mSLICE/models/characters`, avec sa licence et sa notice, et supprimable à tout moment.

To recognise characters, mSLICE can download — **only if the user agrees** (Find tab) — a face-recognition model. It is installed in `Application Support/mSLICE/models/characters` together with its licence and notice, and can be removed at any time.

| Composant | Licence | Source |
| --- | --- | --- |
| AuraFace-v1 (`glintr100.onnx`, ArcFace ResNet-100), fal.ai | Apache License 2.0 | https://huggingface.co/fal/AuraFace-v1 |

- Modifications (Apache 2.0, section 4 b) : conversion ONNX → Core ML (flottants 16 bits), normalisation des pixels intégrée au modèle, palettisation des poids sur 8 bits (k-moyennes). Aucun réentraînement. Script : `scripts/convert_character_model.py`.
- Fichier hébergé (licence, notice et empreinte SHA-256 comprises) : https://github.com/starbudweiser/mSLICE-models (release `characters-auraface-1`).
- Changes (Apache 2.0, section 4 b): ONNX → Core ML conversion (float16), pixel normalisation built into the model, weights palettised to 8 bits (k-means). No retraining.
- « AuraFace » et « fal.ai » appartiennent à leurs titulaires ; mSLICE n'est ni approuvé ni affilié à fal.ai. / "AuraFace" and "fal.ai" belong to their owners; mSLICE is neither endorsed by nor affiliated with fal.ai.

To recognise voices, mSLICE can download — **only if the user agrees** (Find tab) — a second, optional model. It is installed in `Application Support/mSLICE/models/voices` together with its licence and notice, and can be removed at any time.

| Composant | Licence | Source |
| --- | --- | --- |
| CAM++ (`iic/speech_campplus_sv_en_voxceleb_16k`), 3D-Speaker, Alibaba / ModelScope | Apache License 2.0 | https://github.com/modelscope/3D-Speaker |

- Modifications (Apache 2.0, section 4 b) : conversion PyTorch → Core ML (flottants 32 bits, entrée fixe de 150 trames × 80 caractéristiques), couche de moyennes par segments réécrite en opération équivalente pour la longueur fixe, remise en forme d'un tenseur remplacée par une opération équivalente. Aucun réentraînement ; sortie vérifiée contre les poids d'origine (cosinus ≥ 0,9999998). Script : `scripts/model_trials/convert_campplus.py`.
- Changes (Apache 2.0, section 4 b): PyTorch → Core ML conversion (float32, fixed input of 150 frames × 80 features), segment-pooling layer rewritten as an equivalent operation for the fixed length, one tensor reshape replaced by an equivalent one. No retraining; output verified against the original weights (cosine ≥ 0.9999998).
- Fichier hébergé : https://github.com/starbudweiser/mSLICE-models (release `voices-campplus-1`, à publier avec l'accord du propriétaire). Le modèle d'origine a été entraîné sur VoxCeleb (jeu de données de recherche) : voir la fiche du modèle d'origine.
- « CAM++ », « 3D-Speaker » et « Alibaba » appartiennent à leurs titulaires ; mSLICE n'est ni approuvé ni affilié. / These names belong to their owners; mSLICE is neither endorsed by nor affiliated with them.
