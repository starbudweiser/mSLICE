"""mSLICE — document « Documentation » (FR | EN) : guide d'utilisation en langage simple, de l'installation à l'agent."""
from lib import *

d = Doc("documentation", "Documentation", ("Documentation", "Documentation"), "../img/cover-doc.jpg")
d.cover(("Le guide d'utilisation : installer, couper, exporter, trouver des scènes, des sons et des personnages, piloter par un agent.",
         "The user guide: install, cut, export, find scenes, sounds and characters, drive it with an agent."))
d.toc([("1", ("Prise en main", "Getting started"), "3"), ("2", ("Couper et exporter", "Cutting and exporting"), "5"), ("3", ("Trouver", "Find"), "7"), ("4", ("Les personnages", "Characters"), "10"),
       ("5", ("L'agent", "The agent"), "11"), ("6", ("Réglages et données", "Settings and data"), "13"), ("7", ("Dépannage", "Troubleshooting"), "14"), ("8", ("Licences et soutien", "Licences and support"), "15")])

# 1 ---------------------------------------------------------------------------------------------------------------------------------------------
d.opener("1", ("Prise en main", "Getting started"),
         ("mSLICE coupe des fichiers audio et vidéo : on marque les morceaux à garder, puis on les exporte tels quels ou on les fusionne.",
          "mSLICE cuts audio and video files: mark the pieces to keep, then export them as they are or merge them."),
         "../img/spot-slice.jpg", ("Démarrer", "Start"))

d.add(title(("Installation", "Installation"), ("Quatre gestes", "Four gestures")) +
      cards([("1 · Télécharger", "Prenez le fichier <code>.zip</code> de la dernière version sur GitHub (page « Releases »).", "1 · Download", "Take the latest <code>.zip</code> from GitHub (“Releases” page)."),
             ("2 · Installer", "Décompressez, puis glissez <b>mSLICE.app</b> dans Applications.", "2 · Install", "Unzip, then drag <b>mSLICE.app</b> into Applications."),
             ("3 · Ouvrir un fichier", "Glissez-le sur la fenêtre, ou faites un clic droit dessus dans le Finder.", "3 · Open a file", "Drop it on the window, or right-click it in the Finder."),
             ("4 · Marquer et extraire", "<kbd>I</kbd> pose l'entrée, <kbd>O</kbd> la sortie. <kbd>⌘↩</kbd> extrait.", "4 · Mark and extract", "<kbd>I</kbd> sets the in point, <kbd>O</kbd> the out point. <kbd>⌘↩</kbd> extracts.")]) +
      table((["Il vous faut", "Détail"], ["You need", "Detail"]),
            [(["Un Mac", "Apple Silicon, macOS 14 ou plus récent"], ["A Mac", "Apple Silicon, macOS 14 or later"]),
             (["Aucun compte", "Aucun accès réseau, sauf la mise à jour et, si vous l'acceptez, le modèle des personnages"], ["No account", "No network access, except updates and, if you agree, the characters model"]),
             (["Mises à jour", "Vérifiées chaque jour ; installation automatique facultative"], ["Updates", "Checked every day; automatic installation is optional"])]),
      ("Démarrer", "Start"))

# 2 ---------------------------------------------------------------------------------------------------------------------------------------------
d.add(title(("Couper", "Cutting"), ("Marquer des morceaux", "Marking pieces")) +
      fig((img("../img/timeline-fr.jpg"), img("../img/timeline-en.jpg")), ("La timeline : vignettes, forme d'onde, morceaux en orange.", "The timeline: thumbnails, waveform, orange pieces."), shot=True) +
      text(["Placez la tête de lecture, puis <kbd>I</kbd> pour l'entrée et <kbd>O</kbd> pour la sortie : le morceau existe. Glissez les poignées pour ajuster. <kbd>⌫</kbd> supprime le morceau, <kbd>⌘Z</kbd> annule.",
            "La tête de lecture suit la souris image par image. <kbd>←</kbd> <kbd>→</kbd> avancent d'une image, <kbd>↑</kbd> <kbd>↓</kbd> d'une image clé."],
           ["Place the playhead, then <kbd>I</kbd> for the in point and <kbd>O</kbd> for the out point: the piece exists. Drag the handles to adjust. <kbd>⌫</kbd> deletes the piece, <kbd>⌘Z</kbd> undoes.",
            "The playhead follows the mouse frame by frame. <kbd>←</kbd> <kbd>→</kbd> step one frame, <kbd>↑</kbd> <kbd>↓</kbd> one keyframe."], tags=True) +
      note(("<b>Auto : silences début / fin</b> pose d'un clic un morceau sans le silence du début et de la fin.", "<b>Auto: start/end silence</b> places, in one click, a piece without the opening and closing silence.")),
      ("Couper", "Cutting"))

