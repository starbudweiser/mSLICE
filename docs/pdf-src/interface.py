"""mSLICE — document « Interface » (FR | EN) : design Flat Mat, anatomie de la fenêtre, onglets Édition, Trouver, Agent, états, raccourcis."""
from lib import *

d = Doc("interface", "Interface", ("Interface", "Interface"), "../img/cover-interface.jpg")
d.cover(("L'interface écran par écran : design Flat Mat, fenêtre, onglets Édition, Trouver et Agent, états, raccourcis, langues.",
         "The interface screen by screen: Flat Mat design, window, Edit, Find and Agent tabs, states, shortcuts, languages."))

d.toc([("1", ("Le design Flat Mat", "The Flat Mat design"), "3"), ("2", ("La fenêtre", "The window"), "5"), ("3", ("Édition : morceaux et export", "Editing: pieces and export"), "6"),
       ("4", ("Trouver : de l'analyse aux morceaux", "Find: from analysis to pieces"), "9"), ("5", ("Personnages", "Characters"), "14"), ("6", ("Agent", "Agent"), "15"), ("7", ("Raccourcis, réglages, langues", "Shortcuts, settings, languages"), "16")])

# 1 --------------------------------------------------------------------------------------------------------------------------------------
d.opener("1", ("Le design Flat Mat", "The Flat Mat design"),
         ("Des surfaces mates et plates, sans ombre ni dégradé : la hiérarchie vient des aplats, de filets d'un pixel et d'une seule couleur d'accent. Clair, sombre ou automatique.",
          "Matte, flat surfaces with no shadows or gradients: hierarchy comes from flat fills, one-pixel hairlines and a single accent colour. Light, dark or automatic."),
         "../img/cover-interface.jpg", ("Design", "Design"))


def sw(name, hexv, fg, role):
    return f'<div class="sw" style="background:{hexv};color:{fg}"><b>{name}</b>{hexv}<br>{role}</div>'


dark = [("Fond", "#131316", "#f5f5f7", "fenêtre"), ("Carte", "#1c1c1f", "#f5f5f7", "contenu"), ("Contrôle", "#2c2c31", "#f5f5f7", "champs, boutons"), ("Texte", "#f5f5f7", "#131316", "principal"),
        ("Accent", "#0a84ff", "#ffffff", "choix actifs"), ("Morceau", "#f08a52", "#2a1d0c", "timeline, « m »"), ("Réussi", "#30d158", "#0c2a14", "validé"), ("Danger", "#ff453a", "#ffffff", "tête de lecture")]
dark_en = ["Background", "Card", "Control", "Text", "Accent", "Piece", "Success", "Danger"]
role_en = ["window", "content", "fields, buttons", "primary", "active choices", "timeline, “m”", "valid", "playhead"]
light = [("Fond", "#f4f1ec", "#26231e", "fenêtre"), ("Carte", "#ffffff", "#26231e", "contenu"), ("Contrôle", "#ebe6de", "#26231e", "champs, boutons"), ("Texte", "#26231e", "#f4f1ec", "principal"),
         ("Accent", "#26231e", "#f4f1ec", "choix actifs (encre)"), ("Morceau", "#d9622b", "#ffffff", "timeline, « m »"), ("Réussi", "#3f8f5a", "#ffffff", "validé"), ("Alerte", "#b7791f", "#ffffff", "à noter")]
light_en = ["Background", "Card", "Control", "Text", "Accent", "Piece", "Success", "Warning"]
role_en2 = ["window", "content", "fields, buttons", "primary", "active choices (ink)", "timeline, “m”", "valid", "heads-up"]
sw_fr = '<div class="grid4">' + "".join(sw(n, h, f, r) for n, h, f, r in dark) + "</div><div style='height:5px'></div><div class='grid4'>" + "".join(sw(n, h, f, r) for n, h, f, r in light) + "</div>"
sw_en = '<div class="grid4">' + "".join(sw(dark_en[i], h, f, role_en[i]) for i, (n, h, f, r) in enumerate(dark)) + "</div><div style='height:5px'></div><div class='grid4'>" + "".join(sw(light_en[i], h, f, role_en2[i]) for i, (n, h, f, r) in enumerate(light)) + "</div>"

