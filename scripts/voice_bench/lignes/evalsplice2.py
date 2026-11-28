import numpy as np, json
X=np.load("X.npy")
segs=json.load(open("splice_ranges.json")); lab=np.array(json.load(open("splice_lab.json")))
enroll=json.load(open("enroll.json"))
def load(p,n=None):
    e=json.load(open(p)); return np.array([np.mean([w["v"] for w in s],0) if len(s) else np.zeros(512) for s in e])
TV=load("splice_emb_tile.json"); TR=load("train_emb.json"); trl=np.array(json.load(open("train_lab.json")))
groups=sorted(set(a[2] for a in enroll))
def unit(v): return v/(np.linalg.norm(v,axis=-1,keepdims=True)+1e-9)
tests=np.array([i for i in range(len(segs)) if lab[i] in groups])
# données d'apprentissage : fenêtres entières des runs d'enrôlement + segments courts répétés
Wn=[];Wl=[]
for a in enroll: idx=np.arange(a[0],a[1]+1); Wn.append(X[idx]); Wl+= [a[2]]*len(idx)
Wn=np.concatenate(Wn); Wl=np.array(Wl)
def lda(Z,y,k=None,reg=1e-2):
    mu=Z.mean(0); cl=sorted(set(y)); Sw=np.zeros((Z.shape[1],)*2); Sb=np.zeros_like(Sw)
    for c in cl:
        Zc=Z[y==c]; m=Zc.mean(0); D=Zc-m; Sw+=D.T@D; d=(m-mu)[:,None]; Sb+=len(Zc)*(d@d.T)
    Sw/=len(Z); Sw+=reg*np.trace(Sw)/Sw.shape[0]*np.eye(Sw.shape[0])
    ev,V=np.linalg.eigh(np.linalg.solve(Sw,Sb)) if False else np.linalg.eig(np.linalg.solve(Sw,Sb))
    o=np.argsort(-ev.real); k=k or (len(cl)-1); W=V[:,o[:k]].real
    return mu,W
def evaluate(name,Ztr,ytr,k=None,reg=1e-2):
    mu,W=lda(Ztr,ytr,k,reg)
    P=np.array([unit(((Ztr[ytr==c]-mu)@W)).mean(0) for c in groups]); P=unit(P)
    pred=np.array(groups)[(unit((TV-mu)@W)@P.T).argmax(1)]
    print("%-46s %.1f %%"%(name,100*np.mean(pred[tests]==lab[tests])))
def base(name,Ztr,ytr):
    mu=Ztr.mean(0); P=unit(np.array([unit(Ztr[ytr==c]-mu).mean(0) for c in groups]))
    pred=np.array(groups)[(unit(TV-mu)@P.T).argmax(1)]
    print("%-46s %.1f %%"%(name,100*np.mean(pred[tests]==lab[tests])))
base("centrage (apprentissage = fenêtres entières)",Wn,Wl)
Z2=np.concatenate([Wn,TR]); y2=np.concatenate([Wl,trl])
base("centrage (+ segments courts répétés)",Z2,y2)
for reg in (1e-3,1e-2,1e-1):
    evaluate("LDA fenêtres entières reg=%g"%reg,Wn,Wl,None,reg)
    evaluate("LDA +segments courts reg=%g"%reg,Z2,y2,None,reg)
    evaluate("LDA +segments courts, 12 axes reg=%g"%reg,Z2,y2,12,reg)
