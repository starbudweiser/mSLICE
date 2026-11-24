"""mSLICE — bibliothèque de mise en page des PDF (A4 paysage, double page bilingue FR | EN, esprit magazine).

Chaque texte est un couple (français, anglais) ; une page est une suite de blocs bilingues. Les documents (conception.py, interface.py, documentation.py)
décrivent leurs pages avec ces fonctions, `render()` écrit le HTML et `to_pdf()` l'imprime avec un Chromium sans fenêtre.
"""
import html as _html
import os
import subprocess

HERE = os.path.dirname(os.path.abspath(__file__))
BRAVE = "/Applications/Brave Browser.app/Contents/MacOS/Brave Browser"

ORANGE, INK, PAPER = "#d9622b", "#26231e", "#f6f2ea"

CSS = f"""
@page {{ size: 297mm 210mm; margin: 0; }}
* {{ box-sizing: border-box; }}
html {{ -webkit-print-color-adjust: exact; print-color-adjust: exact; }}
body {{ margin: 0; background: #fff; color: {INK}; font: 11.6pt/1.55 -apple-system, "SF Pro Text", "Helvetica Neue", Helvetica, sans-serif; }}
:root {{ --paper: {PAPER}; --ink: {INK}; --ink2: #4f493f; --line: #ddd5c8; --accent: {ORANGE}; --dark: #131316; --card: #fffdf9; }}
.serif {{ font-family: "Iowan Old Style", "Palatino", "Hoefler Text", Georgia, serif; }}
.m {{ color: var(--accent); }}
.page {{ position: relative; width: 297mm; height: 210mm; overflow: hidden; page-break-after: always; break-after: page; background: var(--paper); padding: 16mm 15mm 14mm 15mm; }}
.page:last-child {{ page-break-after: auto; break-after: auto; }}
.rh {{ position: absolute; left: 15mm; right: 15mm; top: 7mm; display: flex; justify-content: space-between; font-size: 7.8pt; letter-spacing: .14em; text-transform: uppercase; color: var(--ink2); }}
.rf {{ position: absolute; left: 15mm; right: 15mm; bottom: 6mm; display: flex; justify-content: space-between; font-size: 7.8pt; color: var(--ink2); }}
.rf b {{ color: var(--ink); }}
.bi {{ display: grid; grid-template-columns: 1fr 1fr; gap: 0 12mm; position: relative; }}
.bi::after {{ content: ""; position: absolute; left: 50%; top: 0; bottom: 0; width: 0; border-left: .5pt solid var(--line); }}
.bi > .col {{ min-width: 0; }}
.tag {{ display: inline-block; font-size: 7.4pt; letter-spacing: .16em; text-transform: uppercase; color: var(--ink2); margin-bottom: 3px; }}
.kick {{ font-size: 8.4pt; letter-spacing: .2em; text-transform: uppercase; color: var(--accent); font-weight: 700; margin-bottom: 4px; }}
h1, h2, h3, h4 {{ font-family: "Iowan Old Style", "Palatino", Georgia, serif; font-weight: 600; line-height: 1.12; margin: 0; letter-spacing: -.005em; }}
h2 {{ font-size: 25pt; margin-bottom: 8px; }}
h3 {{ font-size: 15.5pt; margin: 12px 0 5px; }}
h4 {{ font-size: 12pt; margin: 9px 0 3px; font-family: -apple-system, "SF Pro Text", Helvetica, sans-serif; font-weight: 700; }}
p {{ margin: 0 0 8px; }}
.lead {{ font-family: "Iowan Old Style", Palatino, Georgia, serif; font-size: 14.5pt; line-height: 1.45; color: #2e2a23; }}
.drop::first-letter {{ float: left; font-family: "Iowan Old Style", Palatino, Georgia, serif; font-size: 40pt; line-height: .82; padding: 3px 6px 0 0; color: var(--accent); font-weight: 600; }}
ul, ol {{ margin: 0 0 6px; padding-left: 15px; }}
li {{ margin: 1.5px 0; }}
code, .mono {{ font-family: "SF Mono", Menlo, monospace; font-size: 9.6pt; }}
code {{ background: #ece6da; border-radius: 3px; padding: 0 3px; }}
kbd {{ font-family: "SF Mono", Menlo, monospace; font-size: 9pt; background: #fff; border: .6pt solid #cfc6b6; border-bottom-width: 1.2pt; border-radius: 3px; padding: 0 4px; }}
pre {{ background: #1b1b1e; color: #e8e6e3; border-radius: 7px; padding: 8px 10px; font: 9pt/1.45 "SF Mono", Menlo, monospace; white-space: pre-wrap; margin: 4px 0 8px; }}
table {{ width: 100%; border-collapse: collapse; font-size: 10.4pt; margin: 4px 0 8px; }}
th {{ text-align: left; font-weight: 700; font-size: 8pt; letter-spacing: .1em; text-transform: uppercase; color: var(--ink2); border-bottom: 1pt solid var(--ink); padding: 3px 6px 3px 0; }}
td {{ padding: 4.4px 7px 4.4px 0; border-bottom: .5pt solid var(--line); vertical-align: top; }}
td:first-child {{ font-weight: 600; }}
.note {{ background: var(--card); border-left: 2.4pt solid var(--accent); border-radius: 0 8px 8px 0; padding: 8px 12px; margin: 8px 0 10px; font-size: 10.8pt; }}
.note.dark {{ background: var(--dark); color: #eceae6; border-left-color: #0a84ff; }}
.pull {{ font-family: "Iowan Old Style", Palatino, Georgia, serif; font-size: 19pt; line-height: 1.22; font-style: italic; color: var(--ink); border-top: 2pt solid var(--accent); padding-top: 8px; margin: 6px 0 10px; }}
.stats {{ display: grid; grid-auto-flow: column; grid-auto-columns: 1fr; gap: 0 8mm; margin: 8px 0 10px; }}
.stat {{ border-top: 1.4pt solid var(--ink); padding-top: 5px; }}
.stat .v {{ font-family: "Iowan Old Style", Palatino, Georgia, serif; font-size: 27pt; line-height: 1; font-weight: 600; white-space: nowrap; }}
.stat .v small {{ font-size: 12pt; color: var(--ink2); font-weight: 400; }}
.stat .l {{ font-size: 9.6pt; color: var(--ink2); margin-top: 3px; }}
figure {{ margin: 6px 0 8px; }}
figure img, figure svg {{ display: block; max-width: 100%; }}
figcaption {{ font-size: 9pt; color: var(--ink2); font-style: italic; margin-top: 5px; }}
.shot {{ border-radius: 9px; overflow: hidden; box-shadow: 0 1.2mm 4mm rgba(38,35,30,.22), 0 0 0 .4pt rgba(38,35,30,.25); background: #000; }}
.shot img {{ width: 100%; }}
.full {{ grid-column: 1 / -1; }}
.band {{ position: absolute; left: 0; right: 0; background: var(--dark); color: #fff; }}
.card {{ background: var(--card); border: .5pt solid var(--line); border-radius: 9px; padding: 8px 10px; }}
.card h4 {{ margin-top: 0; }}
.grid2 {{ display: grid; grid-template-columns: 1fr 1fr; gap: 6px 8px; }}
.grid3 {{ display: grid; grid-template-columns: 1fr 1fr 1fr; gap: 6px 8px; }}
.grid4 {{ display: grid; grid-template-columns: repeat(4, 1fr); gap: 6px 8px; }}
.sw {{ border-radius: 8px; padding: 8px 8px 6px; font-size: 8.6pt; border: .5pt solid rgba(0,0,0,.12); }}
.sw b {{ display: block; font-size: 10pt; }}
.pillx {{ display: inline-block; border-radius: 99px; background: #ece6da; padding: 1px 9px; font-size: 8pt; font-weight: 600; }}
.mk {{ position: absolute; width: 18px; height: 18px; margin: -9px 0 0 -9px; border-radius: 50%; background: var(--accent); color: #fff; font-size: 9.6pt; font-weight: 700; line-height: 18px; text-align: center; box-shadow: 0 0 0 1.4pt #fff; }}
.legend {{ counter-reset: lg; list-style: none; padding: 0; margin: 0; font-size: 10.4pt; }}
.legend li {{ position: relative; padding-left: 22px; margin: 4px 0; }}
.legend li::before {{ counter-increment: lg; content: counter(lg); position: absolute; left: 0; top: 1px; width: 15px; height: 15px; border-radius: 50%; background: var(--accent); color: #fff; font-size: 8.6pt; font-weight: 700; line-height: 15px; text-align: center; }}

/* couverture */
.cover {{ padding: 0; background: var(--paper); }}
.cover .art {{ position: absolute; left: 127mm; top: 0; width: 170mm; height: 210mm; object-fit: cover; }}
.cover .plate {{ position: absolute; left: 15mm; top: 15mm; bottom: 15mm; width: 100mm; padding: 10mm 0 0; display: flex; flex-direction: column; }}
.cover h1 {{ font-size: 60pt; letter-spacing: -.02em; line-height: 1; margin: 6px 0 8px; }}
.cover .kind {{ font-family: "Iowan Old Style", Palatino, Georgia, serif; font-size: 22pt; font-style: italic; line-height: 1.18; margin-bottom: 10px; }}
.cover .sub p {{ font-size: 11.6pt; color: #3a352d; margin-bottom: 5px; }}
.cover .meta {{ margin-top: auto; font-size: 8.8pt; color: var(--ink2); border-top: .6pt solid var(--line); padding-top: 6px; }}
.cover .meta b {{ color: var(--ink); }}

/* ouverture de chapitre */
.opener {{ padding: 0; }}
.opener .art {{ position: absolute; left: 0; top: 0; width: 112mm; height: 210mm; object-fit: cover; }}
.opener .txt {{ position: absolute; left: 126mm; right: 15mm; top: 34mm; bottom: 14mm; }}
.opener .num {{ font-family: "Iowan Old Style", Palatino, Georgia, serif; font-size: 96pt; line-height: .85; color: var(--accent); font-weight: 600; margin-bottom: 8px; }}
.opener.right .art {{ left: auto; right: 0; }}
.opener .one {{ min-width: 0; }}
.opener.right .txt {{ left: 15mm; right: 126mm; }}

/* sommaire */
.toc {{ display: grid; grid-template-columns: 1fr 1fr; gap: 0 12mm; }}
.toc .it {{ display: grid; grid-template-columns: 17mm 1fr auto; align-items: baseline; padding: 4.4px 0; border-bottom: .5pt solid var(--line); }}
.toc .it .n {{ font-family: "Iowan Old Style", Palatino, Georgia, serif; font-size: 17pt; color: var(--accent); }}
.toc .it .t {{ font-size: 11.4pt; font-weight: 600; }}
.toc .it .p {{ font-size: 9.6pt; color: var(--ink2); }}
.dark-page {{ background: var(--dark); color: #eceae6; }}
.dark-page .rh, .dark-page .rf {{ color: #8d8a85; }}
.dark-page .rf b {{ color: #fff; }}
.dark-page h2, .dark-page h3 {{ color: #fff; }}
.dark-page td {{ border-color: #2e2e33; }}
.dark-page th {{ color: #9a978f; border-color: #55534e; }}
"""


