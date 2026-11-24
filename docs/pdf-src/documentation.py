"""mSLICE — document « Documentation » (FR | EN) : guide d'utilisation, de l'installation à l'agent."""
from lib import *

d = Doc("documentation", "Documentation", ("Documentation", "Documentation"), "../img/cover-doc.jpg")
d.cover(("Le guide d'utilisation : installer, couper, exporter, trouver des scènes, des sons et des personnages, piloter par un agent.",
         "The user guide: install, cut, export, find scenes, sounds and characters, drive it with an agent."))

d.toc([("1", ("Prise en main", "Getting started"), "3"), ("2", ("Couper et exporter", "Cutting and exporting"), "5"), ("3", ("Trouver", "Find"), "7"), ("4", ("Personnages", "Characters"), "10"),
       ("5", ("Agent et MCP", "Agent and MCP"), "11"), ("6", ("Réglages et données", "Settings and data"), "13"), ("7", ("Dépannage et limites", "Troubleshooting and limits"), "14"), ("8", ("Licences et soutien", "Licences and support"), "15")])

# 1 --------------------------------------------------------------------------------------------------------------------------------------
d.opener("1", ("Prise en main", "Getting started"),
         ("mSLICE élague des fichiers audio et vidéo : on marque des morceaux à garder, on les exporte tels quels ou on les fusionne.",
          "mSLICE trims audio and video files: mark the pieces to keep, then export them as they are or merge them."),
         "../img/spot-slice.jpg", ("Démarrer", "Start"))


def step(n, ft, fb, et, eb):
    return (f'<div class="card"><div style="display:flex;gap:8px;align-items:baseline"><span class="serif m" style="font-size:24pt;line-height:1">{n}</span><h4 style="margin:0">{ft}</h4></div><p style="margin:4px 0 0">{fb}</p></div>',
            f'<div class="card"><div style="display:flex;gap:8px;align-items:baseline"><span class="serif m" style="font-size:24pt;line-height:1">{n}</span><h4 style="margin:0">{et}</h4></div><p style="margin:4px 0 0">{eb}</p></div>')


steps = [step("1", "Télécharger", "Récupérez le <code>.zip</code> de la dernière version sur GitHub (page « Releases »).", "Download", "Get the <code>.zip</code> of the latest version from GitHub (“Releases” page)."),
         step("2", "Installer", "Décompressez, glissez <b>mSLICE.app</b> dans vos Applications. L'appli est signée et notarisée par Apple.", "Install", "Unzip, drag <b>mSLICE.app</b> into Applications. The app is signed and notarised by Apple."),
         step("3", "Ouvrir un fichier", "Glissez-déposez un fichier sur la fenêtre, ouvrez-le par le menu Fichier, ou faites un clic droit dans le Finder.", "Open a file", "Drop a file on the window, open it from the File menu, or right-click it in the Finder."),
         step("4", "Marquer et extraire", "<kbd>I</kbd> pose l'entrée, <kbd>O</kbd> la sortie (crée le morceau). <kbd>⌘↩</kbd> extrait.", "Mark and extract", "<kbd>I</kbd> sets the in point, <kbd>O</kbd> the out point (creates the piece). <kbd>⌘↩</kbd> extracts.")]
d.add(title(("Installation", "Installation"), ("Quatre gestes", "Four gestures")) +
      bi2('<div class="grid2">' + "".join(s[0] for s in steps) + "</div>", '<div class="grid2">' + "".join(s[1] for s in steps) + "</div>") +
      table((["Configuration", "Détail"], ["Requirement", "Detail"]),
            [(["Mac", "Apple Silicon, macOS 14 ou plus récent"], ["Mac", "Apple Silicon, macOS 14 or later"]),
             (["Clic droit dans le Finder", "Activé au premier lancement ; si macOS le demande : Réglages Système ▸ Extensions ▸ Finder"], ["Finder right-click", "Enabled on first launch; if macOS asks: System Settings ▸ Extensions ▸ Finder"]),
             (["Mises à jour", "Recherche quotidienne dans les releases GitHub, signature Developer ID vérifiée, installation automatique facultative (jamais pendant un traitement)"], ["Updates", "Daily check in GitHub releases, Developer ID signature verified, optional automatic installation (never during a task)"]),
             (["Formats lus", "Tout ce que ffprobe sait lire : MOV, MP4, MKV, AVI, WebM, MXF, MTS, WAV, AIFF, MP3, AAC, FLAC, OGG, Opus…"], ["Formats read", "Anything ffprobe can read: MOV, MP4, MKV, AVI, WebM, MXF, MTS, WAV, AIFF, MP3, AAC, FLAC, OGG, Opus…"])]) +
      note(("mSLICE n'a besoin d'aucun compte ni d'aucune connexion : aucun accès réseau, sauf la recherche de mise à jour et, si vous l'acceptez, le téléchargement du modèle des personnages.", "mSLICE needs no account and no connection: no network access, except the update check and, if you agree, the download of the characters model.")),
      ("Démarrer", "Start"))