comp = ('<div style="background:#131316;border-radius:10px;padding:10px 12px;display:flex;gap:7px;flex-wrap:wrap;align-items:center">'
        '<span style="background:#2c2c31;color:#f5f5f7;border-radius:8px;padding:5px 12px;font-weight:600;font-size:8.6pt">{a}</span>'
        '<span style="background:#0a84ff;color:#fff;border-radius:8px;padding:5px 12px;font-weight:700;font-size:8.6pt">{b}</span>'
        '<span style="background:#e8a257;color:#2a1d0c;border-radius:8px;padding:5px 12px;font-weight:700;font-size:8.6pt">{c}</span>'
        '<span style="background:#2c2c31;color:#f5f5f7;border-radius:99px;padding:3px 4px 3px 10px;font-weight:600;font-size:8.4pt">{p} <span style="color:#98989f">✕</span></span>'
        '<span style="background:rgba(48,209,88,.18);color:#30d158;border-radius:99px;padding:2px 9px;font-weight:600;font-size:8pt">{t}</span>'
        '<span style="display:inline-block;width:30px;height:17px;border-radius:99px;background:#f5f5f7;position:relative"><span style="position:absolute;right:2px;top:2px;width:13px;height:13px;border-radius:50%;background:#131316"></span></span></div>')

d.add(title(("Design", "Design"), ("Une palette, deux thèmes", "One palette, two themes")) +
      bi2(f'<figure>{sw_fr}<figcaption>Figure 1 — Sombre (haut) et clair (bas) : seuls le bleu système et l\'orange du « m » sortent du gris chaud.</figcaption></figure>',
          f'<figure>{sw_en}<figcaption>Figure 1 — Dark (top) and light (bottom): only the system blue and the orange “m” leave the warm grey.</figcaption></figure>') +
      bullets([("<b>Mat et plat</b> : cartes en aplat, filet de 1 px, rayon 12 pour les cartes et les fenêtres, 8 pour les boutons et les champs ; aucune ombre, aucun flou.", "<b>Matte and flat</b>: flat cards, 1 px hairline, radius 12 for cards and windows, 8 for buttons and fields; no shadow, no blur."),
               ("<b>Le « m » orange</b> : partout où le nom de l'appli est écrit dans l'interface, son « m » minuscule prend l'orange du logo (jamais dans un menu déroulant).", "<b>The orange “m”</b>: wherever the app's name is written in the interface, its lowercase “m” takes the logo's orange (never inside a drop-down menu)."),
               ("<b>Mesures</b> : barre du haut 48 pt, contrôles 30 pt, barre latérale 232 pt, panneau de droite 304 pt ; police système (SF Pro), chiffres à chasse fixe pour les durées.", "<b>Metrics</b>: top bar 48 pt, controls 30 pt, sidebar 232 pt, right panel 304 pt; system font (SF Pro), monospaced digits for durations.")]) +
      bi2("<h4>Composants</h4>" + comp.format(a="Bouton", b="Principal", c="Extraire", p="Musique", t="2 s · 19 plans"), "<h4>Components</h4>" + comp.format(a="Button", b="Primary", c="Extract", p="Music", t="2 s · 19 shots")),
      ("Design", "Design"))

