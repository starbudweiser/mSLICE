# DINOv2-S sur des recadrages plus serrés : visage aligné agrandi (align224) et centre du recadrage large (tight224).
import os, json, time, warnings
warnings.filterwarnings('ignore')
import numpy as np
from PIL import Image
import coremltools as ct
ids = sorted(f[:-4] for f in os.listdir('data/full/align112'))
m = ct.models.MLModel('models/coreml/dinov2.mlpackage', compute_units=ct.ComputeUnit.CPU_AND_NE)
def get(kind, i):
    if kind == 'align224': return Image.open(f'data/full/align112/{i}.jpg').convert('RGB').resize((224, 224), Image.BICUBIC)
    im = Image.open(f'data/full/face224/{i}.jpg').convert('RGB'); return im.crop((37, 37, 187, 187)).resize((224, 224), Image.BICUBIC)   # boîte du visage = 150/224
for kind in ('align224', 'tight224'):
    C, A = [], []
    for i in ids:
        r = m.predict({'image': get(kind, i)}); C.append(np.asarray(r['cls']).reshape(-1)); A.append(np.asarray(r['avg']).reshape(-1))
    np.save(f'feats/dinov2_{kind}_cls.npy', np.stack(C)); np.save(f'feats/dinov2_{kind}_avg.npy', np.stack(A)); json.dump(ids, open(f'feats/{kind}_ids.json', 'w'))
    print(kind, 'ok')