# 2 --------------------------------------------------------------------------------------------------------------------------------------
d.add(title(("Couper", "Cutting"), ("Marquer des morceaux", "Marking pieces")) +
      fig((img("../img/timeline-fr.jpg"), img("../img/timeline-en.jpg")), ("Une timeline : règle avec images clés, vignettes, forme d'onde, morceaux en orange.", "A timeline: ruler with keyframes, thumbnails, waveform, orange pieces."), shot=True) +
      text(["<b>Bistouri</b> : placez la tête de lecture, <kbd>I</kbd> pour l'entrée, <kbd>O</kbd> pour la sortie, et le morceau existe. Faites-en autant que vous voulez dans le même fichier ; glissez les poignées pour ajuster. <kbd>[</kbd> et <kbd>]</kbd> passent au morceau précédent ou suivant, <kbd>⌫</kbd> supprime le morceau, <kbd>⌘Z</kbd> annule.",
            "<b>Se déplacer</b> : la tête de lecture suit la souris image par image ; <kbd>←</kbd> <kbd>→</kbd> avancent d'une image, <kbd>⇧←</kbd> <kbd>⇧→</kbd> d'une seconde, <kbd>↑</kbd> <kbd>↓</kbd> d'une image clé ; <kbd>J</kbd> <kbd>K</kbd> <kbd>L</kbd> pilotent la lecture. Le zoom se règle au curseur, à <kbd>⌘</kbd> + molette ou au pincement."],
           ["<b>Scalpel</b>: place the playhead, <kbd>I</kbd> for the in point, <kbd>O</kbd> for the out point, and the piece exists. Make as many as you like in the same file; drag the handles to adjust. <kbd>[</kbd> and <kbd>]</kbd> jump to the previous or next piece, <kbd>⌫</kbd> deletes the piece, <kbd>⌘Z</kbd> undoes.",
            "<b>Moving around</b>: the playhead follows the mouse frame by frame; <kbd>←</kbd> <kbd>→</kbd> step one frame, <kbd>⇧←</kbd> <kbd>⇧→</kbd> one second, <kbd>↑</kbd> <kbd>↓</kbd> one keyframe; <kbd>J</kbd> <kbd>K</kbd> <kbd>L</kbd> drive playback. Zoom with the slider, <kbd>⌘</kbd> + wheel or pinch."], tags=True) +
      note(("<b>Aimant : images clés</b> cale les coupures sur les images clés. <b>Auto : silences début / fin</b> pose d'un clic un morceau qui retire le silence d'ouverture et de fin.", "<b>Snap: keyframes</b> snaps cuts to keyframes. <b>Auto: start/end silence</b> places, in one click, a piece that removes the opening and closing silence.")),
      ("Couper", "Cutting"))