ART_BG = {"../img/cover-conception.jpg": "#f1ddb7", "../img/cover-interface.jpg": "#efdcbd", "../img/cover-doc.jpg": "#ecd8b6"}


def esc(s):
    return _html.escape(s, quote=False)


class Doc:
    def __init__(self, key, title, kind, cover_art, version="1.3", date=("24 novembre 2026", "November 24, 2026")):
        self.key, self.title, self.kind, self.cover_art, self.version, self.date = key, title, kind, cover_art, version, date
        self.pages = []
        self.n = 0

    # --- pages -------------------------------------------------------------------------------------------------------------------------------
    def add(self, inner, section=("", ""), cls="", numbered=True):
        self.n += 1
        head = f'<div class="rh"><span><span class="m">m</span>SLICE · {esc(self.kind[0])} · {esc(self.kind[1])}</span><span>{esc(section[0])} · {esc(section[1])}</span></div>' if numbered and section[0] else ""
        foot = f'<div class="rf"><span>DESKTOP MAC TOOLKIT · v{self.version}</span><b>{self.n}</b></div>' if numbered else ""
        self.pages.append(f'<section class="page {cls}">{head}{inner}{foot}</section>')

    def cover(self, sub, meta_extra=("", "")):
        self.n += 1
        self.pages.append(f'''<section class="page cover"><img class="art" src="{self.cover_art}" alt="">
<div class="plate"><div class="kick">DESKTOP MAC TOOLKIT</div><h1><span class="m">m</span>SLICE</h1>
<div class="kind">{esc(self.kind[0])}<br><span style="color:#5f594d">{esc(self.kind[1])}</span></div>
<div class="sub"><p>{esc(sub[0])}</p><p style="color:#4f493f">{esc(sub[1])}</p></div>
<div class="meta"><b>Version {self.version}</b> · {esc(self.date[0])} · {esc(self.date[1])}<br>Starbudweiser &amp; Claude Code (Anthropic) · MIT · github.com/starbudweiser/mSLICE{(" · " + esc(meta_extra[0]) + " / " + esc(meta_extra[1])) if meta_extra[0] else ""}</div></div></section>''')

    def opener(self, num, title, intro, art, section, right=False, extra=""):
        self.n += 1
        self.pages.append(f'''<section class="page opener{' right' if right else ''}"><img class="art" src="{art}" alt="">
<div class="txt"><div class="num">{num}</div><div class="one"><div class="col">
<div class="kick">{esc(section[0])} · {esc(section[1])}</div><h2 style="font-size:30pt">{esc(title[0])}</h2><h2 style="font-size:20pt;color:#5f594d;font-style:italic;margin-bottom:12px">{esc(title[1])}</h2>
<p class="lead">{esc(intro[0])}</p><p class="lead" style="color:#5f594d">{esc(intro[1])}</p>{extra}</div></div></div></section>''')

    def toc(self, items, title=("Sommaire", "Contents"), art=None):
        art = art or self.cover_art
        rows = "".join(f'<div class="it"><span class="n">{n}</span><span class="t">{esc(t[0])}<br><span style="font-weight:400;color:#5f594d">{esc(t[1])}</span></span><span class="p">{p}</span></div>' for n, t, p in items)
        self.add(f'<div class="kick">{esc(title[0])} · {esc(title[1])}</div><h2>{esc(title[0])} <span style="color:#5f594d;font-style:italic">/ {esc(title[1])}</span></h2><div class="toc" style="margin-top:10px">{rows}</div><div style="margin-top:12mm;height:78mm;border-radius:10px;background:{ART_BG.get(art, '#f1ddb7')} url({art}) center/contain no-repeat"></div>', ("", ""), numbered=True)

    def render(self):
        body = "\n".join(self.pages)
        doc = f'<!doctype html><html lang="fr"><head><meta charset="utf-8"><title>mSLICE — {esc(self.kind[0])} / {esc(self.kind[1])}</title><style>{CSS}</style></head><body>\n{body}\n</body></html>'
        path = os.path.join(HERE, f"{self.key}.html")
        open(path, "w", encoding="utf-8").write(doc)
        return path

    def to_pdf(self, out_dir):
        path = self.render()
        os.makedirs(out_dir, exist_ok=True)
        out = os.path.join(out_dir, f"mSLICE-{self.key}-FR-EN.pdf")
        subprocess.run([BRAVE, "--headless=new", "--disable-gpu", "--no-pdf-header-footer", "--virtual-time-budget=20000", f"--print-to-pdf={out}", "file://" + path],
                       check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=240)
        return out


# --- blocs ---------------------------------------------------------------------------------------------------------------------------------
def bi(fr, en, cls=""):
    return f'<div class="bi {cls}"><div class="col" lang="fr"><span class="tag">Français</span>{fr}</div><div class="col" lang="en"><span class="tag">English</span>{en}</div></div>'


def bi2(fr, en, cls=""):
    """Comme `bi`, sans les étiquettes de langue (pour les blocs qui suivent un bloc étiqueté)."""
    return f'<div class="bi {cls}"><div class="col" lang="fr">{fr}</div><div class="col" lang="en">{en}</div></div>'


def title(kick, t, tag=True):
    k = f'<div class="kick">{esc(kick[0])} · {esc(kick[1])}</div>'
    return f'<div class="bi" style="margin-bottom:6px">{"<div class=col>" + k + "<h2>" + esc(t[0]) + "</h2></div>"}<div class="col"><div class="kick" style="color:#5f594d">&nbsp;</div><h2 style="color:#5a5448">{esc(t[1])}</h2></div></div>'


def paras(pair, lead=False, drop=False):
    c = ("lead " if lead else "") + ("drop" if drop else "")
    f = "".join(f'<p class="{c.strip()}">{p}</p>' if i == 0 else f'<p class="{("lead" if lead else "")}">{p}</p>' for i, p in enumerate(pair[0]))
    e = "".join(f'<p class="{c.strip()}">{p}</p>' if i == 0 else f'<p class="{("lead" if lead else "")}">{p}</p>' for i, p in enumerate(pair[1]))
    return f, e


def text(fr, en, lead=False, drop=False, tags=False):
    f, e = paras((fr if isinstance(fr, list) else [fr], en if isinstance(en, list) else [en]), lead, drop)
    return (bi if tags else bi2)(f, e)


def bullets(items):
    f = "<ul>" + "".join(f"<li>{a}</li>" for a, _ in items) + "</ul>"
    e = "<ul>" + "".join(f"<li>{b}</li>" for _, b in items) + "</ul>"
    return bi2(f, e)


def h3(t):
    return bi2(f"<h3>{t[0]}</h3>", f"<h3>{t[1]}</h3>")


def note(t, dark=False):
    c = "note dark" if dark else "note"
    return bi2(f'<div class="{c}">{t[0]}</div>', f'<div class="{c}">{t[1]}</div>')


def pull(t):
    return bi2(f'<div class="pull">{t[0]}</div>', f'<div class="pull">{t[1]}</div>')


def stats(items):
    """items : [(valeur, (fr, en))] ; la valeur est du HTML (ex. « 22<small> s</small> »)."""
    f = '<div class="stats">' + "".join(f'<div class="stat"><div class="v">{v}</div><div class="l">{l[0]}</div></div>' for v, l in items) + "</div>"
    e = '<div class="stats">' + "".join(f'<div class="stat"><div class="v">{v}</div><div class="l">{l[1]}</div></div>' for v, l in items) + "</div>"
    return bi2(f, e)


def table(head, rows):
    """head : (liste fr, liste en) ; rows : [(cellules fr, cellules en)]."""
    def t(i):
        return "<table><tr>" + "".join(f"<th>{h}</th>" for h in head[i]) + "</tr>" + "".join("<tr>" + "".join(f"<td>{c}</td>" for c in r[i]) + "</tr>" for r in rows) + "</table>"
    return bi2(t(0), t(1))


def fig(content, cap, shot=False, width=None):
    """content : (html fr, html en) ou un seul html (image identique des deux côtés)."""
    c = content if isinstance(content, tuple) else (content, content)
    w = f' style="width:{width}"' if width else ""
    cls = ' class="shot"' if shot else ""
    return bi2(f'<figure><div{cls}{w}>{c[0]}</div><figcaption>{cap[0]}</figcaption></figure>', f'<figure><div{cls}{w}>{c[1]}</div><figcaption>{cap[1]}</figcaption></figure>')


def wide(inner_html, cls=""):
    return f'<div class="{cls}" style="position:relative">{inner_html}</div>'


def img(src, alt="", style=""):
    return f'<img src="{src}" alt="{alt}" style="{style}">'


def legend(pair):
    f = '<ol class="legend">' + "".join(f"<li>{a}</li>" for a, _ in pair) + "</ol>"
    e = '<ol class="legend">' + "".join(f"<li>{b}</li>" for _, b in pair) + "</ol>"
    return f, e


def marked(src, marks, shot=True):
    """Capture avec repères numérotés (x, y en % de l'image)."""
    pts = "".join(f'<span class="mk" style="left:{x}%;top:{y}%">{i + 1}</span>' for i, (x, y) in enumerate(marks))
    return f'<div style="position:relative"><div class="{"shot" if shot else ""}"><img src="{src}" alt=""></div>{pts}</div>'


def full_fig(content, cap, width="100%"):
    """Figure centrée, jusqu'à la pleine largeur de la page (un seul schéma aux libellés bilingues). cap : (fr, en)."""
    return f'<figure style="margin:4px auto 8px;width:{width}">{content}<figcaption><b>{cap[0]}</b> &nbsp;·&nbsp; {cap[1]}</figcaption></figure>'


def enclair(t, label=("En clair", "In plain words")):
    """Encadré de résumé en une phrase, en tête de page."""
    f = f'<div class="note" style="border-left-width:3.4pt"><b style="color:var(--accent)">{label[0]}</b> — {t[0]}</div>'
    e = f'<div class="note" style="border-left-width:3.4pt"><b style="color:var(--accent)">{label[1]}</b> — {t[1]}</div>'
    return bi2(f, e)


def steps(items):
    """Étapes numérotées (grosse numérotation orange) : items = [(fr, en)]."""
    def one(i, s): return f'<div style="display:flex;gap:9px;margin:5px 0"><span class="serif m" style="font-size:25pt;line-height:.9;min-width:20px">{i}</span><div>{s}</div></div>'
    f = "".join(one(i + 1, a) for i, (a, _) in enumerate(items))
    e = "".join(one(i + 1, b) for i, (_, b) in enumerate(items))
    return bi2(f, e)


def cards(items, cols=2):
    """Cartes : items = [(titre fr, texte fr, titre en, texte en)]."""
    def c(ti, tx): return f'<div class="card"><h4 style="margin-top:0">{ti}</h4><p style="margin:0">{tx}</p></div>'
    f = f'<div class="grid{cols}">' + "".join(c(a, b) for a, b, _, _ in items) + "</div>"
    e = f'<div class="grid{cols}">' + "".join(c(c_, d_) for _, _, c_, d_ in items) + "</div>"
    return bi2(f, e)
