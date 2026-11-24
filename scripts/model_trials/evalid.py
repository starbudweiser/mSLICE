# Évaluation des empreintes d'identité : vérification (étiquettes anonymes), regroupement, et critères sans étiquette (même image, même plan).
import json, os, sys, bisect, itertools, warnings
warnings.filterwarnings('ignore')
import numpy as np
from scipy.cluster.hierarchy import linkage, fcluster
from scipy.spatial.distance import squareform
from sklearn.metrics import roc_auc_score, roc_curve

M = [json.loads(l) for l in open('data/full/meta.jsonl')]
ids = [m['id'] for m in M]; idx = {i: k for k, i in enumerate(ids)}
N = len(M)
Lj = json.load(open('data/label/labels_final.json')); lab = {k: Lj['merge'].get(v, v) for k, v in Lj['labels'].items()}
equiv = {frozenset((Lj['merge'].get(a, a), Lj['merge'].get(b, b))) for a, b in Lj['equiv']}
EXT = os.environ.get('EXT') == '1'
LI = np.array([idx[k] for k in lab]); LL = np.array([lab[k] for k in lab])
cuts = sorted(float(x) for x in open('data/cuts.txt'))
shot = np.array([bisect.bisect_right(cuts, m['t']) for m in M]); T = np.array([m['t'] for m in M])
B = np.array([m['box'] for m in M])
frame = {}
for k, m in enumerate(M): frame.setdefault(m['t'], []).append(k)

# --- tracklets : même plan, échantillons voisins, boîte continue
parent = list(range(N))
def find(a):
    while parent[a] != a: parent[a] = parent[parent[a]]; a = parent[a]
    return a
ts = sorted(frame)
for t0, t1 in zip(ts[:-1], ts[1:]):
    if t1 - t0 > 1.5: continue
    for a in frame[t0]:
        for b in frame[t1]:
            if shot[a] != shot[b]: continue
            ca = B[a, :2] + B[a, 2:] / 2; cb = B[b, :2] + B[b, 2:] / 2
            r = B[b, 2] / B[a, 2]
            if np.abs(ca - cb).max() < 0.5 * max(B[a, 2], B[b, 2]) and 0.6 < r < 1.67: parent[find(a)] = find(b)
track = np.array([find(k) for k in range(N)])
ntrack = len(set(track))
if EXT:
    tl = {}
    for k, v in lab.items(): tl.setdefault(track[idx[k]], set()).add(v)
    ok_t = {t for t, v in tl.items() if len(v) == 1}
    lab2 = {}
    for k in range(N):
        if track[k] in ok_t: lab2[ids[k]] = next(iter(tl[track[k]]))
    LI = np.array([idx[k] for k in lab2]); LL = np.array([lab2[k] for k in lab2])
    print(f'étiquettes étendues par tracklet : {len(lab)} -> {len(lab2)}', file=sys.stderr)
# paires positives « même tracklet, écart ≥ 2 s » et négatives « même image »
pos_tr = [(a, b) for tr in set(track) for a, b in itertools.combinations([k for k in np.where(track == tr)[0]], 2) if abs(T[a] - T[b]) >= 2]
neg_fr = [(a, b) for ks in frame.values() for a, b in itertools.combinations(ks, 2)]
pos_tr = np.array(pos_tr); neg_fr = np.array(neg_fr)

def load(path, dim=None):
    if path.endswith('.f32'):
        j = json.load(open(path[:-4] + '.json')); a = np.fromfile(path, dtype=np.float32).reshape(-1, j['dim']); fid = j['ids']
    else:
        a = np.load(path); fid = json.load(open('feats/%s_ids.json' % next(k for k in ('person224','face224','align224','tight224','align112') if k in path)))
    full = np.full((N, a.shape[1]), np.nan, dtype=np.float32)
    for r, i in enumerate(fid): full[idx[i]] = a[r]
    return full
def prep(E, center):
    ok = ~np.isnan(E[:, 0]); E = E.copy()
    if center: E[ok] -= E[ok].mean(0)
    E[ok] /= np.linalg.norm(E[ok], axis=1, keepdims=True) + 1e-9
    return E, ok