d.add(title(("Exporter", "Exporting"), ("Copie directe ou recompression", "Direct copy or re-encode")) +
      text(["<b>Un par morceau</b> crée <code>nom_01</code>, <code>nom_02</code>… ; la numérotation continue d'un export à l'autre et rien n'est jamais écrasé. <b>Fusionner</b> assemble les morceaux bout à bout dans un seul fichier. Le dossier de sortie est, par défaut, celui de l'original.",
            "<b>Sans recompression</b> (copie directe des flux) : instantané, aucune perte. Une vidéo ne peut alors démarrer que sur une image clé : l'entrée se cale sur l'image clé précédente et l'interface vous le dit. <b>Recompresser</b> coupe à l'image près : H.264, H.265 ou ProRes en matériel (VideoToolbox), VP9 pour le WebM."],
           ["<b>One per piece</b> creates <code>name_01</code>, <code>name_02</code>… ; numbering continues from one export to the next and nothing is ever overwritten. <b>Merge</b> joins the pieces end to end into a single file. The output folder is, by default, the original's.",
            "<b>Direct copy</b> (streams copied as they are): instant, lossless. A video can then only start on a keyframe: the in point snaps to the previous keyframe and the interface tells you. <b>Re-encode</b> cuts frame-exact: hardware H.264, H.265 or ProRes (VideoToolbox), VP9 for WebM."], tags=True) +
      table((["Sortie", "Formats"], ["Output", "Formats"]),
            [(["Conteneurs", "Identique à l'original, MP4, MOV, MKV, WebM"], ["Containers", "Same as source, MP4, MOV, MKV, WebM"]),
             (["Audio seul", "MP3 (LAME), M4A, WAV, FLAC, AIFF, Opus"], ["Audio only", "MP3 (LAME), M4A, WAV, FLAC, AIFF, Opus"]),
             (["Réglages", "Chiffres de la numérotation, nom du fichier fusionné, révéler dans le Finder, mettre l'original à la corbeille (jamais par défaut)"], ["Settings", "Numbering digits, merged file name, reveal in Finder, move the original to the Trash (never by default)"])]) +
      h3(("Par lot, depuis le Finder", "In batch, from the Finder")) +
      text("Un clic droit sur plusieurs fichiers propose « Élaguer début et fin avec mSLICE… » : retirez X secondes au début et Y à la fin de chacun, ou laissez mSLICE détecter les silences d'ouverture et de fin. Les résultats sont écrits dans le même dossier, les originaux ne sont jamais modifiés, et un fichier trop court est signalé au lieu d'être traité.",
           "A right-click on several files offers “Trim start and end with mSLICE…”: remove X seconds at the start and Y at the end of each, or let mSLICE detect the opening and closing silence. Results are written in the same folder, originals are never modified, and a file that is too short is reported instead of processed."),
      ("Exporter", "Exporting"))

# 3 --------------------------------------------------------------------------------------------------------------------------------------
d.opener("2", ("Trouver", "Find"),
         ("Repérer, avec les modèles intégrés à macOS, les plans, les scènes et les sons d'un fichier, puis transformer leurs passages en morceaux.",
          "Spot, with the models built into macOS, a file's shots, scenes and sounds, then turn their passages into pieces."),
         "../img/spot-listen.jpg", ("Trouver", "Find"), right=True)

cards = lambda l: f'<div style="display:flex;gap:5mm;align-items:flex-start"><img src="../img/pcard-before-{l}.jpg" style="width:56mm;border-radius:9px"><img src="../img/pcard-running-{l}.jpg" style="width:56mm;border-radius:9px"></div>'
d.add(title(("Analyser", "Analyze"), ("Un bouton, quelques secondes", "One button, a few seconds")) +
      text(["Ouvrez l'onglet <b>Trouver</b> et cliquez sur <b>Analyser</b>. Environ une seconde par minute de vidéo ; vous pouvez continuer à travailler, et l'analyse se met en pause pendant la lecture et l'export. Le résultat est gardé : pas besoin de recommencer à la prochaine ouverture du fichier.",
            "mSLICE y repère les <b>plans</b> (coupures du montage), une quarantaine de <b>familles de scènes</b> et de <b>familles de sons</b>. Tout se passe sur votre Mac avec Vision et SoundAnalysis ; rien n'est envoyé."],
           ["Open the <b>Find</b> tab and click <b>Analyze</b>. About one second per minute of video; you can keep working, and the analysis pauses during playback and export. The result is kept: no need to redo it next time you open the file.",
            "mSLICE spots the <b>shots</b> (editing cuts), about forty <b>scene families</b> and <b>sound families</b>. Everything happens on your Mac with Vision and SoundAnalysis; nothing is sent."], tags=True) +
      table((["Ce que l'on trouve", "Exemples"], ["What you can find", "Examples"]),
            [(["Scènes (45 familles)", "feu et flammes, feux d'artifice, foule, nuit, ville, véhicules et routes, animaux, nourriture, sport, mer, forêt, neige, intérieur, documents, vêtements et costumes, art…"], ["Scenes (45 families)", "fire and flames, fireworks, crowd, night, city, vehicles and roads, animals, food, sport, sea, forest, snow, indoors, documents, clothing and costumes, art…"]),
             (["Sons (42 familles)", "parole, musique, rires, applaudissements, foule, coups de feu, explosions, sirènes, tonnerre, moteurs, eau, chiens, verre brisé…"], ["Sounds (42 families)", "speech, music, laughter, applause, crowd, gunfire, explosions, sirens, thunder, engines, water, dogs, broken glass…"])]) +
      bi2(f"<figure>{cards('fr')}<figcaption>Avant l'analyse (à gauche) et pendant (à droite).</figcaption></figure>", f"<figure>{cards('en')}<figcaption>Before analysis (left) and while it runs (right).</figcaption></figure>") +
      note(("« Explosion » n'existe pas comme étiquette d'image : le son « Explosions » et la scène « Feu et flammes » s'en approchent. Pour les passages entre deux plans en fondu, seule une coupure franche est détectée.", "“Explosion” does not exist as a picture label: the “Explosions” sound and the “Fire and flames” scene come close. Only hard cuts are detected, not dissolves.")),
      ("Trouver", "Find"))