d.add(title(("Exporter", "Exporting"), ("Copie directe ou recompression", "Direct copy or re-encode")) +
      text(["<b>Un par morceau</b> crée <code>nom_01</code>, <code>nom_02</code>… sans jamais rien écraser. <b>Fusionner</b> met les morceaux bout à bout dans un seul fichier.",
            "<b>Sans recompression</b> : instantané et sans perte, mais une vidéo ne démarre que sur une image clé (l'interface vous le dit). <b>Recompresser</b> coupe à l'image près."],
           ["<b>One per piece</b> creates <code>name_01</code>, <code>name_02</code>… and never overwrites anything. <b>Merge</b> puts the pieces end to end in a single file.",
            "<b>Direct copy</b>: instant and lossless, but a video only starts on a keyframe (the interface tells you). <b>Re-encode</b> cuts frame-exact."], tags=True) +
      table((["Sortie", "Formats"], ["Output", "Formats"]),
            [(["Vidéo", "Identique à l'original, MP4, MOV, MKV, WebM"], ["Video", "Same as source, MP4, MOV, MKV, WebM"]),
             (["Audio", "MP3, M4A, WAV, FLAC, AIFF, Opus"], ["Audio", "MP3, M4A, WAV, FLAC, AIFF, Opus"])]) +
      h3(("Plusieurs fichiers d'un coup", "Several files at once")) +
      text("Dans le Finder, clic droit ▸ « Élaguer début et fin avec mSLICE… » : retirez X secondes au début et Y à la fin de chaque fichier, ou laissez mSLICE retirer les silences. Les originaux ne sont jamais modifiés.",
           "In the Finder, right-click ▸ “Trim start and end with mSLICE…”: remove X seconds at the start and Y at the end of each file, or let mSLICE remove the silences. Originals are never modified."),
      ("Exporter", "Exporting"))

# 3 ---------------------------------------------------------------------------------------------------------------------------------------------
d.opener("2", ("Trouver", "Find"),
         ("Repérer les plans, les scènes et les sons d'un fichier avec les outils de macOS, puis transformer les passages trouvés en morceaux.",
          "Spot a file's shots, scenes and sounds with macOS tools, then turn the passages found into pieces."),
         "../img/spot-listen.jpg", ("Trouver", "Find"), right=True)

cardsimg = lambda l: f'<div style="display:flex;gap:5mm;align-items:flex-start"><img src="../img/pcard-before-{l}.jpg" style="width:52mm;border-radius:9px"><img src="../img/pcard-running-{l}.jpg" style="width:52mm;border-radius:9px"></div>'
d.add(title(("Analyser", "Analyze"), ("Un bouton, quelques secondes", "One button, a few seconds")) +
      bi2(f"<figure>{cardsimg('fr')}<figcaption>Avant l'analyse, puis pendant.</figcaption></figure>", f"<figure>{cardsimg('en')}<figcaption>Before analysis, then while it runs.</figcaption></figure>") +
      text(["Ouvrez l'onglet <b>Trouver</b> et cliquez sur <b>Analyser</b> : environ une seconde par minute de vidéo. Vous pouvez continuer à travailler. Le résultat est gardé pour la prochaine ouverture.",
            "mSLICE repère les <b>plans</b>, une quarantaine de <b>scènes</b> (feu, foule, nuit, véhicules…) et de <b>sons</b> (parole, musique, rires…). Rien ne sort du Mac."],
           ["Open the <b>Find</b> tab and click <b>Analyze</b>: about one second per minute of video. You can keep working. The result is kept for the next time.",
            "mSLICE spots the <b>shots</b>, about forty <b>scenes</b> (fire, crowd, night, vehicles…) and <b>sounds</b> (speech, music, laughter…). Nothing leaves your Mac."], tags=True) +
      note(("« Explosion » n'existe pas comme scène : essayez le son « Explosions » ou la scène « Feu et flammes ».", "“Explosion” does not exist as a scene: try the “Explosions” sound or the “Fire and flames” scene.")),
      ("Trouver", "Find"))

