"""mSLICE — document « Conception » (FR | EN) : principes, architecture, analyse, personnages, sécurité, agent, mesures, décisions."""
import diagrams as D
from lib import *

d = Doc("conception", "Conception", ("Conception", "Design"), "../img/cover-conception.jpg")
d.cover(("Comment mSLICE est pensé : principes, architecture, analyse des scènes, des sons et des visages, sécurité, mesures.",
         "How mSLICE is designed: principles, architecture, scene, sound and face analysis, security, measurements."))

d.toc([("1", ("Une appli, un usage", "One app, one job"), "3"), ("2", ("Architecture d'ensemble", "Architecture overview"), "5"), ("3", ("Trouver : voir et entendre", "Find: seeing and hearing"), "6"),
       ("4", ("Personnages", "Characters"), "9"), ("5", ("Sécurité et vie privée", "Security and privacy"), "12"), ("6", ("Agent et serveur MCP", "Agent and MCP server"), "13"),
       ("7", ("Mesures et essais", "Measurements and tests"), "14"), ("8", ("Décisions, limites, suite", "Decisions, limits, next"), "15")])

# 1 --------------------------------------------------------------------------------------------------------------------------------------
d.opener("1", ("Une appli, un usage", "One app, one job"),
         ("mSLICE élague : retirer le début où il ne se passe rien, la fin gardée « par sécurité », ou extraire plusieurs morceaux d'une longue séquence. Rien de plus, mais très bien.",
          "mSLICE trims: drop the dead opening, the tail kept “just in case”, or pull several pieces out of a long recording. Nothing more, but done very well."),
         "../img/spot-slice.jpg", ("Principes", "Principles"))

d.add(title(("Principes", "Principles"), ("Vitesse, précision, discrétion", "Speed, precision, discretion")) +
      text(["Un outil d'élagage doit être plus rapide que l'ouverture d'un montage vidéo. mSLICE coupe donc <b>sans recompresser</b> quand c'est possible : les flux sont copiés tels quels, un rush de plusieurs gigaoctets est élagué en une fraction de seconde, sans aucune perte. La précision vient d'un lecteur qui suit la souris image par image, même sur du H.264 long GOP, grâce au décodage matériel.",
            "Tout ce qui est « intelligent » reste au service de cette idée : la détection de scènes, de sons et de personnages ne fait que <b>proposer des morceaux</b>. On les accepte, et on retrouve le bistouri, l'export séparé ou la fusion habituels."],
           ["A trimming tool must be quicker than opening a video editor. So mSLICE cuts <b>without re-encoding</b> whenever it can: streams are copied as they are, a multi-gigabyte rush is trimmed in a fraction of a second, with no loss. Precision comes from a player that follows the mouse frame by frame, even on long-GOP H.264, thanks to hardware decoding.",
            "Everything “smart” serves that idea: detecting scenes, sounds and characters only <b>proposes pieces</b>. You accept them, and the usual scalpel, separate export or merge take over."], drop=True, tags=True) +
      pull(("Une appli par usage, elle le fait bien : pas de montage, pas d'effets, pas de photothèque.", "One app per job, done well: no editing, no effects, no photo library.")) +
      stats([("&lt; 1<small> s</small>", ("pour élaguer un rush de plusieurs Go (copie directe)", "to trim a multi-GB rush (direct copy)")), ("25<small> s</small>", ("pour analyser 28 min : plans, scènes, sons", "to analyse 28 min: shots, scenes, sounds")),
             ("22<small> s</small>", ("pour reconnaître les personnages de 28 min", "to recognise the characters of 28 min")), ("0<small> %</small>", ("de processeur et de mémoire au repos", "CPU and extra memory at rest"))]) +
      note(("<b>Les originaux ne sont jamais modifiés.</b> Les exports créent de nouveaux fichiers (numérotation continue, jamais d'écrasement) ; l'agent aussi.", "<b>Originals are never modified.</b> Exports create new files (continuous numbering, never overwritten); so does the agent.")),
      ("Principes", "Principles"))