recipe = lambda ft, fb, et, eb: (f'<div class="card"><h4 style="margin-top:0">{ft}</h4><p style="margin:0">{fb}</p></div>', f'<div class="card"><h4 style="margin-top:0">{et}</h4><p style="margin:0">{eb}</p></div>')
rec = [recipe("Tous les rires", "Cliquez sur « Rires » dans la liste des sons, gardez « Plans entiers » éteint (marge de 0,3 s), « Ajouter ».", "Every laugh", "Click “Laughter” in the sounds list, keep “Whole shots” off (0.3 s margin), “Add”."),
       recipe("Les plans de nuit, sans musique", "Cliquez sur « Nuit », puis « + Critère » ▸ « Sauf quand… » ▸ Sons ▸ Musique. « Plans entiers » allumé.", "Night shots, no music", "Click “Night”, then “+ Criterion” ▸ “Except when…” ▸ Sounds ▸ Music. “Whole shots” on."),
       recipe("Le feu ET la foule", "Cliquez sur « Feu et flammes », puis « + Critère » ▸ « Et aussi… » ▸ Scènes ▸ Foule : seuls les passages où les deux sont vrais restent.", "Fire AND crowd", "Click “Fire and flames”, then “+ Criterion” ▸ “And also…” ▸ Scenes ▸ Crowd: only passages where both hold remain."),
       recipe("Une étiquette précise", "Les agents peuvent aussi viser une étiquette brute de macOS (<code>label:fireworks</code>, <code>sound_label:gunshot_gunfire</code>) pour aller plus fin que les familles.", "A precise label", "Agents can also target a raw macOS label (<code>label:fireworks</code>, <code>sound_label:gunshot_gunfire</code>) to go finer than families.")]
d.add(title(("Critères", "Criteria"), ("Combiner ET, SAUF, plans entiers", "Combine AND, EXCEPT, whole shots")) +
      fig((f'<div class="shot"><img src="../img/ui-find-choice-fr-light.jpg" alt=""></div>', f'<div class="shot"><img src="../img/ui-find-choice-en-light.jpg" alt=""></div>'), ("« Alma SAUF musique, en plans entiers » : 1 passage retenu sur 4, trois écartés pour la musique.", "“Alma EXCEPT music, whole shots”: 1 of 4 passages kept, three dropped for music."), width="58%") +
      bi2('<div class="grid2">' + "".join(r[0] for r in rec) + "</div>", '<div class="grid2">' + "".join(r[1] for r in rec) + "</div>") +
      note(("Les passages écartés par un SAUF restent dans la liste, grisés, avec la raison écrite ; vous pouvez les cocher pour les garder malgré tout. « Ajouter N morceaux » est annulable d'un seul <kbd>⌘Z</kbd>.", "Passages dropped by an EXCEPT stay in the list, greyed, with the reason written; you can tick them to keep them anyway. “Add N pieces” undoes with a single <kbd>⌘Z</kbd>.")),
      ("Trouver", "Find"))