# 2 --------------------------------------------------------------------------------------------------------------------------------------
marks = [(48, 3), (2.4, 11.5), (48, 31), (48, 63), (48, 80), (73.2, 9.6), (73.2, 20), (73.2, 60)]
leg = legend([("<b>Barre du haut</b> : nom du fichier, flux (taille, codec, images par seconde), raccourcis, réglages.", "<b>Top bar</b>: file name, streams (size, codec, frame rate), shortcuts, settings."),
              ("<b>Fichiers ouverts</b> : un fichier = une session ; le badge compte les morceaux ; glisser-déposer d'autres fichiers.", "<b>Open files</b>: one file = one session; the badge counts the pieces; drop more files."),
              ("<b>Lecteur</b> : image exacte, badge « Dans le morceau N », la tête de lecture suit la souris image par image.", "<b>Player</b>: exact frame, “In piece N” badge, the playhead follows the mouse frame by frame."),
              ("<b>Commandes</b> : saut, lecture, <kbd>I</kbd> entrée et <kbd>O</kbd> sortie (crée le morceau).", "<b>Controls</b>: jump, play, <kbd>I</kbd> in and <kbd>O</kbd> out (creates the piece)."),
              ("<b>Timeline</b> : règle avec images clés, vignettes, forme d'onde, morceaux en orange avec poignées, zoom.", "<b>Timeline</b>: ruler with keyframes, thumbnails, waveform, orange pieces with handles, zoom."),
              ("<b>Panneau de droite</b> : trois onglets, Édition, Trouver, Agent.", "<b>Right panel</b>: three tabs, Edit, Find, Agent."),
              ("<b>Morceaux</b> : liste numérotée, noms de fichiers, durée gardée ; avertissement de copie directe.", "<b>Pieces</b>: numbered list, file names, kept duration; direct-copy warning."),
              ("<b>Export</b> : un fichier par morceau ou fusionné, copie directe ou recompression, format, dossier, taille estimée.", "<b>Export</b>: one file per piece or merged, direct copy or re-encode, format, folder, estimated size.")])
d.add(title(("Fenêtre", "Window"), ("Une fenêtre, huit zones", "One window, eight zones")) +
      fig((marked("../img/ui-edit-fr-dark.jpg", marks), marked("../img/ui-edit-en-dark.jpg", marks)), ("Figure 2 — La fenêtre de mSLICE (thème sombre).", "Figure 2 — mSLICE's window (dark theme)."), shot=False) +
      bi2(leg[0], leg[1]), ("Fenêtre", "Window"))

# 3 --------------------------------------------------------------------------------------------------------------------------------------
d.add(title(("Édition", "Editing"), ("Le bistouri et la timeline", "The scalpel and the timeline")) +
      fig((img("../img/timeline-fr.jpg"), img("../img/timeline-en.jpg")), ("Figure 3 — Trois morceaux posés sur la timeline ; le 2 est sélectionné.", "Figure 3 — Three pieces on the timeline; piece 2 is selected."), shot=True) +
      text(["<kbd>I</kbd> pose l'entrée, <kbd>O</kbd> la sortie et crée le morceau ; on en garde autant qu'on veut dans le même fichier, et chaque poignée se glisse sur la timeline. Le zoom se règle au curseur, à <kbd>⌘</kbd> + molette ou au pincement ; la vue zoomée se déplace à la molette.",
            "<b>Aimant : images clés</b> cale les coupures sur les images clés (indispensable en copie directe) ; <b>Auto : silences début / fin</b> pose d'un clic un morceau qui exclut le silence d'ouverture et de fin."],
           ["<kbd>I</kbd> sets the in point, <kbd>O</kbd> the out point and creates the piece; keep as many as you like in one file, and drag each handle on the timeline. Zoom with the slider, <kbd>⌘</kbd> + wheel or pinch; pan the zoomed view with the wheel.",
            "<b>Snap: keyframes</b> snaps cuts to keyframes (essential for direct copy); <b>Auto: start/end silence</b> places, in one click, a piece that leaves out the opening and closing silence."], tags=True) +
      note(("Sans recompression, une vidéo ne peut démarrer que sur une image clé : l'entrée se cale sur l'image clé précédente et l'interface l'indique (« le morceau 1 démarre à l'image clé 0:07.9 »).", "Without re-encoding a video can only start on a keyframe: the in point snaps to the previous keyframe and the interface says so (“piece 1 starts at keyframe 0:07.9”).")),
      ("Édition", "Editing"))