def side_img(name):
    def im(l): return f'<img src="../img/panel-{name}-{l}-light.jpg" style="width:50mm;border-radius:9px;box-shadow:0 1mm 3mm rgba(38,35,30,.25)">'
    def go(fr, en):
        return bi2(f'<div style="display:flex;gap:6mm;align-items:flex-start">{im("fr")}<div style="flex:1">{fr}</div></div>', f'<div style="display:flex;gap:6mm;align-items:flex-start">{im("en")}<div style="flex:1">{en}</div></div>')
    return go


d.add(title(("Critères", "Criteria"), ("Combiner ET, SAUF, plans entiers", "Combine AND, EXCEPT, whole shots")) +
      side_img("find-choice")("<h4 style='margin-top:0'>Tous les rires</h4><p>Cliquez sur « Rires » (sons), puis « Ajouter ».</p><h4>La nuit, sans musique</h4><p>« Nuit », puis « + Critère » ▸ « Sauf quand… » ▸ Musique.</p><h4>Le feu ET la foule</h4><p>« Feu et flammes », puis « + Critère » ▸ « Et aussi… » ▸ Foule.</p><h4>Plans entiers</h4><p>Garde le plan complet autour de chaque passage.</p>",
                              "<h4 style='margin-top:0'>Every laugh</h4><p>Click “Laughter” (sounds), then “Add”.</p><h4>Night, no music</h4><p>“Night”, then “+ Criterion” ▸ “Except when…” ▸ Music.</p><h4>Fire AND crowd</h4><p>“Fire and flames”, then “+ Criterion” ▸ “And also…” ▸ Crowd.</p><h4>Whole shots</h4><p>Keeps the full shot around each passage.</p>") +
      note(("Les passages écartés restent dans la liste, grisés : cochez-les pour les garder quand même. « Ajouter » se défait d'un seul <kbd>⌘Z</kbd>.", "Dropped passages stay in the list, greyed: tick them to keep them anyway. “Add” undoes with a single <kbd>⌘Z</kbd>.")),
      ("Trouver", "Find"))

# 4 ---------------------------------------------------------------------------------------------------------------------------------------------
def pn(l): return f'<img src="../img/panel-find-results-{l}-light.jpg" style="width:50mm;border-radius:9px;box-shadow:0 1mm 3mm rgba(38,35,30,.25)">'


def side(fr, en):
    return bi2(f'<div style="display:flex;gap:6mm;align-items:flex-start">{pn("fr")}<div style="flex:1">{fr}</div></div>', f'<div style="display:flex;gap:6mm;align-items:flex-start">{pn("en")}<div style="flex:1">{en}</div></div>')


d.add(title(("Personnages", "Characters"), ("Retrouver quelqu'un dans le film", "Find someone in the film")) +
      side("<h4 style='margin-top:0'>1 · Télécharger</h4><p>Carte « Personnages » ▸ « Télécharger » (≈ 60 Mo), seulement si vous le voulez.</p><h4>2 · Reconnaître</h4><p>« Reconnaître les personnages » : environ 1 s par minute de vidéo.</p><h4>3 · Utiliser</h4><p>Un clic sur une vignette l'ajoute à la sélection, comme une scène.</p><h4>4 · Corriger</h4><p>Clic droit : renommer, réunir deux vignettes de la même personne, séparer un groupe mélangé.</p>",
           "<h4 style='margin-top:0'>1 · Download</h4><p>“Characters” card ▸ “Download” (≈ 60 MB), only if you want it.</p><h4>2 · Recognise</h4><p>“Recognise the characters”: about 1 s per minute of video.</p><h4>3 · Use</h4><p>A click on a thumbnail adds it to the selection, like a scene.</p><h4>4 · Fix</h4><p>Right-click: rename, join two thumbnails of the same person, split a mixed group.</p>") +
      note(("<b>Limites</b> : visages seulement (ni créatures ni costumes). Les visages de profil, petits ou flous peuvent être mal regroupés : c'est pour cela que « Réunir » et « Séparer » existent.", "<b>Limits</b>: faces only (no creatures or costumes). Profile, small or blurry faces may be grouped wrongly: that is why “Join” and “Split” exist.")),
      ("Personnages", "Characters"))

