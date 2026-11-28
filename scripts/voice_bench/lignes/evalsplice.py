import numpy as np, json
X=np.load("X.npy"); t=np.load("t.npy")
segs=json.load(open("splice_ranges.json")); lab=np.array(json.load(open("splice_lab.json")))
enroll=json.load(open("enroll.json"))
et=json.load(open("splice_emb_tile.json")); eg=json.load(open("splice_emb_grid.json"))[0]
TV=np.array([ [w["v"] for w in s][0] if len(s) else np.zeros(512) for s in et]); 
TVm=np.array([np.mean([w["v"] for w in s],0) if len(s) else np.zeros(512) for s in et])
GT=np.array([w["t"] for w in eg]); GV=np.array([w["v"] for w in eg])
groups=sorted(set(a[2] for a in enroll))
protos={}
allenroll=[]
for gk in groups:
    idx=np.concatenate([np.arange(a[0],a[1]+1) for a in enroll if a[2]==gk]); protos[gk]=X[idx]; allenroll.append(X[idx])
mu=np.concatenate(allenroll).mean(0)
def unit(v): return v/ (np.linalg.norm(v,axis=-1,keepdims=True)+1e-9)
def cents(center):
    return np.array([unit((unit(protos[k]-(mu if center else 0))).mean(0)) for k in groups])
def classify(V,center,cents_):
    Z=unit(V-(mu if center else 0)); return np.array(groups)[(Z@cents_.T).argmax(1)]
tests=[i for i in range(len(segs)) if lab[i] in groups]
def acc(pred): return np.mean(pred[tests]==lab[tests])
# (a) grille : fenêtres dont le centre tombe dans le segment
GV_seg=[]; ok=[]
for s in segs:
    m=(GT>=s[0])&(GT<=s[1]); 
    GV_seg.append(unit(GV[m]).mean(0) if m.any() else np.zeros(512))
GV_seg=np.array(GV_seg)
for center in (False,True):
    c=cents(center)
    print("centrage" if center else "brut    ","| grille (ancien)  %.1f %% | segment répété %.1f %% | segment répété (moy. fenêtres) %.1f %%"%(100*acc(classify(GV_seg,center,c)),100*acc(classify(TV,center,c)),100*acc(classify(TVm,center,c))))
# (b) fenêtres de grille entièrement DANS le segment seulement (si assez long) 
print("segments:",len(tests)," classes:",np.bincount(lab[tests]))
for lo,hi in ((0.7,1.0),(1.0,1.3),(1.3,1.7)):
    sel=[i for i in tests if lo<=segs[i][1]-segs[i][0]<hi]
    if sel:
        c=cents(True)
        print("durée %.1f–%.1f s (%d seg): grille %.0f %% | répété %.0f %%"%(lo,hi,len(sel),100*np.mean(classify(GV_seg,True,c)[sel]==lab[sel]),100*np.mean(classify(TV,True,c)[sel]==lab[sel])))
