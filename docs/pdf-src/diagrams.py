"""Schémas SVG bilingues des PDF mSLICE : chaque fonction rend le schéma pour une langue (« fr » ou « en »)."""
INK, ORANGE, PAPER, LINE, CARD, DARK, GREY, BLUE = "#26231e", "#d9622b", "#f6f2ea", "#ddd5c8", "#fffdf9", "#1d1d21", "#8a8376", "#0a84ff"
FONT = "-apple-system, 'SF Pro Text', 'Helvetica Neue', Helvetica, sans-serif"
SERIF = "'Iowan Old Style', Palatino, Georgia, serif"


def svg(w, h, body, bg=None):
    r = f'<rect width="{w}" height="{h}" rx="10" fill="{bg}"/>' if bg else ""
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}" width="100%" font-family="{FONT}">'
            f'<defs><marker id="ar" markerWidth="8" markerHeight="8" refX="6.5" refY="4" orient="auto"><path d="M0,0.8 L7,4 L0,7.2 Z" fill="{INK}"/></marker>'
            f'<marker id="ao" markerWidth="8" markerHeight="8" refX="6.5" refY="4" orient="auto"><path d="M0,0.8 L7,4 L0,7.2 Z" fill="{ORANGE}"/></marker></defs>{r}{body}</svg>')


def box(x, y, w, h, label, sub="", style="n", size=11):
    fill, stroke, tc, sc = {"n": (CARD, INK, INK, GREY), "a": (ORANGE, ORANGE, "#fff", "#ffe6d8"), "d": (DARK, DARK, "#fff", "#9a978f"), "s": (PAPER, LINE, INK, GREY)}[style]
    out = f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="8" fill="{fill}" stroke="{stroke}" stroke-width="{0.9 if style != "a" else 0}"/>'
    lines = label.split("\n")
    total = len(lines) + (1 if sub else 0)
    y0 = y + h / 2 - (total - 1) * 7.2 + 4
    for i, ln in enumerate(lines):
        out += f'<text x="{x + w / 2}" y="{y0 + i * 14}" text-anchor="middle" font-size="{size}" font-weight="600" fill="{tc}">{ln}</text>'
    if sub:
        out += f'<text x="{x + w / 2}" y="{y0 + len(lines) * 14}" text-anchor="middle" font-size="8.6" fill="{sc}">{sub}</text>'
    return out


