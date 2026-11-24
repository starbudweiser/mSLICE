"""mSLICE — document « Conception » (FR | EN), en langage simple : idées de départ, architecture, analyse, personnages, sécurité, agent, mesures, choix."""
import diagrams as D
from lib import *

d = Doc("conception", "Conception", ("Conception", "Design"), "../img/cover-conception.jpg")
d.cover(("Comment mSLICE est pensé, expliqué simplement : les idées de départ, la construction, l'analyse des scènes, des sons et des visages, la sécurité, les mesures.",
         "How mSLICE is designed, explained simply: the starting ideas, how it is built, scene, sound and face analysis, security, measurements."))
d.toc([("1", ("Une appli, un usage", "One app, one job"), "3"), ("2", ("Comment c'est construit", "How it is built"), "5"), ("3", ("Trouver : voir et entendre", "Find: seeing and hearing"), "6"),
       ("4", ("Les personnages", "Characters"), "9"), ("5", ("Sécurité et vie privée", "Security and privacy"), "12"), ("6", ("L'agent, facultatif", "The agent, optional"), "13"),
       ("7", ("Ce qui a été mesuré", "What was measured"), "14"), ("8", ("Choix et limites", "Choices and limits"), "15")])

# 1 ---------------------------------------------------------------------------------------------------------------------------------------------
d.opener("1", ("Une appli, un usage", "One app, one job"),
         ("mSLICE sert à couper : retirer un début inutile, une fin gardée « par sécurité », ou sortir quelques passages d'un long enregistrement. Rien de plus, mais très bien.",
          "mSLICE is for cutting: drop a useless opening, an ending kept “just in case”, or pull a few passages out of a long recording. Nothing more, but done very well."),
         "../img/spot-slice.jpg", ("Les idées de départ", "The starting ideas"))

d.add(title(("Les idées de départ", "Starting ideas"), ("Trois promesses", "Three promises")) +
      cards([("Aller vite", "mSLICE copie la vidéo telle quelle au lieu de la recalculer. Un gros fichier est coupé en moins d'une seconde, sans perte de qualité.", "Be fast", "mSLICE copies the video as it is instead of recalculating it. A big file is cut in under a second, with no loss of quality."),
             ("Rester fidèle", "Vos fichiers d'origine ne sont jamais modifiés. Chaque export crée de nouveaux fichiers, sans rien écraser.", "Stay faithful", "Your original files are never modified. Every export creates new files and overwrites nothing."),
             ("Garder la main", "La détection de scènes, de sons et de personnages ne fait que proposer des morceaux. C'est vous qui décidez lesquels garder.", "Stay in control", "Detecting scenes, sounds and characters only suggests pieces. You decide which ones to keep.")], cols=1) +
      stats([("&lt; 1<small> s</small>", ("pour couper un gros fichier", "to cut a big file")), ("25<small> s</small>", ("pour analyser 28 min de vidéo", "to analyse 28 min of video")),
             ("22<small> s</small>", ("pour reconnaître les personnages de 28 min", "to recognise the characters in 28 min")), ("0<small> %</small>", ("de processeur quand l'appli ne fait rien", "CPU when the app is idle"))]),
      ("Les idées de départ", "Starting ideas"))

# 2 ---------------------------------------------------------------------------------------------------------------------------------------------
d.add(title(("Comment c'est construit", "How it is built"), ("Des briques simples", "Simple building blocks")) +
      full_fig(D.architecture(), ("Figure 1 — Les parties de mSLICE.", "Figure 1 — mSLICE's parts."), "74%") +
      enclair(("l'interface pilote des briques simples (lecteur, export, recherche). Le gros calcul de l'analyse tourne dans un petit programme à part, qui rend toute sa mémoire en se terminant.",
               "the interface drives simple blocks (player, export, search). The heavy analysis runs in a small separate program that gives back all its memory when it ends.")) +
      text("Le même moteur sert l'appli et les agents (serveur MCP) : ils font exactement la même chose, avec les mêmes garde-fous.", "The same engine serves the app and the agents (MCP server): they do exactly the same thing, with the same guardrails."),
      ("Construction", "Construction"))

