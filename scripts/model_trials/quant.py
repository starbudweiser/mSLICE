# Compression des poids d'AuraFace (palettisation k-means, sans données) + empreintes de tous les visages pour mesurer la perte.
import sys, os, json, time, warnings
warnings.filterwarnings('ignore')
import numpy as np
from PIL import Image
import coremltools as ct
import coremltools.optimize.coreml as cto
src = sys.argv[1]; tag = sys.argv[2]; nbits = int(sys.argv[3])
ids = sorted(f[:-4] for f in os.listdir('data/full/align112'))
m = ct.models.MLModel(f'models/coreml/{src}.mlpackage')
cfg = cto.OptimizationConfig(global_config=cto.OpPalettizerConfig(mode='kmeans', nbits=nbits))
t0 = time.time(); q = cto.palettize_weights(m, cfg); out = f'models/coreml/{tag}.mlpackage'; q.save(out)
sz = sum(os.path.getsize(os.path.join(d, f)) for d, _, fs in os.walk(out) for f in fs)
print(tag, 'palettisation', round(time.time() - t0), 's, taille', round(sz / 1e6, 1), 'Mo')
q = ct.models.MLModel(out, compute_units=ct.ComputeUnit.CPU_AND_NE)
E = []; t0 = time.time()
for i in ids: E.append(np.asarray(q.predict({'image': Image.open(f'data/full/align112/{i}.jpg').convert('RGB')})['emb']).reshape(-1))
print(tag, 'ms/image', round((time.time() - t0) / len(ids) * 1000, 2))
np.save(f'feats/{tag}_align112_emb.npy', np.stack(E).astype(np.float32))