pan = lambda n, l, w="52mm": f'<img src="../img/panel-{n}-{l}.jpg" alt="" style="width:{w};border-radius:9px;box-shadow:0 1mm 3mm rgba(38,35,30,.25)">'


def side(img_fr, img_en, fr, en):
    """Colonne bilingue : capture à gauche, texte à droite, dans chaque langue."""
    f = f'<div style="display:flex;gap:6mm;align-items:flex-start">{img_fr}<div style="flex:1">{fr}</div></div>'
    e = f'<div style="display:flex;gap:6mm;align-items:flex-start">{img_en}<div style="flex:1">{en}</div></div>'
    return bi2(f, e)


d.add(title(("Édition", "Editing"), ("Morceaux et export", "Pieces and export")) +
      side(pan("edit", "fr"), pan("edit", "en"),
           "<h4>Morceaux</h4><p>La liste numérote les morceaux, propose un nom de fichier pour chacun (<code>demo_01</code>…) et totalise la durée gardée. L'avertissement orange rappelle la copie directe.</p><h4>Un par morceau ou fusionné</h4><p>« Un par morceau » crée <code>nom_01</code>, <code>nom_02</code>… (la numérotation continue, rien n'est jamais écrasé) ; « Fusionner » assemble les morceaux bout à bout.</p><h4>Sans recompression ou recompresser</h4><p>La copie directe est instantanée et sans perte. « Recompresser » passe par VideoToolbox (H.264, H.265, ProRes en matériel) ou VP9 pour le WebM.</p><h4>Formats</h4><p>Identique, MP4, MOV, MKV, WebM, MP3, M4A, WAV, FLAC, AIFF, Opus. Le dossier, la taille et la durée estimées précèdent le bouton « Extraire ».</p>",
           "<h4>Pieces</h4><p>The list numbers the pieces, suggests a file name for each (<code>demo_01</code>…) and totals the kept duration. The orange warning reminds you about direct copy.</p><h4>One per piece or merged</h4><p>“One per piece” creates <code>name_01</code>, <code>name_02</code>… (numbering continues, nothing is ever overwritten); “Merge” joins the pieces end to end.</p><h4>Direct copy or re-encode</h4><p>Direct copy is instant and lossless. “Re-encode” uses VideoToolbox (hardware H.264, H.265, ProRes) or VP9 for WebM.</p><h4>Formats</h4><p>Same as source, MP4, MOV, MKV, WebM, MP3, M4A, WAV, FLAC, AIFF, Opus. Folder, estimated size and time come before the “Extract” button.</p>"),
      ("Édition", "Editing"))

d.add(title(("Édition", "Editing"), ("Pendant et après l'export", "During and after export")) +
      fig((f'<img src="../img/ui-export-fr-dark.jpg" alt="">', f'<img src="../img/ui-export-en-dark.jpg" alt="">'), ("Figure 4 — Une feuille d'export : un fichier par ligne, progression, annulation.", "Figure 4 — An export sheet: one file per line, progress, cancel."), shot=True) +
      text("Un export ne bloque pas l'appli et s'annule à tout moment. Les originaux ne sont jamais modifiés ; l'option « Mettre l'original à la corbeille après l'export » et « Révéler dans le Finder » sont dans les réglages. Un clic droit dans le Finder propose aussi « Extraire des morceaux avec mSLICE… » et « Élaguer début et fin avec mSLICE… » (traitement par lot).",
           "An export never blocks the app and can be cancelled at any time. Originals are never modified; “Move the original to the Trash after export” and “Reveal in Finder” are in the settings. A right-click in the Finder also offers “Extract pieces with mSLICE…” and “Trim start and end with mSLICE…” (batch).", tags=True),
      ("Édition", "Editing"))

# 4 --------------------------------------------------------------------------------------------------------------------------------------
d.opener("2", ("Trouver : de l'analyse aux morceaux", "Find: from analysis to pieces"),
         ("Un bouton, quelques secondes, puis des critères combinables : scènes, sons, personnages. Ce qui est trouvé devient des morceaux ordinaires.",
          "One button, a few seconds, then combinable criteria: scenes, sounds, characters. What is found becomes ordinary pieces."),
         "../img/spot-listen.jpg", ("Trouver", "Find"), right=True)