# 2 --------------------------------------------------------------------------------------------------------------------------------------
d.add(title(("Architecture", "Architecture"), ("Un noyau sans interface, trois portes d'entrée", "A headless core, three ways in")) +
      fig((D.architecture("fr"), D.architecture("en")), ("Figure 1 — Les modules de mSLICE et leurs échanges.", "Figure 1 — mSLICE's modules and how they talk.")) +
      bullets([("<b>Interface</b> SwiftUI (design Flat Mat) : fenêtre unique, panneau de droite à trois onglets.", "<b>Interface</b> in SwiftUI (Flat Mat design): one window, a three-tab right panel."),
               ("<b>Noyau</b> sans interface (export, session, analyse, outils d'agent) compilé aussi dans <code>mslice-mcp</code> : l'agent et l'appli exécutent le même code.", "<b>Headless core</b> (export, session, analysis, agent tools) also compiled into <code>mslice-mcp</code>: the agent and the app run the same code."),
               ("<b>Analyse dans un processus séparé</b> : Vision, SoundAnalysis et Core ML gardent leurs modèles en mémoire ; en les isolant, tout est rendu au système à la fin.", "<b>Analysis in a separate process</b>: Vision, SoundAnalysis and Core ML keep their models in memory; isolating them returns everything to the system when done.")]),
      ("Architecture", "Architecture"))

# 3 --------------------------------------------------------------------------------------------------------------------------------------
d.opener("2", ("Trouver : voir et entendre", "Find: seeing and hearing"),
         ("Un bouton « Analyser » repère les plans, une quarantaine de familles de scènes et de sons avec les modèles intégrés à macOS. Rien n'est téléchargé, rien ne sort du Mac.",
          "One “Analyze” button spots shots and about forty families of scenes and sounds with the models built into macOS. Nothing is downloaded, nothing leaves your Mac."),
         "../img/spot-listen.jpg", ("Trouver", "Find"), right=True)

d.add(title(("Analyse", "Analysis"), ("Une passe, trois lectures", "One pass, three readings")) +
      fig((D.analysis("fr"), D.analysis("en")), ("Figure 2 — La passe d'analyse : une seule lecture du fichier alimente les trois détecteurs.", "Figure 2 — The analysis pass: one read of the file feeds the three detectors.")) +
      text(["Une seule passe de décodage matériel (512 px, toutes les images) sert à <b>détecter les coupures</b> (miniatures de luminance 32×18 et de couleur comparées à l'image précédente : exactes à l'image près, 72 sur 75 identiques à ffmpeg) et, une image toutes les 0,5 s, à <b>classer la scène</b> (1 303 étiquettes de Vision, dix meilleures gardées). En parallèle, le son est classé par SoundAnalysis (303 types, fenêtres de 1,5 s).",
            "Les étiquettes sont regroupées en <b>45 familles de scènes</b> et <b>42 familles de sons</b> lisibles (feu, foule, nuit, véhicules ; parole, musique, rires, coups de feu…), traduites en quatre langues. Le résultat tient dans un index de ≈ 6 Ko par minute, gardé pour la prochaine ouverture du fichier."],
           ["A single hardware-decoding pass (512 px, every frame) <b>detects the cuts</b> (32×18 luminance and colour thumbnails compared with the previous frame: frame-exact, 72 of 75 identical to ffmpeg) and, once every 0.5 s, <b>classifies the scene</b> (1,303 Vision labels, top ten kept). In parallel, sound is classified by SoundAnalysis (303 types, 1.5 s windows).",
            "Labels are grouped into <b>45 scene families</b> and <b>42 sound families</b> that read well (fire, crowd, night, vehicles; speech, music, laughter, gunfire…), translated into four languages. The result fits in a ≈ 6 KB-per-minute index, kept for the next time the file is opened."], tags=True),
      ("Trouver", "Find"))

