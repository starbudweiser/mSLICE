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
      bullets([("<b>Mat et plat</b> : des aplats, un filet d'1 px, aucune ombre, aucun flou.", "<b>Matte and flat</b>: flat fills, a 1 px hairline, no shadow, no blur."),
               ("<b>Le « m » orange</b> : le « m » du nom mSLICE prend toujours l'orange du logo.", "<b>The orange “m”</b>: the “m” of the mSLICE name always takes the logo's orange."),
               ("<b>Police du système</b> (SF Pro) ; chiffres de largeur fixe pour les durées.", "<b>System font</b> (SF Pro); fixed-width digits for durations.")]) +
      bi2("<h4>Composants</h4>" + comp.format(a="Bouton", b="Principal", c="Extraire", p="Musique", t="2 s · 19 plans"), "<h4>Components</h4>" + comp.format(a="Button", b="Primary", c="Extract", p="Music", t="2 s · 19 shots")),
      ("Design", "Design"))

# 2 --------------------------------------------------------------------------------------------------------------------------------------
marks = [(48, 3), (2.4, 11.5), (48, 31), (48, 63), (48, 80), (73.2, 9.6), (73.2, 20), (73.2, 60)]
leg_items = [("Barre du haut", "Top bar", "nom du fichier, raccourcis, réglages", "file name, shortcuts, settings"),
             ("Fichiers ouverts", "Open files", "un fichier = une session", "one file = one session"),
             ("Lecteur", "Player", "image exacte, suit la souris", "exact frame, follows the mouse"),
             ("Commandes", "Controls", "lecture, entrée I, sortie O", "play, in I, out O"),
             ("Timeline", "Timeline", "vignettes, onde, morceaux orange", "thumbnails, waveform, orange pieces"),
             ("Panneau de droite", "Right panel", "Édition, Trouver, Agent", "Edit, Find, Agent"),
             ("Morceaux", "Pieces", "liste, noms, durée gardée", "list, names, kept duration"),
             ("Export", "Export", "format, dossier, bouton Extraire", "format, folder, Extract button")]
legend_html = '<ol class="legend" style="font-size:11pt">' + "".join(f"<li><b>{a}</b> / {b}<br><span style='color:#4f493f'>{c}<br>{d_}</span></li>" for a, b, c, d_ in leg_items) + "</ol>"
d.add(title(("Fenêtre", "Window"), ("Une fenêtre, huit zones", "One window, eight zones")) +
      f'<div style="display:grid;grid-template-columns:62% 1fr;gap:9mm;align-items:start"><figure style="margin:0">{marked("../img/ui-edit-fr-dark.jpg", marks)}<figcaption>Figure 2 — La fenêtre (thème sombre, interface en français). / The window (dark theme, French interface).</figcaption></figure><div>{legend_html}</div></div>',
      ("Fenêtre", "Window"))

# 3 --------------------------------------------------------------------------------------------------------------------------------------
d.add(title(("Édition", "Editing"), ("Le bistouri et la timeline", "The scalpel and the timeline")) +
      fig((img("../img/timeline-fr.jpg"), img("../img/timeline-en.jpg")), ("Figure 3 — Trois morceaux sur la timeline ; le 2 est sélectionné.", "Figure 3 — Three pieces on the timeline; piece 2 is selected."), shot=True) +
      text(["<kbd>I</kbd> pose l'entrée, <kbd>O</kbd> pose la sortie et crée le morceau. Vous pouvez en garder autant que vous voulez, et glisser chaque poignée pour ajuster.",
            "<b>Aimant : images clés</b> cale la coupure sur une image clé (utile en copie directe). <b>Auto : silences début / fin</b> retire d'un clic le silence du début et de la fin."],
           ["<kbd>I</kbd> sets the in point, <kbd>O</kbd> sets the out point and creates the piece. Keep as many as you like, and drag each handle to adjust.",
            "<b>Snap: keyframes</b> snaps the cut to a keyframe (useful for direct copy). <b>Auto: start/end silence</b> removes the opening and closing silence in one click."], tags=True) +
      note(("Sans recompression, une vidéo ne peut démarrer que sur une image clé : l'interface vous dit de combien l'entrée a reculé.", "Without re-encoding, a video can only start on a keyframe: the interface tells you how far the in point moved back.")),
      ("Édition", "Editing"))

pan = lambda n, l, w="52mm": f'<img src="../img/panel-{n}-{l}.jpg" alt="" style="width:{w};border-radius:9px;box-shadow:0 1mm 3mm rgba(38,35,30,.25)">'