# 4 --------------------------------------------------------------------------------------------------------------------------------------
d.add(title(("Personnages", "Characters"), ("Retrouver quelqu'un dans tout le film", "Find someone throughout the film")) +
      bi2('<div style="display:flex;gap:6mm;align-items:flex-start"><img src="../img/panel-find-results-fr-light.jpg" style="width:50mm;border-radius:9px;box-shadow:0 1mm 3mm rgba(38,35,30,.25)"><div style="flex:1">'
          "<h4 style='margin-top:0'>1 · Télécharger le modèle</h4><p>Carte « Personnages » ▸ « Télécharger » (≈ 60 Mo). Facultatif, jamais embarqué : il n'est téléchargé que si vous le demandez, vérifié par son empreinte SHA-256, et supprimable à tout moment.</p>"
          "<h4>2 · Reconnaître</h4><p>« Reconnaître les personnages » : environ une seconde par minute de vidéo, sur votre Mac. Le résultat est gardé avec le fichier.</p>"
          "<h4>3 · Utiliser</h4><p>Un clic sur une vignette ajoute le personnage à la sélection, comme une scène : « ce personnage SAUF musique », en plans entiers.</p>"
          "<h4>4 · Corriger</h4><p>Clic droit : <b>Renommer</b> (le nom suit le personnage partout, y compris pour l'agent), <b>Réunir avec…</b> deux vignettes de la même personne, <b>Séparer en deux</b> un groupe qui mélange deux personnes, <b>Ce n'est pas un personnage</b> pour écarter une affiche ou un reflet.</p></div></div>",
          '<div style="display:flex;gap:6mm;align-items:flex-start"><img src="../img/panel-find-results-en-light.jpg" style="width:50mm;border-radius:9px;box-shadow:0 1mm 3mm rgba(38,35,30,.25)"><div style="flex:1">'
          "<h4 style='margin-top:0'>1 · Download the model</h4><p>“Characters” card ▸ “Download” (≈ 60 MB). Optional, never bundled: it is only downloaded when you ask, verified by its SHA-256 hash, and removable at any time.</p>"
          "<h4>2 · Recognise</h4><p>“Recognise the characters”: about one second per minute of video, on your Mac. The result is kept with the file.</p>"
          "<h4>3 · Use</h4><p>A click on a thumbnail adds the character to the selection, like a scene: “this character EXCEPT music”, whole shots.</p>"
          "<h4>4 · Fix</h4><p>Right-click: <b>Rename</b> (the name follows the character everywhere, including for the agent), <b>Join with…</b> two thumbnails of the same person, <b>Split in two</b> a group that mixes two people, <b>Not a character</b> to drop a poster or a reflection.</p></div></div>") +
      note(("<b>Limites</b> : visages seulement (ni créatures ni costumes) ; les visages de profil, petits ou flous peuvent être mal regroupés : c'est pour cela que réunir et séparer existent. Deux visages d'une même image ne sont jamais réunis dans le même personnage.", "<b>Limits</b>: faces only (no creatures or costumes); profile, small or blurry faces may be grouped wrongly: that is why join and split exist. Two faces from the same frame are never put in the same character.")),
      ("Personnages", "Characters"))