d.add(title(("Requêtes", "Queries"), ("Combiner des critères, sans surprise", "Combine criteria, no surprises")) +
      fig((D.query("fr"), D.query("en")), ("Figure 3 — « Personnage ET feu, SAUF musique, en plans entiers ».", "Figure 3 — “Character AND fire, EXCEPT music, whole shots”.")) +
      bullets([("Grille de 0,5 s ; seuils : image 0,35 ; son 0,5. Critères <b>ET</b> = intersection ; <b>SAUF</b> = un passage qui en chevauche un reste listé « écarté » mais n'entre pas dans les morceaux.", "0.5 s grid; thresholds: picture 0.35, sound 0.5. <b>AND</b> criteria intersect; <b>EXCEPT</b> keeps an overlapping passage in the list, marked “dropped”, but out of the pieces."),
               ("Lissage : trous de moins de 1,5 s comblés, passages de moins de 1 s écartés. « Plans entiers » cale chaque passage sur les coupures ; sinon marge de 0,3 s.", "Smoothing: gaps under 1.5 s filled, passages under 1 s dropped. “Whole shots” snaps each passage to the cuts; otherwise a 0.3 s margin."),
               ("Passages voisins (moins de 1,5 s) réunis en un seul morceau ; « Ajouter N morceaux » est annulable d'un seul ⌘Z.", "Neighbouring passages (under 1.5 s) are joined into one piece; “Add N pieces” undoes with a single ⌘Z.")]) +
      note(("Une piste fine sous la forme d'onde montre les passages (orange : retenus, gris : écartés) ; un clic y amène la tête de lecture.", "A thin lane under the waveform shows the passages (orange: kept, grey: dropped); a click moves the playhead there.")),
      ("Trouver", "Find"))

# 4 --------------------------------------------------------------------------------------------------------------------------------------
d.opener("3", ("Personnages", "Characters"),
         ("macOS ne propose aucune reconnaissance de visages publique. mSLICE propose donc, en option, un petit modèle externe : téléchargé seulement si vous l'acceptez, vérifié, supprimable.",
          "macOS offers no public face recognition. So mSLICE offers, as an option, a small external model: downloaded only if you agree, verified, removable."),
         "../img/spot-faces.jpg", ("Personnages", "Characters"))

d.add(title(("Le modèle", "The model"), ("Quatre candidats, un choix", "Four candidates, one choice")) +
      fig((D.models("fr"), D.models("en")), ("Figure 4 — Qualité du regroupement par personne (AUC) sur 202 visages nets et 543 visages difficiles de la vidéo de test.", "Figure 4 — Quality of person grouping (AUC) on 202 clear and 543 hard faces of the test video.")) +
      table((["Modèle", "Licence", "Taille", "Vitesse", "Verdict"], ["Model", "Licence", "Size", "Speed", "Verdict"]),
            [(["Empreinte d'Apple", "système", "0", "2,3 ms", "mélange les personnes"], ["Apple feature print", "system", "0", "2.3 ms", "mixes people up"]),
             (["DINOv2-S", "Apache 2.0", "41 Mo", "2,7 ms", "suit le décor, pas la personne"], ["DINOv2-S", "Apache 2.0", "41 MB", "2.7 ms", "follows the set, not the person"]),
             (["SFace", "Apache 2.0, données non documentées", "18 Mo", "0,6 ms", "très bon, provenance incertaine"], ["SFace", "Apache 2.0, training data undocumented", "18 MB", "0.6 ms", "very good, uncertain provenance"]),
             (["<b>AuraFace</b>", "Apache 2.0, usage commercial", "63 Mo", "1,7 ms", "<b>retenu</b>"], ["<b>AuraFace</b>", "Apache 2.0, commercial use", "63 MB", "1.7 ms", "<b>chosen</b>"])]) +
      note(("InsightFace / ArcFace d'InsightFace (non commercial), EdgeFace (CC BY-NC-SA) et DINOv3 (licence restreinte) ont été écartés pour leur licence.", "InsightFace / ArcFace by InsightFace (non-commercial), EdgeFace (CC BY-NC-SA) and DINOv3 (restricted licence) were ruled out for their licences.")),
      ("Personnages", "Characters"))