def side(img_fr, img_en, fr, en):
    """Colonne bilingue : capture à gauche, texte à droite, dans chaque langue."""
    f = f'<div style="display:flex;gap:6mm;align-items:flex-start">{img_fr}<div style="flex:1">{fr}</div></div>'
    e = f'<div style="display:flex;gap:6mm;align-items:flex-start">{img_en}<div style="flex:1">{en}</div></div>'
    return bi2(f, e)


d.add(title(("Édition", "Editing"), ("Morceaux et export", "Pieces and export")) +
      side(pan("edit", "fr"), pan("edit", "en"),
           "<h4>Morceaux</h4><p>Chaque morceau a un numéro et un nom de fichier. L'avertissement orange rappelle la copie directe.</p><h4>Un par morceau, ou fusionné</h4><p>Un fichier par morceau (<code>demo_01</code>…), ou tous les morceaux bout à bout.</p><h4>Copie directe ou recompression</h4><p>La copie directe est instantanée et sans perte. « Recompresser » coupe à l'image près.</p><h4>Formats</h4><p>MP4, MOV, MKV, WebM, MP3, M4A, WAV, FLAC, AIFF, Opus, ou le format d'origine.</p>",
           "<h4>Pieces</h4><p>Each piece has a number and a file name. The orange warning reminds you about direct copy.</p><h4>One per piece, or merged</h4><p>One file per piece (<code>demo_01</code>…), or all pieces end to end.</p><h4>Direct copy or re-encode</h4><p>Direct copy is instant and lossless. “Re-encode” cuts frame-exact.</p><h4>Formats</h4><p>MP4, MOV, MKV, WebM, MP3, M4A, WAV, FLAC, AIFF, Opus, or the original format.</p>"),
      ("Édition", "Editing"))

d.add(title(("Édition", "Editing"), ("Pendant l'export", "During export")) +
      fig((f'<img src="../img/ui-export-fr-dark.jpg" alt="">', f'<img src="../img/ui-export-en-dark.jpg" alt="">'), ("Figure 4 — La feuille d'export : un fichier par ligne, avec sa progression.", "Figure 4 — The export sheet: one file per line, with its progress."), shot=True, width="86%") +
      text("L'export ne bloque pas l'appli et s'annule à tout moment. Vos originaux ne sont jamais modifiés.", "Export never blocks the app and can be cancelled at any time. Your originals are never modified.", lead=True, tags=True) +
      note(("Un clic droit dans le Finder propose aussi « Extraire des morceaux avec mSLICE… » et « Élaguer début et fin avec mSLICE… » pour plusieurs fichiers à la fois.", "A right-click in the Finder also offers “Extract pieces with mSLICE…” and “Trim start and end with mSLICE…” for several files at once.")),
      ("Édition", "Editing"))

# 4 --------------------------------------------------------------------------------------------------------------------------------------
d.opener("2", ("Trouver : de l'analyse aux morceaux", "Find: from analysis to pieces"),
         ("Un bouton, quelques secondes, puis des critères à combiner : scènes, sons, personnages. Ce qui est trouvé devient des morceaux ordinaires.",
          "One button, a few seconds, then criteria to combine: scenes, sounds, characters. What is found becomes ordinary pieces."),
         "../img/spot-listen.jpg", ("Trouver", "Find"), right=True)

cardsimg = lambda l: f'<div style="display:flex;gap:5mm;align-items:flex-start"><img src="../img/pcard-before-{l}.jpg" style="width:60mm;border-radius:9px"><img src="../img/pcard-running-{l}.jpg" style="width:60mm;border-radius:9px"></div>'
d.add(title(("Trouver", "Find"), ("Avant et pendant l'analyse", "Before and during analysis")) +
      bi2(f"<figure>{cardsimg('fr')}<figcaption>Figure 5 — À gauche : avant. À droite : en cours.</figcaption></figure>", f"<figure>{cardsimg('en')}<figcaption>Figure 5 — Left: before. Right: running.</figcaption></figure>") +
      text(["<b>Avant</b> : la carte donne la durée prévue (environ 1 s par minute de vidéo) et rappelle que tout reste sur le Mac.",
            "<b>En cours</b> : on peut continuer à travailler, ou cliquer sur « Annuler »."],
           ["<b>Before</b>: the card gives the expected time (about 1 s per minute of video) and says everything stays on the Mac.",
            "<b>Running</b>: you can keep working, or click “Cancel”."], tags=True) +
      note(("Pour un fichier audio, l'analyse ne cherche que des sons.", "For an audio file, the analysis only looks for sounds.")),
      ("Trouver", "Find"))