cards = lambda l: f'<div style="display:flex;gap:5mm;align-items:flex-start"><img src="../img/pcard-before-{l}.jpg" style="width:60mm;border-radius:9px"><img src="../img/pcard-running-{l}.jpg" style="width:60mm;border-radius:9px"></div>'
d.add(title(("Trouver", "Find"), ("Avant et pendant l'analyse", "Before and during analysis")) +
      bi2(f"<figure>{cards('fr')}<figcaption>Figure 5 — À gauche : avant l'analyse. À droite : en cours.</figcaption></figure>",
          f"<figure>{cards('en')}<figcaption>Figure 5 — Left: before analysis. Right: running.</figcaption></figure>") +
      text(["<b>Avant</b> : la carte annonce la durée réelle (environ 1 s par minute de vidéo), rappelle que tout reste sur le Mac et que le résultat est gardé pour la prochaine ouverture. Le bouton « Analyser » est centré sous le texte.",
            "<b>En cours</b> : « Annuler » prend la place d'« Analyser ». Les sons se terminent en premier, les images suivent ; on peut continuer à travailler. L'analyse se met en pause toute seule pendant la lecture et l'export."],
           ["<b>Before</b>: the card gives the real duration (about 1 s per minute of video), says everything stays on the Mac and that the result is kept for next time. The “Analyze” button sits centred under the text.",
            "<b>Running</b>: “Cancel” takes the place of “Analyze”. Sounds finish first, pictures follow; you can keep working. The analysis pauses by itself during playback and export."], tags=True) +
      note(("Audio seul : l'analyse ne cherche que les sons ; la carte et le texte s'adaptent (« Trouver dans le son »).", "Audio only: the analysis only looks for sounds; the card and its text adapt (“Find in the sound”).")),
      ("Trouver", "Find"))

d.add(title(("Trouver", "Find"), ("Les résultats", "The results")) +
      side(pan("find-results", "fr"), pan("find-results", "en"),
           "<h4>Personnages, scènes, sons</h4><p>Chaque ligne donne la famille, le nombre de passages et la durée totale. Un clic place la famille dans la sélection ; « Afficher les autres » déplie la liste.</p><p>Quand une famille souvent cherchée (feu, feux d'artifice, foule) est absente, la carte le dit au lieu de laisser croire à un oubli.</p><h4>Piste de résultats</h4><p>Dès qu'un critère est choisi, une piste fine apparaît sous la forme d'onde : orange pour les passages retenus, gris pour les passages écartés ; un clic amène la tête de lecture au passage.</p><h4>Réanalyser</h4><p>La flèche en haut de la carte relance l'analyse de scènes et de sons ; la flèche de la carte Personnages relance la reconnaissance.</p>",
           "<h4>Characters, scenes, sounds</h4><p>Each row gives the family, the number of passages and the total duration. A click puts the family in the selection; “Show the other…” unfolds the list.</p><p>When an often-searched family (fire, fireworks, crowd) is missing, the card says so instead of letting you think it was overlooked.</p><h4>Results lane</h4><p>As soon as a criterion is chosen, a thin lane appears under the waveform: orange for kept passages, grey for dropped ones; a click moves the playhead to the passage.</p><h4>Analyze again</h4><p>The arrow at the top of the card reruns the scene and sound analysis; the arrow of the Characters card reruns recognition.</p>"),
      ("Trouver", "Find"))