def arrow(x1, y1, x2, y2, accent=False, dash=False):
    c, m = (ORANGE, "ao") if accent else (INK, "ar")
    d = ' stroke-dasharray="4 3"' if dash else ""
    return f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" stroke="{c}" stroke-width="1.1"{d} marker-end="url(#{m})"/>'


def text(x, y, s, size=9, anchor="middle", color=GREY, weight=400, italic=False):
    st = ' font-style="italic"' if italic else ""
    return f'<text x="{x}" y="{y}" text-anchor="{anchor}" font-size="{size}" fill="{color}" font-weight="{weight}"{st}>{s}</text>'


def T(lang):
    return lambda fr, en: fr if lang == "fr" else en


# --- 1. architecture d'ensemble --------------------------------------------------------------------------------------------------------------
def architecture(lang):
    t = T(lang)
    b = box(15, 8, 360, 44, t("Interface SwiftUI", "SwiftUI interface"), t("onglets Édition · Trouver · Agent", "Edit · Find · Agent tabs"), "d")
    b += box(390, 8, 155, 44, t("Extension Finder", "Finder extension"), t("clic droit : extraire, élaguer", "right-click: extract, trim"), "s")
    for x in (75, 205, 335):
        b += arrow(x, 52, x, 82)
    b += arrow(468, 52, 468, 82, dash=True)
    b += box(15, 84, 120, 50, t("Lecteur\net timeline", "Player\nand timeline"), "", "n")
    b += box(145, 84, 120, 50, t("Export", "Export"), t("ffmpeg LGPL · VideoToolbox", "ffmpeg LGPL · VideoToolbox"), "n")
    b += box(275, 84, 120, 50, t("Trouver", "Find"), t("requêtes ET / SAUF", "AND / EXCEPT queries"), "n")
    b += box(408, 84, 137, 50, t("Cœur de l'agent", "Agent core"), t("outils, garde-fous", "tools, guardrails"), "n")
    b += arrow(335, 134, 335, 164, accent=True)
    b += arrow(476, 134, 476, 164)
    b += box(185, 166, 210, 54, t("Processus d'analyse séparé", "Separate analysis process"), "mslice-mcp --analyze · --faces", "a")
    b += box(408, 166, 137, 54, t("Serveur MCP", "MCP server"), "mslice-mcp (stdio)", "n")
    b += arrow(408, 193, 396, 193, dash=True)
    b += text(290, 238, t("Vision · SoundAnalysis · Core ML (modèle optionnel)", "Vision · SoundAnalysis · Core ML (optional model)"), 8.6)
    b += arrow(290, 244, 290, 256, accent=True)
    for i, (x, w, lab) in enumerate([(15, 120, t("sessions", "sessions")), (145, 120, "index .msidx"), (275, 120, t("visages .msfaces", "faces .msfaces")), (405, 140, t("modèle compilé", "compiled model"))]):
        b += box(x, 258, w, 30, lab, "", "s", size=9.6)
    return svg(560, 296, b)


# --- 2. la passe d'analyse ----------------------------------------------------------------------------------------------------------------------
def analysis(lang):
    t = T(lang)
    b = box(10, 62, 78, 46, t("Fichier", "File"), t("vidéo + son", "video + sound"), "d")
    b += arrow(88, 78, 112, 50)
    b += arrow(88, 94, 112, 128)
    b += box(114, 22, 128, 56, t("Décodage matériel\n512 px, toutes les images", "Hardware decoding\n512 px, every frame"), "", "n", size=10)
    b += box(114, 108, 128, 40, t("Audio 16 kHz mono", "16 kHz mono audio"), "", "n", size=10)
    b += arrow(242, 36, 270, 22)
    b += arrow(242, 56, 270, 70)
    b += arrow(242, 128, 270, 128)
    b += box(272, 4, 140, 36, t("Coupures", "Cuts"), t("miniatures 32×18 + couleur", "32×18 thumbnails + colour"), "s", size=10)
    b += box(272, 52, 140, 36, t("Scènes (Vision)", "Scenes (Vision)"), t("1 303 étiquettes, 2 images/s", "1,303 labels, 2 frames/s"), "s", size=10)
    b += box(272, 110, 140, 36, t("Sons (SoundAnalysis)", "Sounds (SoundAnalysis)"), t("303 types, fenêtres de 1,5 s", "303 types, 1.5 s windows"), "s", size=10)
    for y in (22, 70, 128):
        b += arrow(412, y, 440, 82)
    b += box(442, 52, 108, 60, t("Index\n.msidx", "Index\n.msidx"), t("≈ 6 Ko / min", "≈ 6 KB / min"), "a", size=11)
    b += text(280, 172, t("Aucune image n'est conservée · mémoire bornée (3 images en attente)", "No picture is kept · bounded memory (3 frames pending)"), 8.8)
    return svg(560, 184, b)


# --- 3. une requête : critères, SAUF, plans entiers ---------------------------------------------------------------------------------------
def query(lang):
    t = T(lang)
    X0, W, D = 112, 430, 60.0
    def x(s): return X0 + W * s / D
    def strip(y, label, ivs, color, h=18, op=1):
        o = text(X0 - 8, y + h - 5, label, 9.4, "end", INK, 600)
        o += f'<rect x="{X0}" y="{y}" width="{W}" height="{h}" rx="4" fill="#ece6da"/>'
        for a, b_ in ivs:
            o += f'<rect x="{x(a):.1f}" y="{y}" width="{x(b_) - x(a):.1f}" height="{h}" rx="3" fill="{color}" opacity="{op}"/>'
        return o
    b = ""
    for s in (12, 38, 52):
        b += f'<line x1="{x(s):.1f}" y1="6" x2="{x(s):.1f}" y2="176" stroke="{GREY}" stroke-width=".7" stroke-dasharray="2 3"/>'
    b += text(X0, 12, t("coupures du montage", "editing cuts"), 8, "start", GREY, 400, True)
    b += strip(22, t("Personnage", "Character"), [(5, 25), (35, 50)], BLUE)
    b += strip(48, t("Feu", "Fire"), [(18, 30), (40, 46)], ORANGE)
    b += strip(74, t("Musique", "Music"), [(20, 28)], GREY)
    b += strip(102, t("Passages", "Passages"), [(18, 25), (40, 46)], INK)
    b += text(x(21.5), 136, t("écarté : musique", "dropped: music"), 8.4, "middle", GREY, 400, True)
    b += text(X0 - 8, 154, t("Plans entiers", "Whole shots"), 9.4, "end", INK, 600)
    b += f'<rect x="{X0}" y="144" width="{W}" height="18" rx="4" fill="#ece6da"/>'
    b += f'<rect x="{x(38):.1f}" y="144" width="{x(52) - x(38):.1f}" height="18" rx="3" fill="{ORANGE}"/>'
    b += f'<rect x="{x(12):.1f}" y="144" width="{x(38) - x(12):.1f}" height="18" rx="3" fill="none" stroke="{GREY}" stroke-dasharray="3 2"/>'
    return svg(560, 184, b)


# --- 4. la chaîne des personnages --------------------------------------------------------------------------------------------------------
def faces(lang):
    t = T(lang)
    w, h = 96, 46
    xs = [8, 120, 232, 344, 456]
    b = box(xs[0], 10, w, h, t("1 image\npar seconde", "1 frame\nper second"), "", "d", 10)
    b += box(xs[1], 10, w, h, t("Visages et\n5 repères", "Faces and\n5 landmarks"), "Vision", "n", 10)
    b += box(xs[2], 10, w, h, t("Alignement\n112 × 112", "Alignment\n112 × 112"), t("gabarit ArcFace", "ArcFace template"), "n", 10)
    b += box(xs[3], 10, w, h, t("Empreinte\n512 valeurs", "Embedding\n512 values"), "AuraFace · Core ML", "a", 10)
    b += box(xs[4], 10, 96, h, t("Suivis", "Tracks"), t("même plan, même boîte", "same shot, same box"), "n", 10)
    for i in range(4):
        b += arrow(xs[i] + w, 33, xs[i + 1], 33, accent=(i == 2))
    b += arrow(504, 56, 504, 84)
    b += box(456, 86, 96, 46, t("Groupes", "Groups"), t("liaison moyenne 0,30", "average link 0.30"), "n", 10)
    b += arrow(456, 109, 428, 109)
    b += box(232, 86, 196, 46, t("Personnages", "Characters"), t("jamais deux visages d'une même image", "never two faces from one frame"), "a", 11)
    b += arrow(232, 109, 204, 109)
    b += box(8, 86, 196, 46, t("Vignettes rondes\nrenommer · réunir · séparer", "Round thumbnails\nrename · join · split"), "", "s", 10)
    b += text(280, 156, t("Tout se passe sur le Mac, dans le processus d'analyse ; le modèle est rendu au système à sa fin.", "Everything runs on the Mac, inside the analysis process; the model is released when it ends."), 8.8)
    return svg(560, 166, b)


# --- 5. les candidats pour l'identité des personnages ------------------------------------------------------------------------------
def models(lang):
    t = T(lang)
    rows = [("Apple (Vision)", 0.85, 0.80, "0 Mo"), ("DINOv2-S", 0.77, 0.76, "41 Mo"), ("SFace", 0.999, 0.983, "18 Mo"), ("AuraFace 8 bits", 0.998, 0.980, "63 Mo")]
    X0, W = 118, 300
    b = text(X0, 14, t("AUC : 0,5 = hasard · 1 = parfait", "AUC: 0.5 = chance · 1 = perfect"), 8.4, "start", GREY, 400, True)
    for i, (n, a, d, s) in enumerate(rows):
        y = 26 + i * 40
        win = n.startswith("AuraFace")
        b += text(X0 - 8, y + 12, n, 10, "end", INK, 700 if win else 500)
        for j, (v, col, lab) in enumerate([(a, ORANGE if win else INK, t("visages nets", "clear faces")), (d, "#b9b1a3", t("difficiles", "hard cases"))]):
            yy = y + j * 15
            w = W * (v - 0.5) / 0.5
            b += f'<rect x="{X0}" y="{yy}" width="{W}" height="11" rx="3" fill="#ece6da"/><rect x="{X0}" y="{yy}" width="{w:.1f}" height="11" rx="3" fill="{col}"/>'
            b += text(X0 + w + 5, yy + 9, f"{v:.3f}".replace(".", "," if lang == "fr" else "."), 8.4, "start", INK)
        b += text(X0 + W + 40, y + 14, s, 9, "start", GREY)
    b += text(X0 + 4, 188, t("▌ visages nets   ▌ difficiles (profils, flous)", "▌ clear faces   ▌ hard cases (profiles, blur)"), 8.2, "start", GREY)
    return svg(560, 196, b)


# --- 6. le chemin d'un ordre d'agent ---------------------------------------------------------------------------------------------------------
def agent(lang):
    t = T(lang)
    b = box(8, 20, 118, 52, t("Agent", "Agent"), "Claude Code, Cursor…", "d", 11)
    b += arrow(126, 46, 150, 46)
    b += text(138, 38, "MCP", 7.6, "middle", GREY)
    b += box(152, 20, 118, 52, "mslice-mcp", t("JSON-RPC sur stdio", "JSON-RPC over stdio"), "n")
    b += arrow(270, 36, 300, 22)
    b += arrow(270, 56, 300, 80)
    b += box(302, 4, 120, 40, t("Appli ouverte ?", "App open?"), t("prise Unix locale", "local Unix socket"), "s", 10)
    b += box(302, 60, 120, 40, t("Sinon : en autonome", "Otherwise: standalone"), t("sans fenêtre", "no window"), "s", 10)
    b += arrow(422, 24, 450, 44)
    b += arrow(422, 80, 450, 64)
    b += box(452, 26, 98, 52, t("Cœur de\nl'agent", "Agent\ncore"), t("mêmes garde-fous", "same guardrails"), "a", 10)
    b += arrow(500, 78, 500, 106)
    b += box(380, 108, 170, 38, t("Nouveaux fichiers seulement", "New files only"), t("jamais d'écrasement ni de suppression", "never overwritten or deleted"), "n", 10)
    b += text(280, 168, t("L'appli ouverte met la timeline à jour en direct ; hors de l'appli, l'outil s'exécute dans mslice-mcp.", "With the app open the timeline updates live; otherwise the tool runs inside mslice-mcp."), 8.6)
    return svg(560, 178, b)


# --- 7. mesures ------------------------------------------------------------------------------------------------------------------------------------
def timing(lang):
    t = T(lang)
    X0, W = 190, 340
    b = ""
    rows = [(t("Vidéo de test", "Test video"), 1685, GREY, "28:05"), (t("Analyse (scènes, sons)", "Analysis (scenes, sounds)"), 25, ORANGE, "25 s"),
            (t("Reconnaissance des personnages", "Character recognition"), 22, ORANGE, "22 s"), (t("Export par copie directe", "Direct-copy export"), 1, INK, "< 1 s")]
    for i, (n, v, c, lab) in enumerate(rows):
        y = 8 + i * 30
        w = max(W * v / 1685, 3)
        b += text(X0 - 8, y + 14, n, 9.4, "end", INK, 600)
        b += f'<rect x="{X0}" y="{y}" width="{W}" height="19" rx="4" fill="#ece6da"/><rect x="{X0}" y="{y}" width="{w:.1f}" height="19" rx="4" fill="{c}"/>'
        b += text(X0 + w + 6 if w < 300 else X0 + w - 6, y + 14, lab, 9.4, "start" if w < 300 else "end", INK if w < 300 else "#fff", 700)
    return svg(560, 130, b)


# --- 8. dossiers de données --------------------------------------------------------------------------------------------------------------------
def folders(lang):
    t = T(lang)
    lines = [("Application Support/mSLICE/", "", 0), ("sessions/", t("morceaux de chaque fichier, restaurés à la réouverture", "each file's pieces, restored on reopening"), 1), ("index/&lt;clé&gt;.msidx", t("plans, scènes, sons (version 1)", "shots, scenes, sounds (version 1)"), 1),
             ("index/&lt;clé&gt;.msfaces", t("visages, personnages, noms (liés au modèle)", "faces, characters, names (tied to the model)"), 1), ("models/characters/", t("modèle compilé, licence, notice, manifeste", "compiled model, licence, notice, manifest"), 1),
             ("agent.log", t("journal des actions de l'agent", "log of the agent's actions"), 1)]
    b = ""
    for i, (n, d, lv) in enumerate(lines):
        y = 16 + i * 25
        b += text(10 + lv * 16, y, ("▸ " if lv else "") + n, 9.6, "start", INK, 700 if not lv else 600)
        if d:
            b += text(200, y, d, 8.8, "start", GREY)
    return svg(560, 160, b)