d.add(title(("Trouver", "Find"), ("Les résultats", "The results")) +
      side(pan("find-results", "fr"), pan("find-results", "en"),
           "<h4>Personnages, scènes, sons</h4><p>Chaque ligne donne le nombre de passages et la durée. Un clic ajoute la ligne à la sélection.</p><h4>Piste de résultats</h4><p>Sous la forme d'onde : orange pour les passages gardés, gris pour les passages écartés. Un clic y amène la tête de lecture.</p><h4>Relancer</h4><p>La flèche en haut de chaque carte relance l'analyse ou la reconnaissance.</p>",
           "<h4>Characters, scenes, sounds</h4><p>Each row gives the number of passages and the duration. A click adds the row to the selection.</p><h4>Results lane</h4><p>Under the waveform: orange for kept passages, grey for dropped ones. A click moves the playhead there.</p><h4>Run again</h4><p>The arrow at the top of each card reruns the analysis or the recognition.</p>"),
      ("Trouver", "Find"))

d.add(title(("Trouver", "Find"), ("La sélection", "The selection")) +
      side(pan("find-choice", "fr"), pan("find-choice", "en"),
           "<h4>Critères</h4><p>Chaque critère est une pastille. Cliquez sur ET ou SAUF pour changer. « + Critère » en ajoute un.</p><h4>Plans entiers</h4><p>Garde le plan complet autour de chaque passage. Éteint : marge de 0,3 s.</p><h4>Passages</h4><p>Cochez ou décochez. Les passages écartés restent visibles, grisés, avec la raison.</p><h4>Ajouter</h4><p>Le bouton annonce le nombre de morceaux et leur durée.</p>",
           "<h4>Criteria</h4><p>Each criterion is a pill. Click AND or EXCEPT to switch. “+ Criterion” adds one.</p><h4>Whole shots</h4><p>Keeps the full shot around each passage. Off: 0.3 s margin.</p><h4>Passages</h4><p>Tick or untick. Dropped passages stay visible, greyed, with the reason.</p><h4>Add</h4><p>The button announces the number of pieces and their duration.</p>"),
      ("Trouver", "Find"))

d.add(title(("Trouver", "Find"), ("Morceaux ajoutés", "Pieces added")) +
      side(pan("find-added", "fr"), pan("find-added", "en"),
           "<p class='lead'>« Alma, sauf quand il y a de la musique, en plans entiers » : un seul morceau de 12 secondes.</p><p>Les morceaux ajoutés apparaissent en orange sur la timeline et dans l'onglet Édition.</p><p><kbd>⌘Z</kbd> annule l'ajout d'un seul coup.</p>",
           "<p class='lead'>“Alma, except when there is music, whole shots”: a single 12-second piece.</p><p>Added pieces appear in orange on the timeline and in the Editing tab.</p><p><kbd>⌘Z</kbd> undoes the addition in one go.</p>"),
      ("Trouver", "Find"))

# 5 --------------------------------------------------------------------------------------------------------------------------------------
d.add(title(("Personnages", "Characters"), ("Des vignettes rondes, des gestes simples", "Round thumbnails, simple gestures")) +
      fig((f'<div class="shot"><img src="../img/ui-find-results-fr-light.jpg" alt=""></div>', f'<div class="shot"><img src="../img/ui-find-results-en-light.jpg" alt=""></div>'), ("Figure 6 — La carte Personnages (thème clair).", "Figure 6 — The Characters card (light theme)."), shot=False, width="80%") +
      bullets([("<b>Clic</b> : ajoute le personnage à la sélection.", "<b>Click</b>: adds the character to the selection."),
               ("<b>Clic droit</b> : renommer, réunir, séparer en deux, ou « Ce n'est pas un personnage ».", "<b>Right-click</b>: rename, join, split in two, or “Not a character”."),
               ("<b>Supprimer</b> retire le modèle de 63 Mo ; les personnages déjà reconnus restent.", "<b>Remove</b> deletes the 63 MB model; already recognised characters stay.")]),
      ("Personnages", "Characters"))