# 3 ---------------------------------------------------------------------------------------------------------------------------------------------
d.opener("2", ("Trouver : voir et entendre", "Find: seeing and hearing"),
         ("Un bouton « Analyser » repère les plans, les scènes et les sons d'un fichier avec les outils déjà présents dans macOS. Rien n'est téléchargé, rien ne sort du Mac.",
          "One “Analyze” button spots a file's shots, scenes and sounds with the tools already built into macOS. Nothing is downloaded, nothing leaves your Mac."),
         "../img/spot-listen.jpg", ("Trouver", "Find"), right=True)

d.add(title(("L'analyse", "Analysis"), ("L'analyse, en bref", "Analysis in brief")) +
      full_fig(D.analysis(), ("Figure 2 — Une seule lecture du fichier nourrit les trois détecteurs.", "Figure 2 — One read of the file feeds the three detectors."), "86%") +
      text(["mSLICE lit le fichier <b>une seule fois</b>. Il note où le montage change de plan, ce qu'on voit (feu, foule, nuit…) et ce qu'on entend (musique, rires, paroles…).",
            "Le résultat est une petite fiche, d'environ 6 Ko par minute, gardée pour la prochaine ouverture. Tout se passe sur votre Mac."],
           ["mSLICE reads the file <b>only once</b>. It notes where the edit changes shot, what you see (fire, crowd, night…) and what you hear (music, laughter, speech…).",
            "The result is a small record, about 6 KB per minute, kept for the next time. Everything happens on your Mac."], tags=True) +
      note(("Seules les coupures franches sont détectées, pas les fondus enchaînés.", "Only hard cuts are detected, not dissolves.")),
      ("Analyse", "Analysis"))

d.add(title(("Les critères", "Criteria"), ("Combiner les critères", "Combining criteria")) +
      full_fig(D.query(), ("Figure 3 — « Le personnage ET le feu, SAUF quand il y a de la musique, en plans entiers ».", "Figure 3 — “The character AND the fire, EXCEPT when there is music, whole shots”."), "86%") +
      bullets([("<b>ET</b> : les deux à la fois (ici le personnage et le feu).", "<b>AND</b>: both at once (here the character and the fire)."),
               ("<b>SAUF</b> : on écarte les passages où l'on entend de la musique.", "<b>EXCEPT</b>: passages with music are dropped."),
               ("<b>Plans entiers</b> : on garde le plan complet, de son premier à son dernier instant.", "<b>Whole shots</b>: the full shot is kept, from its first to its last moment."),
               ("Les passages très proches sont réunis ; « Ajouter » se défait d'un seul ⌘Z.", "Passages very close together are joined; “Add” undoes with a single ⌘Z.")]),
      ("Critères", "Criteria"))

# 4 ---------------------------------------------------------------------------------------------------------------------------------------------
d.opener("3", ("Les personnages", "Characters"),
         ("macOS ne sait pas reconnaître les visages. mSLICE propose donc, en option, un petit modèle externe : téléchargé seulement si vous l'acceptez, vérifié, supprimable à tout moment.",
          "macOS cannot recognise faces. So mSLICE offers, as an option, a small external model: downloaded only if you agree, verified, removable at any time."),
         "../img/spot-faces.jpg", ("Personnages", "Characters"))

d.add(title(("Le modèle", "The model"), ("Quel modèle choisir ?", "Which model?")) +
      full_fig(D.models(), ("Figure 4 — Quatre modèles essayés sur 745 visages d'une vraie vidéo.", "Figure 4 — Four models tried on 745 faces from a real video."), "80%") +
      table((["Modèle", "Ce que ça donne", "Décision"], ["Model", "What you get", "Decision"]),
            [(["Empreinte d'Apple", "confond les personnes entre elles", "écartée"], ["Apple's built-in", "mixes people up", "dropped"]),
             (["DINOv2-S", "regarde le décor, pas la personne", "écarté"], ["DINOv2-S", "looks at the set, not the person", "dropped"]),
             (["SFace", "très bon, mais ses données d'entraînement sont inconnues", "repli possible"], ["SFace", "very good, but its training data is unknown", "possible fallback"]),
             (["<b>AuraFace</b>", "très bon, licence Apache 2.0 pensée pour un usage commercial", "<b>retenu</b>"], ["<b>AuraFace</b>", "very good, Apache 2.0 licence made for commercial use", "<b>chosen</b>"])]),
      ("Personnages", "Characters"))