d.add(title(("Trouver", "Find"), ("Sélection : ET, SAUF, plans entiers", "Selection: AND, EXCEPT, whole shots")) +
      side(pan("find-choice", "fr"), pan("find-choice", "en"),
           "<h4>Critères</h4><p>Chaque critère est une pastille ; le premier est un « ET », les suivants s'enchaînent avec <b>ET</b> ou <b>SAUF</b> (un clic sur le mot bascule). « + Critère » ajoute une scène, un son ou un personnage. Au moins un critère positif est nécessaire : un SAUF seul ne suffit pas.</p><h4>Plans entiers</h4><p>Cale chaque passage sur les coupures du montage : le plan entier est gardé. Désactivé, une marge de 0,3 s entoure le passage.</p><h4>Passages</h4><p>Vignette, temps et durée ; cases à cocher, « tout cocher / tout décocher ». Les passages écartés par un SAUF restent visibles, grisés, avec la raison écrite.</p><h4>Ajouter</h4><p>Le bouton dit combien de morceaux seront ajoutés (passages voisins réunis) et leur durée.</p>",
           "<h4>Criteria</h4><p>Each criterion is a pill; the first is an “AND”, the next ones chain with <b>AND</b> or <b>EXCEPT</b> (click the word to switch). “+ Criterion” adds a scene, a sound or a character. At least one positive criterion is required: an EXCEPT alone is not enough.</p><h4>Whole shots</h4><p>Snaps each passage to the editing cuts: the whole shot is kept. Off, a 0.3 s margin surrounds the passage.</p><h4>Passages</h4><p>Thumbnail, time and duration; checkboxes, “check all / uncheck all”. Passages dropped by an EXCEPT stay visible, greyed, with the reason written.</p><h4>Add</h4><p>The button says how many pieces will be added (neighbouring passages joined) and their duration.</p>"),
      ("Trouver", "Find"))

d.add(title(("Trouver", "Find"), ("Morceaux ajoutés", "Pieces added")) +
      side(pan("find-added", "fr"), pan("find-added", "en"),
           "<p class='lead'>« Alma, sauf quand il y a de la musique, en plans entiers » : un morceau de 12 secondes, le seul passage sans musique.</p><p>Les morceaux ajoutés apparaissent en orange sur la timeline, comme ceux posés au bistouri, et dans l'onglet Édition. <kbd>⌘Z</kbd> annule l'ajout d'un seul coup.</p><p>Le bouton « Ouvrir l'onglet Édition » mène à l'export (bouton sable « Extraire ») : rien ne change dans la façon d'exporter.</p>",
           "<p class='lead'>“Alma, except when there is music, in whole shots”: one 12-second piece, the only passage without music.</p><p>Added pieces appear in orange on the timeline, like those placed with the scalpel, and in the Editing tab. <kbd>⌘Z</kbd> undoes the addition in one go.</p><p>The “Open the Editing tab” button leads to export (the sand “Extract” button): nothing changes in how you export.</p>"),
      ("Trouver", "Find"))

# 5 --------------------------------------------------------------------------------------------------------------------------------------
d.add(title(("Personnages", "Characters"), ("Des vignettes rondes, des gestes simples", "Round thumbnails, simple gestures")) +
      fig((f'<div class="shot"><img src="../img/ui-find-results-fr-light.jpg" alt=""></div>', f'<div class="shot"><img src="../img/ui-find-results-en-light.jpg" alt=""></div>'), ("Figure 6 — La carte Personnages (thème clair) : quatre personnages, deux déjà nommés.", "Figure 6 — The Characters card (light theme): four characters, two already named."), shot=False) +
      bullets([("<b>Télécharger</b> (≈ 60 Mo, avec votre accord) → <b>Reconnaître les personnages</b> → vignettes rondes : nom (ou « Personnage N »), nombre d'apparitions et durée à l'écran.", "<b>Download</b> (≈ 60 MB, with your consent) → <b>Recognise the characters</b> → round thumbnails: name (or “Character N”), number of appearances and time on screen."),
               ("<b>Clic</b> : ajoute le personnage à la sélection. <b>Clic droit</b> : renommer, réunir avec un autre, séparer en deux, « Ce n'est pas un personnage ».", "<b>Click</b>: adds the character to the selection. <b>Right-click</b>: rename, join with another, split in two, “Not a character”."),
               ("<b>Supprimer</b> retire le modèle de 63 Mo ; les personnages déjà reconnus restent consultables.", "<b>Remove</b> deletes the 63 MB model; already recognised characters stay available.")]),
      ("Personnages", "Characters"))