# 6 --------------------------------------------------------------------------------------------------------------------------------------
d.add(title(("Agent", "Agent"), ("Discuter avec le fichier", "Talking to your file")) +
      side(pan("agent", "fr"), pan("agent", "en"),
           "<p class='lead'>Décrivez ce que vous voulez : l'agent pose les morceaux et exporte, toujours vers de nouveaux fichiers.</p><p>Désactivé par défaut : Réglages ▸ « Autoriser un agent ». Claude Code, API Anthropic, ou serveur compatible OpenAI.</p><p>Chaque outil appelé s'affiche dans la conversation ; un refus apparaît en rouge.</p>",
           "<p class='lead'>Describe what you want: the agent places the pieces and exports, always to new files.</p><p>Off by default: Settings ▸ “Allow an agent”. Claude Code, Anthropic API, or an OpenAI-compatible server.</p><p>Each tool called shows in the conversation; a refusal appears in red.</p>"),
      ("Agent", "Agent"))

# 7 --------------------------------------------------------------------------------------------------------------------------------------
d.add(title(("Raccourcis", "Shortcuts"), ("Tout au clavier", "All on the keyboard")) +
      fig((f'<div class="shot"><img src="../img/ui-shortcuts-fr-dark.jpg" alt=""></div>', f'<div class="shot"><img src="../img/ui-shortcuts-en-dark.jpg" alt=""></div>'), ("Figure 7 — La feuille « Raccourcis clavier » (⌘/).", "Figure 7 — The “Keyboard shortcuts” sheet (⌘/)."), shot=False, width="72%") +
      table((["Touche", "Action"], ["Key", "Action"]),
            [(["<kbd>I</kbd> <kbd>O</kbd>", "entrée · sortie (crée le morceau)"], ["<kbd>I</kbd> <kbd>O</kbd>", "in · out (creates the piece)"]),
             (["<kbd>Espace</kbd> <kbd>J</kbd> <kbd>K</kbd> <kbd>L</kbd>", "lecture, vitesses"], ["<kbd>Space</kbd> <kbd>J</kbd> <kbd>K</kbd> <kbd>L</kbd>", "play, speeds"]),
             (["<kbd>←</kbd> <kbd>→</kbd> · <kbd>↑</kbd> <kbd>↓</kbd>", "une image · une image clé"], ["<kbd>←</kbd> <kbd>→</kbd> · <kbd>↑</kbd> <kbd>↓</kbd>", "one frame · one keyframe"]),
             (["<kbd>⌫</kbd> <kbd>⌘Z</kbd> <kbd>⌘↩</kbd>", "supprimer · annuler · extraire"], ["<kbd>⌫</kbd> <kbd>⌘Z</kbd> <kbd>⌘↩</kbd>", "delete · undo · extract"])]),
      ("Raccourcis", "Shortcuts"))

setimg = lambda l: f'<div style="display:flex;gap:5mm;align-items:flex-start"><img src="../img/win-set-{l}.jpg" style="width:42mm;border-radius:9px;box-shadow:0 1mm 3mm rgba(38,35,30,.25)"><img src="../img/win-setag-{l}.jpg" style="width:42mm;border-radius:9px;box-shadow:0 1mm 3mm rgba(38,35,30,.25)"><img src="../img/win-about-{l}.jpg" style="width:28mm;border-radius:9px;box-shadow:0 1mm 3mm rgba(38,35,30,.25)"></div>'
d.add(title(("Réglages", "Settings"), ("Réglages et « À propos »", "Settings and “About”")) +
      bi2(f"<figure>{setimg('fr')}<figcaption>Figure 8 — Général, Agent, À propos.</figcaption></figure>", f"<figure>{setimg('en')}<figcaption>Figure 8 — General, Agent, About.</figcaption></figure>") +
      bullets([("<b>Général</b> : langue (français, anglais, espagnol, italien) et apparence ; export ; Finder ; mises à jour.", "<b>General</b>: language (French, English, Spanish, Italian) and appearance; export; Finder; updates."),
               ("<b>Agent</b> : autoriser, choisir le moteur, copier la configuration pour d'autres agents ; clés gardées dans le Trousseau.", "<b>Agent</b>: allow, choose the engine, copy the setup for other agents; keys kept in the Keychain."),
               ("<b>À propos</b> : version, licence MIT, crédits, lien « ♥ Soutenir le projet ».", "<b>About</b>: version, MIT licence, credits, “♥ Support the project” link.")]),
      ("Réglages", "Settings"))

if __name__ == "__main__":
    out = d.to_pdf(os.path.join(HERE, "..", "pdf"))
    print(out)