def evaluate(name, E, center=False):
    E, ok = prep(E, center)
    S = np.where(ok[:, None] & ok[None, :], E @ E.T, np.nan)
    keep = ok[LI]; li = LI[keep]; ll = LL[keep]
    iu = np.triu_indices(len(li), 1); a, b = li[iu[0]], li[iu[1]]; la, lb = ll[iu[0]], ll[iu[1]]
    same = la == lb
    skip = np.array([(not s) and frozenset((x, y)) in equiv for s, x, y in zip(same, la, lb)])
    if EXT: skip = skip | (track[a] == track[b])        # paires d'un même tracklet : triviales, ignorées
    y = same[~skip]; s = S[a, b][~skip]
    auc = roc_auc_score(y, s); fpr, tpr, thr = roc_curve(y, s)
    eer = fpr[np.argmin(np.abs(fpr - (1 - tpr)))]
    t1 = tpr[np.searchsorted(fpr, 0.01, side='right') - 1]; t01 = tpr[np.searchsorted(fpr, 0.001, side='right') - 1]
    # critères sans étiquette (tous les visages)
    sneg = S[neg_fr[:, 0], neg_fr[:, 1]]; sneg = sneg[~np.isnan(sneg)]
    spos = S[pos_tr[:, 0], pos_tr[:, 1]]; spos = spos[~np.isnan(spos)]
    tau = np.quantile(sneg, 0.995)                      # seuil : 0,5 % des paires « même image » (personnes différentes) dépassent
    trk_recall = float((spos >= tau).mean())
    # regroupement (liaison moyenne) sur tous les visages disponibles
    sel = np.where(ok)[0]; D = 1 - S[np.ix_(sel, sel)]; np.fill_diagonal(D, 0); D = np.clip((D + D.T) / 2, 0, None)
    Z = linkage(squareform(D, checks=False), 'average')
    pos_in = {k: r for r, k in enumerate(sel)}
    lidx = np.array([pos_in[k] for k in li]); best = None; table = []
    for d in np.linspace(0.2, 1.2, 51):
        cl = fcluster(Z, d, 'distance')
        ca = cl[lidx[iu[0]]]; cb = cl[lidx[iu[1]]]; tog = (ca == cb)[~skip]
        tp = (tog & y).sum(); fp = (tog & ~y).sum(); fn = (~tog & y).sum()
        P = tp / max(tp + fp, 1); R = tp / max(tp + fn, 1)
        # impureté sans étiquette : couples « même image » réunis dans un groupe
        viol = float((cl[sel.searchsorted(neg_fr[:, 0])] == cl[sel.searchsorted(neg_fr[:, 1])]).mean()) if len(neg_fr) else 0
        ncl = len(set(cl)); big = len([c for c in set(cl) if (cl == c).sum() >= 5])
        table.append((d, P, R, ncl, big, viol))
    ok98 = [t for t in table if t[1] >= 0.98]
    op = max(ok98, key=lambda t: t[2]) if ok98 else None
    f1b = max(table, key=lambda t: 2 * t[1] * t[2] / max(t[1] + t[2], 1e-9))
    q=lambda v,qs:[round(float(np.quantile(v,x)),2) for x in qs]
    return dict(table=[list(map(float,t)) for t in table], neg_q=q(sneg,[.5,.9,.99,.995,.999]), pos_q=q(spos,[.05,.25,.5]), name=name, n=int(ok.sum()), auc=auc, eer=eer, tpr_fpr1=t1, tpr_fpr01=t01, track_recall=trk_recall, tau=float(tau),
                op98=dict(zip(['d', 'P', 'R', 'clusters', 'clusters5', 'sameframe_merged'], op)) if op else None,
                f1best=dict(zip(['d', 'P', 'R', 'clusters', 'clusters5', 'sameframe_merged'], f1b)))

if __name__ == '__main__':
    print(f'{N} visages, {len(lab)} étiquetés, {ntrack} tracklets, {len(pos_tr)} paires même-tracklet, {len(neg_fr)} paires même-image', file=sys.stderr)
    sets = [('Apple (empreinte générique) – recadrage large', 'feats/apple_face224.f32'), ('Apple – visage aligné 112', 'feats/apple_align112.f32'),
            ('Apple – personne entière', 'feats/apple_person224.f32'),
            ('DINOv2-S CLS – recadrage large', 'feats/dinov2_face224_cls.npy'), ('DINOv2-S moyenne – recadrage large', 'feats/dinov2_face224_avg.npy'),
            ('DINOv2-S CLS – personne entière', 'feats/dinov2_person224_cls.npy'), ('DINOv2-S moyenne – personne entière', 'feats/dinov2_person224_avg.npy'),
            ('DINOv2-S CLS – visage aligné ×2', 'feats/dinov2_align224_cls.npy'), ('DINOv2-S moyenne – visage aligné ×2', 'feats/dinov2_align224_avg.npy'), ('DINOv2-S CLS – visage serré', 'feats/dinov2_tight224_cls.npy'), ('DINOv2-S moyenne – visage serré', 'feats/dinov2_tight224_avg.npy'), ('SFace – visage aligné', 'feats/sface_align112_emb.npy'), ('AuraFace – visage aligné', 'feats/auraface_align112_emb.npy'), ('AuraFace FINAL (zip hébergeable)', 'feats/auraface_final_align112_emb.npy'), ('AuraFace palettisé 8 bits', 'feats/auraface_p8_align112_emb.npy'), ('AuraFace palettisé 6 bits', 'feats/auraface_p6_align112_emb.npy'), ('AuraFace palettisé 4 bits', 'feats/auraface_p4_align112_emb.npy')]
    out = []
    for name, p in sets:
        if not os.path.exists(p): continue
        E = load(p)
        for c in (False, True):
            if c and ('SFace' in name or 'AuraFace' in name): continue
            r = evaluate(name + (' (centré)' if c else ''), E, c); out.append(r)
            o = r['op98']
            print(f"{r['name']:<58} n={r['n']:<5} AUC {r['auc']:.3f} EER {r['eer']:.3f} TPR@1% {r['tpr_fpr1']:.2f} @0.1% {r['tpr_fpr01']:.2f} | suivi {r['track_recall']:.2f} | " +
                  (f"P≥98 %: R {o['R']:.2f} ({o['clusters']} groupes, {o['clusters5']} ≥5) mêmeimage {o['sameframe_merged']*100:.2f}% d={o['d']:.2f}" if o else 'aucun point P≥98 %'), flush=True)
    json.dump(out, open('feats/results.json', 'w'), indent=1)