d.add(title(("La chaîne", "The pipeline"), ("De l'image au personnage", "From frame to character")) +
      full_fig(D.faces(), ("Figure 5 — Reconnaître les personnages, étape par étape.", "Figure 5 — Recognising characters, step by step."), "74%") +
      steps([("Une image par seconde : on repère les visages.", "One frame per second: faces are spotted."),
             ("Chaque visage est redressé puis transformé en 512 nombres : son « empreinte ».", "Each face is straightened, then turned into 512 numbers: its “fingerprint”."),
             ("Les visages qui se suivent dans un même plan sont réunis ; les empreintes qui se ressemblent forment un personnage.", "Faces that follow each other in one shot are joined; similar fingerprints form a character."),
             ("<b>Règle d'or</b> : deux visages d'une même image ne sont jamais le même personnage.", "<b>Golden rule</b>: two faces from the same frame are never the same character.")]) +
      stats([("1&nbsp;845", ("visages trouvés en 28 min", "faces found in 28 min")), ("50", ("personnages", "characters")), ("22<small> s</small>", ("pour toute la vidéo", "for the whole video")), ("278<small> Mo</small>", ("de mémoire au plus fort", "memory at the peak"))]),
      ("Personnages", "Characters"))

# 5 ---------------------------------------------------------------------------------------------------------------------------------------------
d.add(title(("Sécurité", "Security"), ("Sécurité et vie privée", "Security and privacy")) +
      text("Tout se passe sur votre Mac. La seule connexion est le téléchargement du modèle, que vous déclenchez vous-même.", "Everything happens on your Mac. The only connection is the model download, which you start yourself.", lead=True) +
      table((["Protection", "Ce qu'elle fait"], ["Protection", "What it does"]),
            [(["Téléchargement", "HTTPS seulement, taille limitée, signature (SHA-256) vérifiée avant l'installation."], ["Download", "HTTPS only, limited size, signature (SHA-256) checked before installing."]),
             (["Archive du modèle", "Son contenu est inspecté avant d'être ouvert ; seuls le modèle, sa licence et sa notice sont gardés."], ["Model archive", "Its content is inspected before opening; only the model, its licence and notice are kept."]),
             (["Avant chaque usage", "La signature du modèle installé est recalculée : un fichier remplacé ou abîmé n'est jamais chargé."], ["Before each use", "The installed model's signature is recomputed: a replaced or damaged file is never loaded."]),
             (["Fichiers d'analyse", "Refusés s'ils sont tronqués ou incohérents : ils ne peuvent pas faire planter l'appli."], ["Analysis files", "Refused if truncated or inconsistent: they cannot crash the app."]),
             (["Agent", "Crée seulement de nouveaux fichiers, ne supprime ni n'écrase rien, ne télécharge jamais le modèle."], ["Agent", "Only creates new files, deletes or overwrites nothing, never downloads the model."]),
             (["Programme à part", "Un plantage d'un modèle d'Apple ne touche pas l'appli ; on peut tout annuler à tout moment."], ["Separate program", "A crash in an Apple model does not touch the app; everything can be cancelled at any time."])]),
      ("Sécurité", "Security"))

