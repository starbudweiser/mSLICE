import json,sys,numpy as np
from scipy.cluster.hierarchy import linkage
w=sys.argv[1]; TAU=float(sys.argv[2]) if len(sys.argv)>2 else None
E=json.load(open(w+"/emb.json")); T=json.load(open(w+"/truth.json"))
X=np.array([r["v"] for r in E["windows"]],dtype=np.float32); t=np.array([r["t"] for r in E["windows"]]); X/= (np.linalg.norm(X,axis=1,keepdims=True)+1e-9)
WIN,HOP=E["window"],E["hop"]; D=T["duration"]; G=100; N=int(D*G)+1
spk=np.zeros((8,N),bool)
for u in T["utterances"]: spk[u["speaker"]][int(u["start"]*G):int(u["end"]*G)]=True
cnt=spk.sum(0); solo=[spk[k]&(cnt==1) for k in range(8)]; ov=cnt>=2; sil=cnt==0
def cluster(X,tau):
    # liaison moyenne sur la distance 1-cos ; coupe à 1-tau
    Z=linkage(X,method="average",metric="cosine")
    from scipy.cluster.hierarchy import fcluster
    return fcluster(Z,1-tau,criterion="distance"),Z
def auto_tau(Z):
    sims=1-Z[:,2]            # similarités de fusion décroissantes dans l'ordre des fusions
    s=np.sort(sims)[::-1]
    # plus grand écart entre deux fusions successives dans [0.25,0.7]
    best=(0,0.45)
    for a,b in zip(s[:-1],s[1:]):
        if 0.25<=b and a<=0.75 and a-b>best[0]: best=(a-b,(a+b)/2)
    return best[1]
def metrics(m,name):
    best=max(range(8),key=lambda k:(m&solo[k]).sum()); mt=max(m.sum(),1)
    return best,(m&solo[best]).sum()/max(solo[best].sum(),1),sum((m&solo[k]).sum() for k in range(8) if k!=best)/mt,(m&ov).sum()/mt,(m&sil).sum()/mt,mt/G
def run(tau,assign_min,margin):
    lab,Z=cluster(X,tau)
    # centroïdes
    ks=sorted(set(lab)); C=np.array([X[lab==k].mean(0) for k in ks]); C/=np.linalg.norm(C,axis=1,keepdims=True)
    S=X@C.T
    # clusters retenus : au moins 4 s de parole
    keep=[i for i,k in enumerate(ks) if (lab==k).sum()*HOP>=4]
    rows=[]
    for ci in keep:
        mask=np.zeros(N,bool)
        for i in range(len(t)):
            if lab[i]!=ks[ci]: continue
            o=np.sort(S[i][keep])[::-1]
            if S[i][ci]<assign_min: continue
            if len(o)>1 and S[i][ci]-np.sort(S[i][[c for c in keep if c!=ci]])[-1]<margin: continue
            c=t[i]+WIN/2; mask[int(max(c-HOP/2,0)*G):int(min(c+HOP/2,D)*G)]=True
        rows.append(metrics(mask,"c%d"%ci))
    return len(keep),rows
for tau in ([TAU] if TAU else [0.30,0.45,"auto"]):
    if tau=="auto":
        _,Z=cluster(X,0.3); tau=auto_tau(Z)
    for am,mg in ((0,0),(0.45,0.1),(0.55,0.15)):
        nk,rows=run(tau,am,mg)
        wsum=sum(r[5] for r in rows)
        avg=[sum(r[i]*r[5] for r in rows)/max(wsum,1e-9) for i in (1,2,3,4)]
        print("τ=%.2f assign≥%.2f marge≥%.2f : %d voix | rappel %3.0f %% intrus %3.0f %% chevauch. %3.0f %% silence %3.0f %%"%(tau,am,mg,nk,100*avg[0],100*avg[1],100*avg[2],100*avg[3]))