d.add(title(("La chaîne", "The pipeline"), ("De l'image au personnage", "From frame to character")) +
      fig((D.faces("fr"), D.faces("en")), ("Figure 5 — La reconnaissance des personnages, dans le processus d'analyse.", "Figure 5 — Character recognition, inside the analysis process.")) +
      text(["Une image par seconde : Vision trouve les visages et cinq repères (pupilles, nez, coins de la bouche) ; le visage est <b>aligné sur le gabarit ArcFace</b> (112 × 112) puis passé au modèle (moteur neuronal, 1,7 ms) qui rend une empreinte de 512 valeurs. Les visages de deux images voisines d'un même plan dont les boîtes se recouvrent forment un <b>suivi</b>.",
            "Le regroupement est une <b>liaison moyenne</b> (similarité 0,30, soit une distance de 0,70) qui part des suivis, avec une règle stricte : <b>jamais deux visages d'une même image dans le même personnage</b>. Réunir est facile, séparer ne l'est pas : le panneau permet de réunir ou de séparer à la main."],
           ["One frame per second: Vision finds the faces and five landmarks (pupils, nose, mouth corners); the face is <b>aligned on the ArcFace template</b> (112 × 112), then fed to the model (neural engine, 1.7 ms), which returns a 512-value embedding. Faces from neighbouring frames of one shot whose boxes overlap form a <b>track</b>.",
            "Grouping is an <b>average linkage</b> (similarity 0.30, i.e. distance 0.70) starting from tracks, with a strict rule: <b>never two faces from one frame in the same character</b>. Joining is easy, splitting is not: the panel lets you join or split by hand."], tags=True) +
      stats([("1 845", ("visages trouvés dans 28 min", "faces found in 28 min")), ("50", ("personnages (1 617 visages rattachés)", "characters (1,617 faces attached)")), ("22<small> s</small>", ("pour toute la vidéo", "for the whole video")), ("278<small> Mo</small>", ("de pic, rendus à la fin du processus", "peak, released when the process ends"))]),
      ("Personnages", "Characters"))

# 5 --------------------------------------------------------------------------------------------------------------------------------------
d.add(title(("Sécurité et vie privée", "Security and privacy"), ("Rien ne sort du Mac, rien n'est installé sans accord", "Nothing leaves the Mac, nothing installs without consent")) +
      text(["Toutes les analyses se font sur le Mac. La seule connexion réseau liée à l'analyse est le téléchargement du modèle des personnages, que l'utilisateur déclenche lui-même ; la requête ne contient que l'adresse du fichier.",
            "Les garde-fous sont les mêmes pour l'appli et pour l'agent, et chacun est couvert par un essai automatique."],
           ["All analysis runs on the Mac. The only network connection tied to analysis is the download of the characters model, which the user starts; the request contains only the file's address.",
            "The guardrails are the same for the app and the agent, and each one is covered by an automatic test."], lead=True, tags=True) +
      table((["Garde-fou", "Comment"], ["Guardrail", "How"]),
            [(["Téléchargement du modèle", "HTTPS seulement (HTTP uniquement vers cette machine, pour les essais) ; taille plafonnée à 1,5 fois l'annoncée ; empreinte SHA-256 vérifiée avant toute installation ; installation atomique."], ["Model download", "HTTPS only (HTTP only to this machine, for tests); size capped at 1.5× the announced one; SHA-256 checked before any installation; atomic install."]),
             (["Archive du modèle", "Liste des entrées inspectée avant extraction (ni chemin absolu, ni « .. », taille décompressée plafonnée), aucun lien symbolique toléré, seuls le modèle compilé, la licence et la notice sont gardés."], ["Model archive", "Entry list inspected before extraction (no absolute path, no “..”, capped unpacked size), no symbolic link tolerated, only the compiled model, licence and notice are kept."]),
             (["Avant chaque usage", "L'empreinte de l'arbre de fichiers compilé est recalculée : un modèle remplacé ou altéré n'est jamais chargé."], ["Before every use", "The compiled file tree's hash is recomputed: a replaced or tampered model is never loaded."]),
             (["Fichiers d'index", "Binaires, versionnés, refusés s'ils sont tronqués ou incohérents (comptes, valeurs non finies, instants non triés, groupes hors table)."], ["Index files", "Binary, versioned, refused when truncated or inconsistent (counts, non-finite values, unsorted times, groups out of range)."]),
             (["Agent", "Ne crée que de nouveaux fichiers ; ne supprime et n'écrase jamais ; refuse liens symboliques et caractères de contrôle ; ne télécharge jamais le modèle ; dossier d'export borné."], ["Agent", "Only creates new files; never deletes or overwrites; refuses symbolic links and control characters; never downloads the model; export folder bounded."]),
             (["Processus séparé", "Un plantage d'un modèle d'Apple ne touche pas l'appli ; l'annulation arrête le processus en 0,1 s ; il s'arrête si l'appli disparaît."], ["Separate process", "A crash in an Apple model does not touch the app; cancelling stops the process in 0.1 s; it exits if the app disappears."])]),
      ("Sécurité", "Security"))

