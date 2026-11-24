# Essai des modèles d'identité (24/11/2026)

Outils de l'étape « essai des modèles » (voir `ETAT.md` § 9). Ils servent à refaire la mesure si on veut comparer un autre modèle ; **rien ici n'est compilé dans l'appli**.

Dossier de travail attendu (hors dépôt) : `data/full/{align112,face224,person224}` (recadrages), `data/label/labels_final.json`, `data/cuts.txt`, `models/…`, `feats/`.

| Fichier | Rôle |
| --- | --- |
| `extract.swift` | Vision (visages + repères, personnes) → recadrages : visage **aligné 112 × 112** sur le gabarit ArcFace (similitude sur 5 points : pupilles, nez, coins de la bouche), carré large 224, personne 224. Un échantillon par seconde. L'ordre des visages est trié (résultat identique d'une passe à l'autre). Les images sortantes ne vont **jamais** dans le dépôt (droits d'auteur). |
| `fp.swift` | Empreinte générique d'Apple (`VNGenerateImageFeaturePrintRequest`), pour la comparaison. |
| `convert_trials.py` | Conversion Core ML (fp16) de DINOv2-S, SFace, AuraFace (essai). La conversion livrée est `scripts/convert_character_model.py`. |
| `embed.py`, `embed_dino2.py`, `quant.py` | Empreintes Core ML de tous les recadrages, contrôle de fidélité (Core ML fp16 contre ONNX Runtime / PyTorch fp32), palettisation 8 / 6 / 4 bits. |
| `bench.swift` | Vitesse native : compilation, chargement, 300 prédictions (moteur neuronal, GPU, processeur). |
| `evalid.py` | Vérification par paires sur les étiquettes, regroupement (liaison moyenne), critères sans étiquette (paires de la même image = personnes différentes ; paires du même plan = même personne). `EXT=1` étend les étiquettes le long des suivis de visage (visages difficiles). |
| `labels_final.json` | 202 visages nets étiquetés à la main avec des lettres anonymes (aucun nom), `merge` / `equiv` : groupes identiques ou peut-être identiques (paires croisées ignorées). |
| `cuts.txt` | Coupures de plans de la vidéo de test (ffmpeg, seuil 0,25), pour construire les suivis. |

Limites : une seule vidéo (28 min, séries TV : visages réels seulement, aucune créature) ; vérité terrain posée par une seule personne (étiquettes anonymes) ; 202 visages nets, étendus à 543 par les suivis.