# 5 ---------------------------------------------------------------------------------------------------------------------------------------------
d.add(title(("Agent", "Agent"), ("Piloter mSLICE avec un agent", "Drive mSLICE with an agent")) +
      text(["L'agent est <b>désactivé par défaut</b> : Réglages ▸ Agent ▸ « Autoriser un agent ». Il crée seulement de nouveaux fichiers : il ne supprime et n'écrase rien.",
            "<b>Panneau de discussion</b> (onglet Agent) : Claude Code, API Anthropic, ou serveur compatible OpenAI (Ollama, LM Studio…)."],
           ["The agent is <b>off by default</b>: Settings ▸ Agent ▸ “Allow an agent”. It only creates new files: it deletes and overwrites nothing.",
            "<b>Chat panel</b> (Agent tab): Claude Code, Anthropic API, or an OpenAI-compatible server (Ollama, LM Studio…)."], tags=True) +
      h3(("Raccorder un autre agent (MCP)", "Connect another agent (MCP)")) +
      text("Réglages ▸ Agent ▸ « Raccorder d'autres agents » : trois boutons copient la configuration. Pour Claude Code :", "Settings ▸ Agent ▸ “Connect other agents”: three buttons copy the setup. For Claude Code:") +
      bi2("<pre>claude mcp add --scope user mslice -- \"/Applications/mSLICE.app/Contents/MacOS/mslice-mcp\"</pre>", "<pre>claude mcp add --scope user mslice -- \"/Applications/mSLICE.app/Contents/MacOS/mslice-mcp\"</pre>") +
      bi2("<pre>{ \"mcpServers\": { \"mslice\": { \"command\": \".../mslice-mcp\" } } }</pre><p style='margin:0;font-size:10pt'>Claude Desktop, Cursor, Gemini CLI</p>", "<pre>[mcp_servers.mslice]\ncommand = \".../mslice-mcp\"</pre><p style='margin:0;font-size:10pt'>Codex</p>"),
      ("Agent", "Agent"))

tools = [("get_state · probe_media", "État de l'appli ; infos sur un fichier", "App state; file information"),
         ("find_silences · get_frame", "Silences ; image à un instant", "Silences; picture at a time"),
         ("analyze_media", "Plans, scènes, sons (et personnages avec <code>characters=true</code>)", "Shots, scenes, sounds (and characters with <code>characters=true</code>)"),
         ("find_scenes", "Passages : <code>scene:</code> <code>sound:</code> <code>person:</code>…", "Passages: <code>scene:</code> <code>sound:</code> <code>person:</code>…"),
         ("list_subjects · name_subject", "Liste et nomme les personnages", "Lists and names the characters"),
         ("get / set / add / remove / clear_segments", "Lire et modifier les morceaux", "Read and edit the pieces"),
         ("trim_edges · trim_silences · split_on_silence", "Élaguer, retirer ou découper aux silences", "Trim, remove or split at silences"),
         ("preview_export · export · batch_trim", "Simuler, exporter, traiter plusieurs fichiers", "Dry-run, export, process several files"),
         ("open_in_app · seek", "Ouvrir un fichier ; placer la tête de lecture", "Open a file; move the playhead")]
d.add(title(("Agent", "Agent"), ("Les 21 outils, en bref", "The 21 tools, in brief")) +
      table((["Outil", "À quoi il sert"], ["Tool", "What it is for"]), [([f"<code>{n}</code>", fr], [f"<code>{n}</code>", en]) for n, fr, en in tools]) +
      note(("Exemple : « garde toutes les apparitions d'Alma, sauf quand il y a de la musique, et fusionne ».", "Example: “keep every appearance of Alma, except when there is music, and merge”.")),
      ("Agent", "Agent"))

# 6 ---------------------------------------------------------------------------------------------------------------------------------------------
d.add(title(("Réglages et données", "Settings and data"), ("Où tout se trouve", "Where everything lives")) +
      table((["Réglage", "Effet"], ["Setting", "Effect"]),
            [(["Langue", "Automatique (langue du Mac) ou français, anglais, espagnol, italien"], ["Language", "Automatic (the Mac's language) or French, English, Spanish, Italian"]),
             (["Apparence", "Clair, sombre ou automatique"], ["Appearance", "Light, dark or automatic"]),
             (["Export", "Numérotation, nom du fichier fusionné, révéler dans le Finder, original à la corbeille"], ["Export", "Numbering, merged file name, reveal in Finder, original to the Trash"]),
             (["Mises à jour", "Installer automatiquement ; Rechercher maintenant"], ["Updates", "Install automatically; Check now"])]) +
      h3(("Ce que mSLICE écrit sur le disque", "What mSLICE writes to disk")) +
      table((["Dossier", "Contenu"], ["Folder", "Content"]),
            [(["<code>Application Support/mSLICE/…</code>", "morceaux (<code>sessions</code>), analyses (<code>index</code>), modèle (<code>models</code>), journal de l'agent"], ["<code>Application Support/mSLICE/…</code>", "pieces (<code>sessions</code>), analyses (<code>index</code>), model (<code>models</code>), agent log"])]) +
      note(("Supprimer ces dossiers ne touche jamais à vos médias. Les originaux ne sont jamais modifiés.", "Deleting these folders never touches your media. Originals are never modified.")),
      ("Réglages", "Settings"))