# 6 --------------------------------------------------------------------------------------------------------------------------------------
d.add(title(("Agent", "Agent"), ("Discuter avec le fichier", "Talking to your file")) +
      side(pan("agent", "fr"), pan("agent", "en"),
           "<p class='lead'>L'onglet Agent est un panneau de discussion : on décrit ce qu'on veut, l'agent pose les morceaux et exporte, toujours vers de nouveaux fichiers.</p><p>Désactivé par défaut : « Autoriser un agent » dans les réglages. Moteurs : Claude Code, API Anthropic, ou tout serveur compatible OpenAI (Ollama, LM Studio…).</p><p>Chaque outil appelé s'affiche dans la conversation (« set_segments · fichier.mov ») avec son état ; un refus du garde-fou apparaît en rouge. Suggestions de départ : « Retire les silences du début et de la fin », « Garde seulement ce qui se dit, sans les silences, et fusionne ».</p><p>Le même jeu d'outils est exposé par le serveur MCP <code>mslice-mcp</code> à Claude Code, Claude Desktop, Cursor, Codex et Gemini CLI.</p>",
           "<p class='lead'>The Agent tab is a chat panel: describe what you want, the agent places the pieces and exports, always to new files.</p><p>Off by default: “Allow an agent” in the settings. Engines: Claude Code, Anthropic API, or any OpenAI-compatible server (Ollama, LM Studio…).</p><p>Each tool called shows in the conversation (“set_segments · file.mov”) with its state; a guardrail refusal appears in red. Starter suggestions: “Remove the silence at the start and end”, “Keep only what is said, without silences, and merge”.</p><p>The same tool set is exposed by the <code>mslice-mcp</code> MCP server to Claude Code, Claude Desktop, Cursor, Codex and Gemini CLI.</p>"),
      ("Agent", "Agent"))

# 7 --------------------------------------------------------------------------------------------------------------------------------------
d.add(title(("Raccourcis et réglages", "Shortcuts and settings"), ("Tout au clavier, en quatre langues", "All on the keyboard, in four languages")) +
      fig((f'<div class="shot"><img src="../img/ui-shortcuts-fr-dark.jpg" alt=""></div>', f'<div class="shot"><img src="../img/ui-shortcuts-en-dark.jpg" alt=""></div>'), ("Figure 7 — La feuille « Raccourcis clavier » (⌘/).", "Figure 7 — The “Keyboard shortcuts” sheet (⌘/)."), shot=False, width="80%") +
      table((["Touche", "Action"], ["Key", "Action"]),
            [(["<kbd>I</kbd> <kbd>O</kbd>", "entrée / sortie (crée le morceau)"], ["<kbd>I</kbd> <kbd>O</kbd>", "in / out (creates the piece)"]),
             (["<kbd>Espace</kbd> <kbd>J</kbd> <kbd>K</kbd> <kbd>L</kbd>", "lecture, vitesses"], ["<kbd>Space</kbd> <kbd>J</kbd> <kbd>K</kbd> <kbd>L</kbd>", "play, speeds"]),
             (["<kbd>←</kbd> <kbd>→</kbd> · <kbd>⇧←</kbd> <kbd>⇧→</kbd>", "une image · une seconde"], ["<kbd>←</kbd> <kbd>→</kbd> · <kbd>⇧←</kbd> <kbd>⇧→</kbd>", "one frame · one second"]),
             (["<kbd>↑</kbd> <kbd>↓</kbd> · <kbd>[</kbd> <kbd>]</kbd>", "image clé · morceau précédent / suivant"], ["<kbd>↑</kbd> <kbd>↓</kbd> · <kbd>[</kbd> <kbd>]</kbd>", "keyframe · previous / next piece"]),
             (["<kbd>⌫</kbd> <kbd>⌘Z</kbd> <kbd>⌘↩</kbd>", "supprimer le morceau · annuler · extraire"], ["<kbd>⌫</kbd> <kbd>⌘Z</kbd> <kbd>⌘↩</kbd>", "delete the piece · undo · extract"])]) +
      note(("<b>Langues</b> : français, anglais, espagnol, italien, choisies d'après la langue du Mac (anglais si elle n'est pas l'une des quatre) ou dans les réglages. <b>Thème</b> : clair, sombre ou automatique. <b>Mises à jour</b> : recherche quotidienne, installation automatique facultative.", "<b>Languages</b>: French, English, Spanish, Italian, chosen from the Mac's language (English when it is none of the four) or in the settings. <b>Theme</b>: light, dark or automatic. <b>Updates</b>: daily check, optional automatic installation.")),
      ("Raccourcis", "Shortcuts"))

