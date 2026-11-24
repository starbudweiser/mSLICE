#!/usr/bin/env python3
"""mSLICE — conversion du modèle d'identité des personnages (AuraFace, Apache 2.0) en Core ML, prêt à héberger.

Entrée : glintr100.onnx de https://huggingface.co/fal/AuraFace-v1 (260 694 151 octets, SHA-256 attendu ci-dessous).
Sortie : AuraFace-CoreML-8bit.zip (AuraFace.mlpackage + LICENSE.txt + NOTICE.txt) et son SHA-256 (à copier dans `ModelCatalog.characters`).

Chaîne : ONNX → PyTorch (onnx2torch) → Core ML mlprogram fp16 (macOS 14) → palettisation 8 bits par k-moyennes (65 Mo, aucune perte mesurée).
Entrée du modèle : image RVB 112 × 112 du visage ALIGNÉ sur le gabarit ArcFace (voir scripts/model_trials/extract.swift), brute 0..255
(la normalisation (x − 127,5) / 127,5 est dans le modèle). Sortie : « emb », 512 flottants, à normaliser en L2 ; similarité = produit scalaire.

Dépendances (essai du 24/11/2026) : torch, coremltools, onnx, onnx2torch, numpy — dans un environnement à part, jamais dans le dépôt.
Usage : python3 scripts/convert_character_model.py <glintr100.onnx> <dossier-de-sortie>
"""
import hashlib, os, shutil, subprocess, sys, warnings
warnings.filterwarnings('ignore')

ONNX_SHA256 = 'a7933ea5330113b01c9b60351d8f4c33003f145d8470ac5f0e52ee2effe25c60'
NOTICE = """AuraFace (glintr100.onnx), https://huggingface.co/fal/AuraFace-v1 — Apache License 2.0 (texte dans LICENSE.txt).
Modèle de reconnaissance de visages ArcFace ResNet-100, entraîné par fal.ai sur des données à usage commercial (selon sa fiche).

Modifications apportées par mSLICE (art. 4.b de la licence) : conversion du fichier ONNX en Core ML (flottants 16 bits), normalisation des pixels
((x - 127,5) / 127,5) intégrée au modèle, puis compression des poids par palettisation 8 bits (k-moyennes). Aucun réentraînement.
Usage dans mSLICE : regrouper les apparitions d'un même visage dans une vidéo, sur le Mac de l'utilisateur ; rien n'est envoyé hors du Mac.
"""

def sha256(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for b in iter(lambda: f.read(1 << 20), b''): h.update(b)
    return h.hexdigest()

def main(onnx_path, out_dir):
    import numpy as np, onnx, onnx2torch, torch, coremltools as ct
    import coremltools.optimize.coreml as cto
    torch.set_grad_enabled(False)
    got = sha256(onnx_path)
    if got != ONNX_SHA256: sys.exit(f'Empreinte inattendue pour {onnx_path} : {got}')
    os.makedirs(out_dir, exist_ok=True)
    net = onnx2torch.convert(onnx.load(onnx_path)).eval()
    traced = torch.jit.trace(net, torch.rand(1, 3, 112, 112), strict=False)
    m = ct.convert(traced, inputs=[ct.ImageType(name='image', shape=(1, 3, 112, 112), color_layout=ct.colorlayout.RGB, scale=1 / 127.5, bias=[-1, -1, -1])],
                   outputs=[ct.TensorType(name='emb')], convert_to='mlprogram', compute_precision=ct.precision.FLOAT16, minimum_deployment_target=ct.target.macOS14)
    m = cto.palettize_weights(m, cto.OptimizationConfig(global_config=cto.OpPalettizerConfig(mode='kmeans', nbits=8)))
    m.author = 'AuraFace (fal.ai), converti pour mSLICE'
    m.license = 'Apache License 2.0'
    m.short_description = 'Empreinte de visage (512 valeurs, à normaliser en L2) pour un visage RVB 112x112 aligné sur le gabarit ArcFace.'
    m.user_defined_metadata['source'] = 'https://huggingface.co/fal/AuraFace-v1 (glintr100.onnx, sha256 ' + ONNX_SHA256 + ')'
    work = os.path.join(out_dir, 'AuraFace-CoreML-8bit'); shutil.rmtree(work, ignore_errors=True); os.makedirs(work)
    m.save(os.path.join(work, 'AuraFace.mlpackage'))
    open(os.path.join(work, 'NOTICE.txt'), 'w', encoding='utf-8').write(NOTICE)
    lic = os.path.join(os.path.dirname(onnx_path), 'LICENSE.md')
    if os.path.exists(lic):
        t = open(lic, encoding='utf-8').read()
        if t.startswith('---'): t = t.split('---', 2)[2].lstrip('\n')                 # retire l'en-tête YAML de choosealicense.com
        open(os.path.join(work, 'LICENSE.txt'), 'w', encoding='utf-8').write(t)
    zip_path = os.path.join(out_dir, 'AuraFace-CoreML-8bit.zip')
    if os.path.exists(zip_path): os.remove(zip_path)
    subprocess.run(['/usr/bin/ditto', '-c', '-k', '--norsrc', '--noextattr', work, zip_path], check=True)
    print('fichier :', zip_path, os.path.getsize(zip_path), 'octets')
    print('sha256  :', sha256(zip_path))

if __name__ == '__main__':
    if len(sys.argv) != 3: sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