# 5 --------------------------------------------------------------------------------------------------------------------------------------
d.add(title(("Agent", "Agent"), ("Piloter mSLICE avec un agent", "Drive mSLICE with an agent")) +
      text(["L'agent est <b>désactivé par défaut</b>. Pour l'activer : Réglages ▸ Agent ▸ « Autoriser un agent à piloter mSLICE ». Il vaut pour le panneau de discussion et pour le serveur MCP. L'agent crée de nouveaux fichiers ; il ne peut ni supprimer, ni écraser, ni mettre à la corbeille, et n'écrit que dans le dossier du fichier source (ou celui que vous avez choisi pour l'export).",
            "<b>Panneau de discussion</b> (onglet Agent) : <b>Claude Code</b> (détecté automatiquement, utilise votre abonnement sans clé API), <b>API Anthropic</b> ou tout serveur <b>compatible OpenAI</b> (Ollama, LM Studio…). Les clés sont conservées dans le Trousseau, jamais en clair ; « Tester la connexion » vérifie le réglage."],
           ["The agent is <b>off by default</b>. To turn it on: Settings ▸ Agent ▸ “Allow an agent to drive mSLICE”. It applies to the chat panel and to the MCP server. The agent creates new files; it can neither delete, overwrite nor trash anything, and only writes in the source file's folder (or the export folder you chose).",
            "<b>Chat panel</b> (Agent tab): <b>Claude Code</b> (detected automatically, uses your subscription without an API key), <b>Anthropic API</b> or any <b>OpenAI-compatible</b> server (Ollama, LM Studio…). Keys are kept in the Keychain, never in clear; “Test the connection” checks the setup."], tags=True) +
      h3(("Raccorder un autre agent (MCP)", "Connect another agent (MCP)")) +
      bi2("<p>Réglages ▸ Agent ▸ « Raccorder d'autres agents (MCP) » : trois boutons copient la configuration. <code>mslice-mcp</code> est livré dans l'appli et fonctionne fenêtre ouverte ou non.</p><pre>claude mcp add --scope user mslice -- \"/Applications/mSLICE.app/Contents/MacOS/mslice-mcp\"</pre>",
          "<p>Settings ▸ Agent ▸ “Connect other agents (MCP)”: three buttons copy the configuration. <code>mslice-mcp</code> ships inside the app and works with the window open or not.</p><pre>claude mcp add --scope user mslice -- \"/Applications/mSLICE.app/Contents/MacOS/mslice-mcp\"</pre>") +
      bi2("<pre>{ \"mcpServers\": { \"mslice\": { \"command\": \".../mslice-mcp\" } } }   # Claude Desktop, Cursor, Gemini CLI</pre><pre>[mcp_servers.mslice]\ncommand = \".../mslice-mcp\"                    # Codex</pre>",
          "<pre>{ \"mcpServers\": { \"mslice\": { \"command\": \".../mslice-mcp\" } } }   # Claude Desktop, Cursor, Gemini CLI</pre><pre>[mcp_servers.mslice]\ncommand = \".../mslice-mcp\"                    # Codex</pre>") +
      note(("Chaque action de l'agent est notée dans le journal (Réglages ▸ Agent ▸ Journal ▸ Ouvrir). L'appli ouverte met la timeline à jour en direct.", "Every agent action is written in the log (Settings ▸ Agent ▸ Log ▸ Open). With the app open the timeline updates live.")),
      ("Agent", "Agent"))

tools = [("get_state", "État de l'appli, fichiers ouverts, morceaux, valeurs d'export", "App state, open files, pieces, export defaults"),
         ("probe_media", "Durée, flux, codec, images clés (option)", "Duration, streams, codec, keyframes (optional)"),
         ("find_silences", "Intervalles de silence et plages sonores", "Silent intervals and sounding ranges"),
         ("get_frame", "Image PNG à un instant donné", "PNG picture at a given time"),
         ("analyze_media", "Plans, familles de scènes et de sons ; <code>characters=true</code> reconnaît aussi les personnages (modèle installé par l'utilisateur)", "Shots, scene and sound families; <code>characters=true</code> also recognises characters (model installed by the user)"),
         ("find_scenes", "Passages selon <code>include</code> / <code>exclude</code> : <code>scene:</code>, <code>sound:</code>, <code>label:</code>, <code>sound_label:</code>, <code>person:</code> ; <code>apply</code> = none / add / set", "Passages by <code>include</code> / <code>exclude</code>: <code>scene:</code>, <code>sound:</code>, <code>label:</code>, <code>sound_label:</code>, <code>person:</code>; <code>apply</code> = none / add / set"),
         ("list_subjects · name_subject", "Liste les personnages reconnus ; leur donne un nom", "Lists recognised characters; names them"),
         ("get_segments · set_segments", "Lit ou remplace les morceaux (durées en secondes ou m:ss.d)", "Reads or replaces the pieces (times in seconds or m:ss.d)"),
         ("add_segment · remove_segment · clear_segments", "Ajoute, retire, vide les morceaux", "Adds, removes, clears pieces"),
         ("trim_edges · trim_silences · split_on_silence", "Élague début et fin, retire les silences d'ouverture et de fin, découpe aux silences", "Trims start and end, removes opening and closing silence, splits at silences"),
         ("preview_export · export · batch_trim", "Simule puis exporte (copie directe ou recompression), élague plusieurs fichiers", "Dry-runs then exports (direct copy or re-encode), trims several files"),
         ("open_in_app · seek", "Ouvre un fichier dans l'appli, place la tête de lecture", "Opens a file in the app, moves the playhead")]