# 7 ---------------------------------------------------------------------------------------------------------------------------------------------
d.add(title(("Dépannage", "Troubleshooting"), ("Questions fréquentes", "Frequently asked questions")) +
      table((["Question", "Réponse"], ["Question", "Answer"]),
            [(["Mon morceau démarre trop tôt.", "En copie directe, la vidéo démarre sur l'image clé précédente. Choisissez « Recompresser » pour couper à l'image près."], ["My piece starts too early.", "With direct copy the video starts on the previous keyframe. Choose “Re-encode” to cut frame-exact."]),
             (["« L'analyse a échoué ».", "macOS n'a pas pu lire le fichier. Réessayez ou essayez un autre fichier."], ["“The analysis failed”.", "macOS could not read the file. Try again or try another file."]),
             (["Le feu ou la foule n'apparaissent pas.", "La carte Scènes dit ce qui n'a pas été repéré. Combinez les familles avec ET."], ["Fire or crowd do not show up.", "The Scenes card says what was not spotted. Combine families with AND."]),
             (["Deux personnes sont réunies.", "Clic droit sur la vignette ▸ « Séparer en deux »."], ["Two people are merged.", "Right-click the thumbnail ▸ “Split in two”."]),
             (["La reconnaissance échoue.", "Supprimez le modèle depuis la carte Personnages, puis téléchargez-le de nouveau."], ["Recognition fails.", "Remove the model from the Characters card, then download it again."]),
             (["Le clic droit du Finder manque.", "Réglages Système ▸ Extensions ▸ Finder : cochez mSLICE."], ["The Finder right-click is missing.", "System Settings ▸ Extensions ▸ Finder: tick mSLICE."]),
             (["Un agent ne peut pas piloter mSLICE.", "Vérifiez « Autoriser un agent » et lisez le journal (Réglages ▸ Agent)."], ["An agent cannot drive mSLICE.", "Check “Allow an agent” and read the log (Settings ▸ Agent)."])]),
      ("Dépannage", "Troubleshooting"))

# 8 ---------------------------------------------------------------------------------------------------------------------------------------------
d.add(title(("Licences et soutien", "Licences and support"), ("Libre, et fait pour durer", "Free, and built to last")) +
      text(["mSLICE est publié sous <b>licence MIT</b> et fait partie du <b>DESKTOP MAC TOOLKIT</b>. Le code est sur <b>github.com/starbudweiser/mSLICE</b>.",
            "L'appli embarque <b>FFmpeg</b> (LGPL), <b>LAME</b>, <b>mpg123</b>, <b>Opus</b> et <b>libvpx</b>. Le modèle optionnel des personnages est <b>AuraFace</b> de fal.ai (Apache 2.0). Le détail est dans <code>THIRD_PARTY_LICENSES.md</code>."],
           ["mSLICE is published under the <b>MIT licence</b> and is part of the <b>DESKTOP MAC TOOLKIT</b>. The code is at <b>github.com/starbudweiser/mSLICE</b>.",
            "The app bundles <b>FFmpeg</b> (LGPL), <b>LAME</b>, <b>mpg123</b>, <b>Opus</b> and <b>libvpx</b>. The optional characters model is fal.ai's <b>AuraFace</b> (Apache 2.0). Details are in <code>THIRD_PARTY_LICENSES.md</code>."], lead=True, tags=True) +
      note(("<b>♥ Soutenir le projet</b> : facultatif, aucune fonction bloquée. Lien en bas de la fenêtre « À propos » : github.com/sponsors/starbudweiser.", "<b>♥ Support the project</b>: optional, no feature locked. Link at the bottom of the “About” window: github.com/sponsors/starbudweiser.")) +
      stats([("21", ("outils d'agent", "agent tools")), ("4", ("langues", "languages")), ("0", ("octet envoyé hors du Mac par l'analyse", "bytes sent off the Mac by analysis")), ("1.3", ("version décrite ici", "version described here"))]),
      ("Licences", "Licences"))

if __name__ == "__main__":
    out = d.to_pdf(os.path.join(HERE, "..", "pdf"))
    print(out)
