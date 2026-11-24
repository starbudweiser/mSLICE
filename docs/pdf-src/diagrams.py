"""Schémas SVG des PDF mSLICE : un seul schéma par figure, aux libellés bilingues (français en gras, anglais dessous), conçu pour la pleine largeur de la page."""
INK, ORANGE, PAPER, LINE, CARD, DARK, GREY, BLUE = "#26231e", "#d9622b", "#f6f2ea", "#ddd5c8", "#fffdf9", "#1d1d21", "#5f594d", "#0a84ff"
FONT = "-apple-system, 'SF Pro Text', 'Helvetica Neue', Helvetica, sans-serif"
W = 600


def svg(h, body):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {h}" width="100%" font-family="{FONT}">'
            f'<defs><marker id="ar" markerWidth="9" markerHeight="9" refX="7.5" refY="4.5" orient="auto"><path d="M0,1 L8,4.5 L0,8 Z" fill="{INK}"/></marker>'
            f'<marker id="ao" markerWidth="9" markerHeight="9" refX="7.5" refY="4.5" orient="auto"><path d="M0,1 L8,4.5 L0,8 Z" fill="{ORANGE}"/></marker></defs>{body}</svg>')


def box(x, y, w, h, fr, en=None, style="n", fs=11.4, es=9.4):
    fill, stroke, tc, sc = {"n": (CARD, INK, INK, GREY), "a": (ORANGE, ORANGE, "#fff", "#fff1e6"), "d": (DARK, DARK, "#fff", "#cfcdc8"), "s": (PAPER, "#b9b1a3", INK, GREY)}[style]
    out = f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="9" fill="{fill}" stroke="{stroke}" stroke-width="{0 if style == "a" else 1.1}"/>'
    fl, el = fr.split("\n"), (en.split("\n") if en else [])
    n = len(fl) + len(el)
    lh = 1.22
    y0 = y + h / 2 - (len(fl) * fs * lh + len(el) * es * lh) / 2 + fs * 0.92
    for i, ln in enumerate(fl):
        out += f'<text x="{x + w / 2}" y="{y0 + i * fs * lh:.1f}" text-anchor="middle" font-size="{fs}" font-weight="700" fill="{tc}">{ln}</text>'
    y1 = y0 + (len(fl) - 1) * fs * lh + fs * 0.35
    for i, ln in enumerate(el):
        out += f'<text x="{x + w / 2}" y="{y1 + (i + 1) * es * lh:.1f}" text-anchor="middle" font-size="{es}" fill="{sc}">{ln}</text>'
    return out