d.add(title(("Réglages", "Settings"), ("Réglages et fenêtre « À propos »", "Settings and the “About” window")) +
      bi2('<div style="display:flex;gap:5mm;align-items:flex-start"><img src="../img/win-set-fr.jpg" style="width:42mm;border-radius:9px;box-shadow:0 1mm 3mm rgba(38,35,30,.25)"><img src="../img/win-setag-fr.jpg" style="width:42mm;border-radius:9px;box-shadow:0 1mm 3mm rgba(38,35,30,.25)"><img src="../img/win-about-fr.jpg" style="width:28mm;border-radius:9px;box-shadow:0 1mm 3mm rgba(38,35,30,.25)"></div><figcaption>Figure 8 — Général et export, page Agent, À propos.</figcaption>',
          '<div style="display:flex;gap:5mm;align-items:flex-start"><img src="../img/win-set-en.jpg" style="width:42mm;border-radius:9px;box-shadow:0 1mm 3mm rgba(38,35,30,.25)"><img src="../img/win-setag-en.jpg" style="width:42mm;border-radius:9px;box-shadow:0 1mm 3mm rgba(38,35,30,.25)"><img src="../img/win-about-en.jpg" style="width:28mm;border-radius:9px;box-shadow:0 1mm 3mm rgba(38,35,30,.25)"></div><figcaption>Figure 8 — General and export, Agent page, About.</figcaption>') +
      bullets([("<b>Général</b> : langue (automatique d'après le Mac, ou l'une des quatre) et apparence. <b>Export</b> : chiffres de la numérotation, nom du fichier fusionné, révéler dans le Finder, mettre l'original à la corbeille. <b>Finder</b> : état de l'extension du clic droit. <b>Mises à jour</b> : installation automatique et recherche manuelle.", "<b>General</b>: language (automatic from the Mac, or one of the four) and appearance. <b>Export</b>: numbering digits, merged file name, reveal in Finder, move the original to the Trash. <b>Finder</b>: right-click extension status. <b>Updates</b>: automatic installation and manual check."),
               ("<b>Agent</b> : autoriser l'agent ; moteur (Claude Code détecté automatiquement, API Anthropic ou compatible OpenAI) ; clés conservées dans le Trousseau, jamais en clair ; boutons de copie (Claude Code, JSON, Codex) pour raccorder d'autres agents ; journal des actions.", "<b>Agent</b>: allow the agent; engine (Claude Code detected automatically, Anthropic API or OpenAI-compatible); keys kept in the Keychain, never in clear; copy buttons (Claude Code, JSON, Codex) to connect other agents; action log."),
               ("<b>À propos</b> : version, licence MIT, crédits (FFmpeg, AuraFace), appartenance au DESKTOP MAC TOOLKIT et lien « ♥ Soutenir le projet ».", "<b>About</b>: version, MIT licence, credits (FFmpeg, AuraFace), membership of the DESKTOP MAC TOOLKIT and the “♥ Support the project” link.")]),
      ("Réglages", "Settings"))

if __name__ == "__main__":
    out = d.to_pdf(os.path.join(HERE, "..", "pdf"))
    print(out)
