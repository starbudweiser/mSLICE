import numpy as np, json, sys
import onnxruntime as ort
from scipy.io import wavfile
R=16000
def mel(f): return 1127*np.log(1+f/700)
def filters():
    nfft=512; low,high=mel(20),mel(8000); d=(high-low)/81
    m=np.zeros((80,257)); freqs=np.arange(257)*R/nfft; mk=mel(freqs)
    for b in range(80):
        l=low+b*d; c=low+(b+1)*d; r=low+(b+2)*d
        up=(mk-l)/(c-l); dn=(r-mk)/(r-c); m[b]=np.maximum(0,np.minimum(up,dn))
    return m
FB=filters(); WIN=np.power(0.5-0.5*np.cos(2*np.pi*np.arange(400)/399),0.85)
def fbank(x):
    x=x*32768.0
    n=1+(len(x)-400)//160
    if n<20: x=np.pad(x,(0,400+160*19-len(x)),mode="wrap"); n=1+(len(x)-400)//160
    idx=np.arange(400)[None,:]+160*np.arange(n)[:,None]; f=x[idx]
    f=f-f.mean(1,keepdims=True)
    pre=np.empty_like(f); pre[:,1:]=f[:,1:]-0.97*f[:,:-1]; pre[:,0]=f[:,0]-0.97*f[:,0]
    f=pre*WIN[None,:]
    P=np.abs(np.fft.rfft(f,512,axis=1))**2
    o=np.log(np.maximum(P@FB.T,np.finfo(np.float32).eps))
    return (o-o.mean(0,keepdims=True)).astype(np.float32)
def run_sess(path):
    s=ort.InferenceSession(path,providers=["CPUExecutionProvider"]); return s,s.get_inputs()[0].name
def emb(sess,name,x):
    f=fbank(x)[None]; return sess.run(None,{name:f})[0][0]
def segs(wavpath,rngs):
    sr,y=wavfile.read(wavpath); y=y.astype(np.float32)/32768; return [y[int(a*R):int(b*R)] for a,b in rngs]
def unit(v): return v/(np.linalg.norm(v,axis=-1,keepdims=True)+1e-9)
if __name__=="__main__":
    path=sys.argv[1]; sess,name=run_sess(path)
    te=json.load(open("splice_ranges.json")); lab=np.array(json.load(open("splice_lab.json")))
    tr=json.load(open("train_ranges.json")); trl=np.array(json.load(open("train_lab.json")))
    TE=np.array([emb(sess,name,s) for s in segs("splice.wav",te)]); TR=np.array([emb(sess,name,s) for s in segs("train.wav",tr)])
    np.save("onnx_te_%s.npy"%sys.argv[2],TE); np.save("onnx_tr_%s.npy"%sys.argv[2],TR)
    groups=sorted(set(trl.tolist())); G=np.array(groups); tests=np.array([i for i in range(len(lab)) if lab[i] in groups])
    for center in (False,True):
        mu=TR.mean(0) if center else 0
        P=unit(np.array([unit(TR[trl==c]-mu).mean(0) for c in groups]))
        pred=G[(unit(TE-mu)@P.T).argmax(1)]
        print("%-8s %s  précision %.1f %%  (dim %d)"%(sys.argv[2],"centré" if center else "brut  ",100*np.mean(pred[tests]==lab[tests]),TE.shape[1]))
        for lo,hi in ((0.7,1.0),(1.0,1.3),(1.3,1.7)):
            sel=[i for i in tests if lo<=te[i][1]-te[i][0]<hi]
            if sel and center: print("    %.1f–%.1f s : %.0f %% (%d)"%(lo,hi,100*np.mean(pred[sel]==lab[sel]),len(sel)))