def arrow(x1, y1, x2, y2, accent=False, dash=False):
    c, m = (ORANGE, "ao") if accent else (INK, "ar")
    d = ' stroke-dasharray="5 4"' if dash else ""
    return f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" stroke="{c}" stroke-width="1.5"{d} marker-end="url(#{m})"/>'


def text(x, y, s, size=10, anchor="middle", color=GREY, weight=400, italic=False):
    st = ' font-style="italic"' if italic else ""
    return f'<text x="{x}" y="{y}" text-anchor="{anchor}" font-size="{size}" fill="{color}" font-weight="{weight}"{st}>{s}</text>'


def bi_text(x, y, fr, en, anchor="middle", size=11, es=9.2, weight=700):
    return text(x, y, fr, size, anchor, INK, weight) + text(x, y + es + 3, en, es, anchor, GREY)


# 1. architecture d'ensemble ---------------------------------------------------------------------------------------------------------------------
def architecture():
    b = box(10, 8, 395, 56, "Interface", "Édition · Trouver · Agent  /  Edit · Find · Agent", "d")
    b += box(415, 8, 175, 56, "Extension Finder", "Finder extension", "s")
    for x in (80, 225, 375):
        b += arrow(x, 64, x, 98)
    b += arrow(520, 64, 520, 98, dash=True)
    b += box(10, 100, 140, 56, "Lecteur · timeline", "Player · timeline")
    b += box(160, 100, 130, 56, "Export", None)
    b += box(300, 100, 140, 56, "Trouver", "Find")
    b += box(450, 100, 140, 56, "Agent", None)
    b += arrow(370, 156, 370, 192, accent=True)
    b += arrow(520, 156, 520, 192)
    b += box(160, 194, 280, 66, "Analyse (programme à part)", "Analysis (separate program)", "a")
    b += box(450, 194, 140, 66, "Serveur MCP", "MCP server")
    b += arrow(450, 227, 442, 227, dash=True)
    b += arrow(300, 260, 300, 284, accent=True)
    for x, w, fr, en in [(10, 140, "Sessions", None), (160, 130, "Analyses", "Analyses"), (300, 140, "Visages", "Faces"), (450, 140, "Modèle", "Model")]:
        b += box(x, 286, w, 44, fr, en if en and en != fr else None, "s", fs=11)
    return svg(340, b)


# 2. la passe d'analyse ---------------------------------------------------------------------------------------------------------------------------
def analysis():
    b = box(8, 76, 92, 66, "Fichier", "File", "d")
    b += arrow(100, 98, 128, 62)
    b += arrow(100, 122, 128, 160)
    b += box(130, 24, 160, 66, "Lecture des images", "Reading the pictures")
    b += box(130, 130, 160, 66, "Lecture du son", "Reading the sound")
    for y0, y1 in ((52, 28), (52, 98)):
        b += arrow(290, y0, 328, y1)
    b += arrow(290, 162, 328, 162)
    b += box(330, 4, 190, 50, "Coupures du montage", "Editing cuts", "s")
    b += box(330, 74, 190, 50, "Scènes (Vision)", "Scenes (Vision)", "s")
    b += box(330, 138, 190, 50, "Sons (SoundAnalysis)", "Sounds (SoundAnalysis)", "s")
    for y in (29, 99, 163):
        b += arrow(520, y, 536, 98)
    b += box(538, 62, 56, 72, "Index", None, "a", fs=11)
    return svg(206, b)


# 3. une requête --------------------------------------------------------------------------------------------------------------------------------------
def query():
    X0, WW, D = 150, 440, 60.0
    def x(s): return X0 + WW * s / D
    def strip(y, fr, en, ivs, color, h=22):
        o = bi_text(X0 - 12, y + 10, fr, en, "end", 11, 9)
        o += f'<rect x="{X0}" y="{y}" width="{WW}" height="{h}" rx="5" fill="#ece6da"/>'
        for a, b_ in ivs:
            o += f'<rect x="{x(a):.1f}" y="{y}" width="{x(b_) - x(a):.1f}" height="{h}" rx="4" fill="{color}"/>'
        return o
    b = ""
    for s in (12, 38, 52):
        b += f'<line x1="{x(s):.1f}" y1="20" x2="{x(s):.1f}" y2="214" stroke="{GREY}" stroke-width=".9" stroke-dasharray="3 4"/>'
    b += text(X0, 13, "coupures du montage  /  editing cuts", 9, "start", GREY, 400, True)
    b += strip(26, "Personnage", "Character", [(5, 25), (35, 50)], BLUE)
    b += strip(62, "Feu", "Fire", [(18, 30), (40, 46)], ORANGE)
    b += strip(98, "Musique", "Music", [(20, 28)], GREY)
    b += strip(142, "Retenus", "Kept", [(18, 25), (40, 46)], INK)
    b += text(x(21.5), 136, "écarté : musique  /  dropped: music", 9, "middle", GREY, 600, True)
    b += bi_text(X0 - 12, 188, "Plans entiers", "Whole shots", "end", 11, 9)
    b += f'<rect x="{X0}" y="178" width="{WW}" height="22" rx="5" fill="#ece6da"/>'
    b += f'<rect x="{x(12):.1f}" y="178" width="{x(38) - x(12):.1f}" height="22" rx="4" fill="none" stroke="{GREY}" stroke-dasharray="4 3"/>'
    b += f'<rect x="{x(38):.1f}" y="178" width="{x(52) - x(38):.1f}" height="22" rx="4" fill="{ORANGE}"/>'
    return svg(214, b)


# 4. la chaîne des personnages ---------------------------------------------------------------------------------------------------------------
def faces():
    w, h = 102, 70
    xs = [4, 128, 252, 376, 498]
    steps = [("1 image\npar seconde", "1 frame\nper second", "d"), ("Visages\net repères", "Faces and\nlandmarks", "n"), ("Visage\nredressé", "Straightened\nface", "n"),
             ("Empreinte\n(512 nombres)", "Fingerprint\n(512 numbers)", "a"), ("Suivis", "Tracks", "n")]
    b = ""
    for x, (fr, en, st) in zip(xs, steps):
        b += box(x, 8, w, h, fr, en, st, fs=11, es=9)
    for i in range(4):
        b += arrow(xs[i] + w, 43, xs[i + 1], 43, accent=(i == 2))
    b += arrow(549, 78, 549, 122)
    b += box(498, 124, 102, h, "Groupes", "Groups", "n", fs=11)
    b += arrow(498, 159, 462, 159)
    b += box(252, 124, 208, h, "Personnages", "Characters", "a", fs=12.5, es=10)
    b += arrow(252, 159, 216, 159)
    b += box(4, 124, 210, h, "Vignettes rondes", "Round thumbnails", "s", fs=11)
    return svg(206, b)


# 5. les candidats ---------------------------------------------------------------------------------------------------------------------------------
def models():
    rows = [("Empreinte d'Apple", "Apple's built-in", 0.85, 0.80, "0 Mo / MB"), ("DINOv2-S", "", 0.77, 0.76, "41 Mo / MB"), ("SFace", "", 0.999, 0.983, "18 Mo / MB"), ("AuraFace", "", 0.998, 0.980, "63 Mo / MB")]
    X0, WW = 170, 290
    b = text(X0, 14, "Score de tri : 0,5 = au hasard · 1 = parfait   /   Sorting score: 0.5 = chance · 1 = perfect", 9.6, "start", GREY, 400, True)
    for i, (n, e, a, d, s) in enumerate(rows):
        y = 30 + i * 52
        win = n == "AuraFace"
        b += text(X0 - 12, y + 15, n, 12, "end", INK, 700 if win else 600)
        if e:
            b += text(X0 - 12, y + 29, e, 9.4, "end", GREY)
        for j, (v, col) in enumerate([(a, ORANGE if win else INK), (d, "#b9b1a3")]):
            yy = y + j * 20
            wv = WW * (v - 0.5) / 0.5
            b += f'<rect x="{X0}" y="{yy}" width="{WW}" height="15" rx="4" fill="#ece6da"/><rect x="{X0}" y="{yy}" width="{wv:.1f}" height="15" rx="4" fill="{col}"/>'
            b += text(X0 + WW + 8, yy + 12, f"{v:.3f}".replace(".", ","), 10.4, "start", INK)
        b += text(X0 + WW + 62, y + 23, s, 10, "start", GREY)
    b += f'<rect x="{X0}" y="242" width="14" height="10" rx="2" fill="{INK}"/>' + text(X0 + 20, 251, "visages nets / clear faces", 9.6, "start", GREY)
    b += f'<rect x="{X0 + 190}" y="242" width="14" height="10" rx="2" fill="#b9b1a3"/>' + text(X0 + 210, 251, "visages difficiles / hard cases", 9.6, "start", GREY)
    return svg(260, b)


# 6. le chemin d'un ordre d'agent ---------------------------------------------------------------------------------------------------------------
def agent():
    b = box(6, 36, 130, 66, "Agent", "Claude Code, Cursor…", "d")
    b += arrow(136, 69, 168, 69)
    b += text(152, 60, "MCP", 9, "middle", GREY, 600)
    b += box(170, 36, 130, 66, "mslice-mcp", None)
    b += arrow(300, 54, 332, 32)
    b += arrow(300, 86, 332, 112)
    b += box(334, 6, 130, 56, "Appli ouverte ?", "App open?", "s", fs=11)
    b += box(334, 86, 130, 56, "Sinon : seul", "Else: standalone", "s", fs=11)
    b += arrow(464, 34, 488, 58)
    b += arrow(464, 114, 488, 92)
    b += box(490, 40, 104, 70, "Outils\nde mSLICE", "mSLICE\ntools", "a", fs=11, es=9)
    b += arrow(542, 110, 542, 140)
    b += box(296, 142, 298, 52, "Nouveaux fichiers seulement", "New files only · never overwritten or deleted", "n", fs=11.4)
    return svg(204, b)


# 7. mesures -------------------------------------------------------------------------------------------------------------------------------------------
def timing():
    X0, WW = 220, 330
    rows = [("Vidéo de test", "Test video", 1685, GREY, "28:05"), ("Analyse : scènes, sons", "Analysis: scenes, sounds", 25, ORANGE, "25 s"),
            ("Reconnaissance des personnages", "Character recognition", 22, ORANGE, "22 s"), ("Export en copie directe", "Direct-copy export", 1, INK, "< 1 s")]
    b = ""
    for i, (fr, en, v, c, lab) in enumerate(rows):
        y = 6 + i * 44
        w = max(WW * v / 1685, 4)
        b += bi_text(X0 - 12, y + 12, fr, en, "end", 10.6, 9)
        b += f'<rect x="{X0}" y="{y}" width="{WW}" height="26" rx="5" fill="#ece6da"/><rect x="{X0}" y="{y}" width="{w:.1f}" height="26" rx="5" fill="{c}"/>'
        b += text(X0 + w + 8 if w < 250 else X0 + w - 8, y + 18, lab, 11.4, "start" if w < 250 else "end", INK if w < 250 else "#fff", 700)
    return svg(184, b)


# 8. dossiers de données ------------------------------------------------------------------------------------------------------------------------
def folders():
    lines = [("Application Support/mSLICE/", "", "", 0), ("sessions/", "les morceaux de chaque fichier", "each file's pieces", 1), ("index/…  .msidx", "plans, scènes, sons", "shots, scenes, sounds", 1),
             ("index/…  .msfaces", "visages, personnages, noms", "faces, characters, names", 1), ("models/characters/", "le modèle des personnages", "the characters model", 1), ("agent.log", "journal des actions de l'agent", "log of the agent's actions", 1)]
    b = ""
    for i, (n, fr, en, lv) in enumerate(lines):
        y = 20 + i * 36
        b += text(10 + lv * 18, y, ("▸ " if lv else "") + n, 12, "start", INK, 700 if not lv else 600)
        if fr:
            b += text(250, y - 4, fr, 11, "start", INK, 400) + text(250, y + 11, en, 9.4, "start", GREY)
    return svg(232, b)