d.add(title(("Agent", "Agent"), ("Les 21 outils", "The 21 tools")) +
      table((["Outil", "Rôle"], ["Tool", "Role"]), [([f"<code>{n}</code>", fr], [f"<code>{n}</code>", en]) for n, fr, en in tools]) +
      note(("Exemple : « garde toutes les apparitions d'Alma, sauf quand il y a de la musique, et fusionne » → <code>find_scenes</code> (<code>include</code> [\"person:Alma\"], <code>exclude</code> [\"sound:music\"], <code>apply</code> \"set\") → <code>preview_export</code> → <code>export</code> (fusionné).", "Example: “keep every appearance of Alma, except when there is music, and merge” → <code>find_scenes</code> (<code>include</code> [\"person:Alma\"], <code>exclude</code> [\"sound:music\"], <code>apply</code> \"set\") → <code>preview_export</code> → <code>export</code> (merged).")),
      ("Agent", "Agent"))

# 6 --------------------------------------------------------------------------------------------------------------------------------------
d.add(title(("Réglages et données", "Settings and data"), ("Où tout se trouve", "Where everything lives")) +
      table((["Réglage", "Effet"], ["Setting", "Effect"]),
            [(["Général ▸ Langue", "Automatique (langue du Mac) ou français, anglais, espagnol, italien ; anglais si la langue du Mac n'est aucune des quatre"], ["General ▸ Language", "Automatic (the Mac's language) or French, English, Spanish, Italian; English when the Mac's language is none of the four"]),
             (["Général ▸ Apparence", "Clair, sombre ou automatique"], ["General ▸ Appearance", "Light, dark or automatic"]),
             (["Export", "Chiffres de la numérotation, nom du fichier fusionné, révéler dans le Finder, mettre l'original à la corbeille après l'export"], ["Export", "Numbering digits, merged file name, reveal in Finder, move the original to the Trash after export"]),
             (["Finder", "État de l'extension du clic droit ; bouton vers les Réglages Système"], ["Finder", "Right-click extension status; button to System Settings"]),
             (["Mises à jour", "Installer automatiquement ; Rechercher maintenant"], ["Updates", "Install automatically; Check now"]),
             (["Agent", "Autoriser, moteur, clés, MCP, journal"], ["Agent", "Allow, engine, keys, MCP, log"])]) +
      h3(("Ce que mSLICE écrit sur le disque", "What mSLICE writes to disk")) +
      table((["Dossier", "Contenu"], ["Folder", "Content"]),
            [(["<code>~/Library/Application Support/mSLICE/sessions</code>", "les morceaux de chaque fichier, restaurés à la réouverture"], ["<code>~/Library/Application Support/mSLICE/sessions</code>", "each file's pieces, restored on reopening"]),
             (["<code>…/index</code>", "résultats d'analyse (.msidx) et de reconnaissance (.msfaces) ; ≈ 6 Ko par minute"], ["<code>…/index</code>", "analysis (.msidx) and recognition (.msfaces) results; ≈ 6 KB per minute"]),
             (["<code>…/models/characters</code>", "le modèle des personnages, sa licence et sa notice (supprimable depuis la carte Personnages)"], ["<code>…/models/characters</code>", "the characters model, its licence and notice (removable from the Characters card)"]),
             (["<code>…/agent.log</code>", "journal des actions de l'agent"], ["<code>…/agent.log</code>", "log of the agent's actions"])]) +
      note(("Supprimer ces dossiers ne touche jamais à vos médias : mSLICE n'y écrit rien d'autre que ses propres données. Les originaux ne sont jamais modifiés.", "Deleting these folders never touches your media: mSLICE writes nothing there but its own data. Originals are never modified.")),
      ("Réglages", "Settings"))