# 6 --------------------------------------------------------------------------------------------------------------------------------------
d.add(title(("Agent", "Agent"), ("Un pilote que l'on peut débrancher", "A pilot you can unplug")) +
      fig((D.agent("fr"), D.agent("en")), ("Figure 6 — Du client MCP aux fichiers : un seul cœur d'outils.", "Figure 6 — From the MCP client to the files: one set of tools.")) +
      text(["L'agent est <b>désactivé par défaut</b> (réglage « Autoriser un agent »). Un panneau de discussion (Claude Code, API Anthropic, Ollama / LM Studio / OpenAI) et un serveur MCP (<code>mslice-mcp</code>, pour Claude Code, Claude Desktop, Cursor, Codex, Gemini CLI) donnent accès aux mêmes 21 outils.",
            "<b>Lecture</b> : <code>get_state</code>, <code>probe_media</code>, <code>find_silences</code>, <code>get_frame</code>, <code>analyze_media</code>, <code>find_scenes</code>, <code>list_subjects</code>, <code>get_segments</code>. <b>Morceaux</b> : <code>set_segments</code>, <code>add_segment</code>, <code>remove_segment</code>, <code>clear_segments</code>, <code>trim_edges</code>, <code>trim_silences</code>, <code>split_on_silence</code>, <code>name_subject</code>. <b>Sortie</b> : <code>preview_export</code>, <code>export</code>, <code>batch_trim</code>. <b>Appli</b> : <code>open_in_app</code>, <code>seek</code>."],
           ["The agent is <b>off by default</b> (the “Allow an agent” setting). A chat panel (Claude Code, Anthropic API, Ollama / LM Studio / OpenAI) and an MCP server (<code>mslice-mcp</code>, for Claude Code, Claude Desktop, Cursor, Codex, Gemini CLI) give access to the same 21 tools.",
            "<b>Read</b>: <code>get_state</code>, <code>probe_media</code>, <code>find_silences</code>, <code>get_frame</code>, <code>analyze_media</code>, <code>find_scenes</code>, <code>list_subjects</code>, <code>get_segments</code>. <b>Pieces</b>: <code>set_segments</code>, <code>add_segment</code>, <code>remove_segment</code>, <code>clear_segments</code>, <code>trim_edges</code>, <code>trim_silences</code>, <code>split_on_silence</code>, <code>name_subject</code>. <b>Output</b>: <code>preview_export</code>, <code>export</code>, <code>batch_trim</code>. <b>App</b>: <code>open_in_app</code>, <code>seek</code>."], tags=True) +
      note(("Exemple : « garde toutes les apparitions de ce personnage, sauf quand il y a de la musique, et fusionne » enchaîne <code>find_scenes</code> (<code>person:</code>, <code>exclude</code>) → <code>preview_export</code> → <code>export</code>.", "Example: “keep every appearance of this character, except when there is music, and merge” chains <code>find_scenes</code> (<code>person:</code>, <code>exclude</code>) → <code>preview_export</code> → <code>export</code>.")),
      ("Agent", "Agent"))

