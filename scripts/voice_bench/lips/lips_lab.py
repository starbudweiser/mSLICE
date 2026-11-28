import json, numpy as np
D=json.load(open("lips.json")); fr=D["frames"]; fps=D["fps"]
x=np.fromfile("clean.f32",dtype=np.float32)
# VAD énergétique sur la piste nettoyée (trames de 1/fps)
hop=int(16000/fps); n=len(x)//hop
rms=np.sqrt((x[:n*hop].reshape(n,hop)**2).mean(1)); 
thr=max(np.percentile(rms,20)*3,1e-3)
vad=rms>thr
print("trames",len(fr),"VAD parole %.0f %%"%(100*vad.mean()), "seuil",thr)
# suivi par IoU
def iou(a,b):
    ax,ay,aw,ah=a; bx,by,bw,bh=b
    ix=max(0,min(ax+aw,bx+bw)-max(ax,bx)); iy=max(0,min(ay+ah,by+bh)-max(ay,by)); i=ix*iy
    return i/(aw*ah+bw*bh-i+1e-9)
tracks=[]  # liste de dict: idx list
active=[]
for fi,f in enumerate(fr):
    used=set(); new=[]
    for k,face in enumerate(f["f"]):
        best=-1;bi=0.0
        for ti in active:
            tr=tracks[ti]
            if tr["last"]<fi-2 or ti in used: continue
            v=iou(tr["box"],face["b"])
            if v>bi: bi=v;best=ti
        if best>=0 and bi>0.4:
            used.add(best); tr=tracks[best]; tr["pts"].append((fi,k)); tr["last"]=fi; tr["box"]=face["b"]; new.append(best)
        else:
            tracks.append({"pts":[(fi,k)],"last":fi,"box":face["b"]}); new.append(len(tracks)-1); used.add(len(tracks)-1)
    active=[t for t in set(active+new) if tracks[t]["last"]>=fi-2]
print("pistes",len(tracks),"longues (≥2 s):",sum(len(t["pts"])>=fps*2 for t in tracks))
# activité des lèvres par piste
def feat(tr):
    pts=tr["pts"]; fi=np.array([p[0] for p in pts]); 
    inH=np.array([fr[a]["f"][b]["m"][0] for a,b in pts]); outH=np.array([fr[a]["f"][b]["m"][2] for a,b in pts])
    G=[np.array(fr[a]["f"][b]["g"],dtype=np.float32) for a,b in pts]
    ok=[len(g)==128 for g in G]
    dg=np.zeros(len(pts))
    for i in range(1,len(pts)):
        if ok[i] and ok[i-1] and fi[i]-fi[i-1]<=2:
            a=G[i];b=G[i-1]; dg[i]=np.abs((a-a.mean())-(b-b.mean())).mean()
    dinH=np.zeros(len(pts)); dinH[1:]=np.abs(np.diff(inH))
    return fi,inH,outH,dg,dinH
def smooth(v,w):
    k=np.ones(w)/w; return np.convolve(v,k,mode="same")
res={"inH":[], "dg":[], "dinH":[], "vad":[], "std":[]}
for tr in tracks:
    if len(tr["pts"])<int(fps*1.0): continue
    fi,inH,outH,dg,dinH=feat(tr)
    w=int(fps*0.6)|1
    s_inH=np.sqrt(np.maximum(smooth(inH**2,w)-smooth(inH,w)**2,0))
    for name,v in (("inH",smooth(inH,w)),("dg",smooth(dg,w)),("dinH",smooth(dinH,w)),("std",s_inH)):
        res[name].append(v)
    res["vad"].append(vad[np.minimum(fi,n-1)])
def auc(score,lab):
    s=np.concatenate(score); l=np.concatenate(lab)
    o=np.argsort(s); r=np.empty(len(s)); r[o]=np.arange(len(s))
    P=l.sum(); N=len(l)-P
    return (r[l==1].sum()-P*(P-1)/2)/(P*N)
for name in ("inH","dg","dinH","std"):
    print("AUC activité lèvres (%s) vs parole : %.3f"%(name,auc(res[name],res["vad"])))
np.save("tracks_n.npy",len(tracks))
