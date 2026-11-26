import json,sys,numpy as np
w=sys.argv[1]
E=json.load(open(w+"/emb.json")); T=json.load(open(w+"/truth.json"))
X=np.array([r["v"] for r in E["windows"]],dtype=np.float32); t=np.array([r["t"] for r in E["windows"]]); X/= (np.linalg.norm(X,axis=1,keepdims=True)+1e-9)
G=100; N=int(T["duration"]*G)+1
spk=np.zeros((8,N),bool)
for u in T["utterances"]: spk[u["speaker"]][int(u["start"]*G):int(u["end"]*G)]=True
cnt=spk.sum(0)
lab=[]
win=E["window"]
for ti in t:
    a,b=int(ti*G),int((ti+win)*G)
    sl=cnt[a:b]; 
    frac=[(spk[k][a:b]&(sl==1)).mean() for k in range(8)]
    k=int(np.argmax(frac)); ov=(sl>=2).mean(); sil=(sl==0).mean()
    lab.append(k if frac[k]>0.8 else (-2 if ov>0.2 else -1))   # -2 : chevauchement, -1 : mixte/silence
lab=np.array(lab)
print("fenêtres : %d, par locuteur : %s, chevauchement : %d, autres : %d"%(len(t),[int((lab==k).sum()) for k in range(4)],int((lab==-2).sum()),int((lab==-1).sum())))
S=X@X.T
for a in range(4):
    row=[]
    for b in range(4):
        ia,ib=np.where(lab==a)[0],np.where(lab==b)[0]
        if len(ia)==0 or len(ib)==0: row.append("  n/a"); continue
        m=S[np.ix_(ia,ib)]; 
        if a==b: m=m[~np.eye(len(ia),dtype=bool)]
        row.append("%5.2f"%m.mean())
    print("locuteur %d :"%a," ".join(row))
ov=np.where(lab==-2)[0]
print("fenêtres en chevauchement : similarité max à chaque locuteur (moyenne) :",[round(float(np.mean([S[i][lab==k].mean() for i in ov])),2) if len(ov) and (lab==k).any() else None for k in range(4)])