# 7 --------------------------------------------------------------------------------------------------------------------------------------
d.add(title(("Mesures et essais", "Measurements and tests"), ("Ce qui a été mesuré, pas promis", "Measured, not promised")) +
      fig((D.timing("fr"), D.timing("en")), ("Figure 7 — Vidéo de test de 28 min 05 s (1080p, M5 Max).", "Figure 7 — 28 min 05 s test video (1080p, M5 Max).")) +
      table((["Critère", "Mesure"], ["Criterion", "Measure"]),
            [(["Analyse de 28 min", "25 s (critère : 90 s) · pic de 58 Mo dans le processus (critère : 250 Mo)"], ["28-minute analysis", "25 s (target: 90 s) · 58 MB peak in the process (target: 250 MB)"]),
             (["Personnages", "22 s · pic de 278 Mo, modèle chargé compris (critère de cette passe optionnelle : 300 Mo) · annulation en 0,1 s"], ["Characters", "22 s · 278 MB peak with the model loaded (target for this optional pass: 300 MB) · cancel in 0.1 s"]),
             (["Au repos", "0 % de processeur ; mémoire de l'appli identique avant et après l'analyse"], ["At rest", "0 % CPU; the app's memory is the same before and after analysis"]),
             (["Coupures", "425 sur 428 exactes à l'image près sur le fichier complet ; 50 sur 50 sur un extrait de 2 min 30"], ["Cuts", "425 of 428 frame-exact on the full file; 50 of 50 on a 2 min 30 excerpt"])]) +
      text(["Essais automatiques sans fenêtre : <code>--selftest-analysis</code> (vocabulaires, index, requêtes, regroupement sur données à vérité connue, vraie reconnaissance, annulation, modèle altéré, archives hostiles), <code>--selftest-ui</code> (interface et pont vers l'agent), <code>scripts/mcp_e2e.py</code> (serveur autonome, garde-fous, entrées hostiles), <code>--check-l10n</code> (362 textes × 4 langues).",
            ],
           ["Automatic windowless tests: <code>--selftest-analysis</code> (vocabularies, index, queries, grouping on known-truth data, real recognition, cancel, tampered model, hostile archives), <code>--selftest-ui</code> (interface and agent bridge), <code>scripts/mcp_e2e.py</code> (standalone server, guardrails, hostile inputs), <code>--check-l10n</code> (362 texts × 4 languages)."], tags=True),
      ("Mesures", "Measurements"))

# 8 --------------------------------------------------------------------------------------------------------------------------------------
d.add(title(("Décisions", "Decisions"), ("Ce qu'on a choisi, ce qu'on assume", "What we chose, what we accept")) +
      fig((D.folders("fr"), D.folders("en")), ("Figure 8 — Ce que mSLICE écrit sur le disque (jamais dans vos dossiers de médias).", "Figure 8 — What mSLICE writes to disk (never into your media folders).")) +
      table((["Décision", "Raison"], ["Decision", "Why"]),
            [(["Processus d'analyse séparé", "Vision et SoundAnalysis gardent ≈ 30 Mo qu'elles ne rendent pas ; le processus les libère en se terminant."], ["Separate analysis process", "Vision and SoundAnalysis keep ≈ 30 MB they never give back; the process frees them by exiting."]),
             (["Modèle des personnages optionnel et jamais embarqué", "63 Mo de plus pour tous, sans besoin pour la plupart ; téléchargement avec accord, vérifié, supprimable."], ["Optional, never-bundled characters model", "63 MB more for everyone, unneeded by most; download with consent, verified, removable."]),
             (["Visages seulement en 1.3", "Aucun candidat Apache 2.0 convaincant pour les créatures ou les costumes (DINOv2-S : AUC 0,77) : il faut d'abord un film d'essai avec des créatures."], ["Faces only in 1.3", "No convincing Apache 2.0 candidate for creatures or costumes (DINOv2-S: AUC 0.77): a test film with creatures comes first."]),
             (["Réunir facile, séparer prudent", "Une coupure de regroupement plutôt stricte et des corrections à la main : une fusion malheureuse se défait d'un clic droit."], ["Joining easy, splitting careful", "A fairly strict grouping cut and manual fixes: an unlucky merge is undone with a right-click."])]) +
      note(("<b>Suite (1.4)</b> : recherche libre par texte (« explosion », « dragon », « poursuite en voiture ») avec un second modèle, téléchargé à la demande. <b>Limites connues</b> : seuls les changements de plan francs sont détectés (pas les fondus) ; réglages mesurés sur une seule vidéo.", "<b>Next (1.4)</b>: free text search (“explosion”, “dragon”, “car chase”) with a second model, downloaded on request. <b>Known limits</b>: only hard cuts are detected (no dissolves); settings measured on a single video.")),
      ("Décisions", "Decisions"))

if __name__ == "__main__":
    out = d.to_pdf(os.path.join(HERE, "..", "pdf"))
    print(out)