# 7 --------------------------------------------------------------------------------------------------------------------------------------
d.add(title(("Dépannage", "Troubleshooting"), ("Questions fréquentes", "Frequently asked questions")) +
      table((["Question", "Réponse"], ["Question", "Answer"]),
            [(["Mon morceau démarre avant mon entrée.", "En copie directe, une vidéo ne démarre que sur une image clé : l'entrée se cale sur l'image clé précédente (l'avertissement orange le dit). Choisissez « Recompresser » pour couper à l'image près."], ["My piece starts before my in point.", "With direct copy a video can only start on a keyframe: the in point snaps to the previous keyframe (the orange warning says so). Choose “Re-encode” to cut frame-exact."]),
             (["« L'analyse a échoué ».", "macOS n'a pas pu lire les images ou le son. Réessayez, ou essayez un autre fichier ; les formats que macOS ne lit pas passent par une copie de lecture temporaire."], ["“The analysis failed”.", "macOS could not read the pictures or the sound. Try again, or try another file; formats macOS cannot read go through a temporary playback copy."]),
             (["Le feu, la foule ou le feu d'artifice n'apparaissent pas.", "La carte Scènes dit lesquelles n'ont pas été repérées dans ce fichier. Les familles sont larges (« Personnes » couvre presque tout un dialogue) : combinez-les avec ET."], ["Fire, crowd or fireworks do not show up.", "The Scenes card says which ones were not spotted in this file. Families are broad (“People” covers almost a whole dialogue): combine them with AND."]),
             (["Deux personnes sont réunies en un seul personnage.", "Clic droit sur la vignette ▸ « Séparer en deux ». À l'inverse, « Réunir avec… » regroupe deux vignettes de la même personne."], ["Two people are merged into one character.", "Right-click the thumbnail ▸ “Split in two”. Conversely, “Join with…” merges two thumbnails of the same person."]),
             (["La reconnaissance échoue.", "Le modèle est introuvable ou altéré : supprimez-le depuis la carte Personnages, puis téléchargez-le de nouveau."], ["Recognition fails.", "The model is missing or damaged: remove it from the Characters card, then download it again."]),
             (["Le clic droit du Finder n'apparaît pas.", "Réglages Système ▸ Extensions ▸ Finder, cochez mSLICE ; l'état figure dans les réglages de l'appli."], ["The Finder right-click does not appear.", "System Settings ▸ Extensions ▸ Finder, tick mSLICE; the status is in the app's settings."]),
             (["Un agent n'arrive pas à piloter mSLICE.", "Vérifiez Réglages ▸ Agent ▸ « Autoriser un agent » et ouvrez le journal pour lire le refus."], ["An agent cannot drive mSLICE.", "Check Settings ▸ Agent ▸ “Allow an agent” and open the log to read the refusal."])]),
      ("Dépannage", "Troubleshooting"))

# 8 --------------------------------------------------------------------------------------------------------------------------------------
d.add(title(("Licences et soutien", "Licences and support"), ("Libre, et fait pour durer", "Free, and built to last")) +
      text(["mSLICE est publié sous <b>licence MIT</b> et fait partie du <b>DESKTOP MAC TOOLKIT</b> (Starbudweiser &amp; Claude Code, Anthropic). Le code est sur <b>github.com/starbudweiser/mSLICE</b>.",
            "L'appli embarque <b>FFmpeg</b> (LGPL 2.1, compilé sans GPL), <b>LAME</b>, <b>mpg123</b>, <b>Opus</b> et <b>libvpx</b>. Le modèle optionnel des personnages est <b>AuraFace</b> de fal.ai (Apache 2.0), converti en Core ML ; sa licence et sa notice de modification sont gardées à côté du modèle installé. Le détail est dans <code>THIRD_PARTY_LICENSES.md</code>."],
           ["mSLICE is published under the <b>MIT licence</b> and is part of the <b>DESKTOP MAC TOOLKIT</b> (Starbudweiser &amp; Claude Code, Anthropic). The code is at <b>github.com/starbudweiser/mSLICE</b>.",
            "The app bundles <b>FFmpeg</b> (LGPL 2.1, built without GPL), <b>LAME</b>, <b>mpg123</b>, <b>Opus</b> and <b>libvpx</b>. The optional characters model is fal.ai's <b>AuraFace</b> (Apache 2.0), converted to Core ML; its licence and modification notice are kept next to the installed model. Details are in <code>THIRD_PARTY_LICENSES.md</code>."], lead=True, tags=True) +
      note(("<b>♥ Soutenir le projet</b> : facultatif, discret, aucune fonction bloquée. Le lien est en bas de la fenêtre « À propos » et dans le fichier README ; github.com/sponsors/starbudweiser.", "<b>♥ Support the project</b>: optional, discreet, no feature locked. The link is at the bottom of the “About” window and in the README; github.com/sponsors/starbudweiser.")) +
      stats([("21", ("outils d'agent", "agent tools")), ("4", ("langues, 362 textes chacune", "languages, 362 texts each")), ("0", ("octet envoyé hors du Mac par l'analyse", "bytes sent off the Mac by analysis")), ("1.3", ("version décrite ici", "version described here"))]),
      ("Licences", "Licences"))

if __name__ == "__main__":
    out = d.to_pdf(os.path.join(HERE, "..", "pdf"))
    print(out)