# 6 ---------------------------------------------------------------------------------------------------------------------------------------------
d.add(title(("Agent", "Agent"), ("L'agent, facultatif", "The agent, optional")) +
      full_fig(D.agent(), ("Figure 6 — D'un agent comme Claude Code jusqu'à vos fichiers.", "Figure 6 — From an agent such as Claude Code to your files."), "78%") +
      text(["L'agent est <b>désactivé par défaut</b> (Réglages ▸ Agent). Un panneau de discussion et un serveur MCP donnent accès aux mêmes <b>21 outils</b> : lire des informations (<code>probe_media</code>, <code>find_scenes</code>…), poser des morceaux (<code>set_segments</code>…), exporter (<code>export</code>…)."],
           ["The agent is <b>off by default</b> (Settings ▸ Agent). A chat panel and an MCP server give access to the same <b>21 tools</b>: read information (<code>probe_media</code>, <code>find_scenes</code>…), place pieces (<code>set_segments</code>…), export (<code>export</code>…)."], tags=True) +
      note(("Exemple : « garde toutes les apparitions d'Alma, sauf quand il y a de la musique, et fusionne ».", "Example: “keep every appearance of Alma, except when there is music, and merge”.")),
      ("Agent", "Agent"))

# 7 ---------------------------------------------------------------------------------------------------------------------------------------------
d.add(title(("Mesures", "Measurements"), ("Ce qui a été mesuré", "What was measured")) +
      full_fig(D.timing(), ("Figure 7 — Une vidéo de test de 28 min 05 s, en 1080p.", "Figure 7 — A 28 min 05 s test video, in 1080p."), "76%") +
      table((["Ce qu'on a mesuré", "Résultat"], ["What we measured", "Result"]),
            [(["Analyser 28 min", "25 secondes (objectif : 90) ; 58 Mo de mémoire (objectif : 250)"], ["Analysing 28 min", "25 seconds (target: 90); 58 MB of memory (target: 250)"]),
             (["Reconnaître les personnages", "22 secondes ; 278 Mo avec le modèle chargé (objectif : 300) ; annulation en 0,1 s"], ["Recognising characters", "22 seconds; 278 MB with the model loaded (target: 300); cancel in 0.1 s"]),
             (["Quand l'appli ne fait rien", "0 % de processeur ; mémoire identique avant et après l'analyse"], ["When the app is idle", "0 % CPU; memory identical before and after analysis"]),
             (["Coupures de plans", "425 sur 428 exactes, à l'image près"], ["Shot cuts", "425 of 428 exact, frame for frame"])]) +
      text("Des essais automatiques, sans fenêtre, vérifient tout cela à chaque version : analyse, interface, agent, traductions.", "Automatic tests, with no window, check all of this on every version: analysis, interface, agent, translations."),
      ("Mesures", "Measurements"))

# 8 ---------------------------------------------------------------------------------------------------------------------------------------------
d.add(title(("Choix et limites", "Choices and limits"), ("Ce qu'on a choisi, ce qu'on assume", "What we chose, what we accept")) +
      table((["Choix", "Pourquoi"], ["Choice", "Why"]),
            [(["Analyse dans un programme à part", "Les outils d'Apple gardent de la mémoire ; en les isolant, tout est rendu à la fin."], ["Analysis in a separate program", "Apple's tools hold on to memory; isolating them returns everything at the end."]),
             (["Modèle des personnages en option", "63 Mo de plus pour tout le monde, alors que peu l'utilisent : il se télécharge si on le veut."], ["Characters model is optional", "63 MB more for everyone, when few use it: it downloads only if you want it."]),
             (["Visages seulement", "Aucun modèle libre n'est assez bon pour les créatures ou les costumes : il faut d'abord un film d'essai."], ["Faces only", "No free model is good enough for creatures or costumes: a test film comes first."]),
             (["Réunir facile, séparer prudent", "On regroupe prudemment, et un clic droit corrige : réunir deux vignettes, ou séparer un groupe mélangé."], ["Joining easy, splitting careful", "Grouping is cautious, and a right-click fixes it: join two thumbnails, or split a mixed group."])]) +
      cards([("Prochaine étape", "Une recherche libre par texte (« explosion », « dragon »…) avec un second modèle, téléchargé à la demande.", "Next", "A free text search (“explosion”, “dragon”…) with a second model, downloaded on request."),
             ("Limites connues", "Seules les coupures franches sont détectées. Les réglages ont été mesurés sur une seule vidéo.", "Known limits", "Only hard cuts are detected. Settings were measured on a single video.")], cols=1),
      ("Choix", "Choices"))

if __name__ == "__main__":
    out = d.to_pdf(os.path.join(HERE, "..", "pdf"))
    print(out)
