# Croisement image / voix : essais du 28/11/2026

`LipAnalyzer.swift.txt` : passe de décodage à 12,5 images/s, visages et lèvres (Vision), vignette 16×8 de la zone des lèvres (retiré de l'appli, à remettre dans `Sources/Analysis/` pour refaire les mesures).
`lips_lab.py`, `avsync2.py` : mouvement des lèvres contre la parole, puis corrélation voix × visage avec test de permutation.

Résultats sur « La Révolte II » (720×406, visages de 20 % de la hauteur) : le mouvement des lèvres ne prédit pas la parole (AUC 0,47 à 0,56) ; la synchronie
voix × visage cumulée est réelle (z jusqu'à 6) mais plusieurs visages d'un même plan ressortent pour une même voix : pas assez sûre pour lier ou fusionner seule.
À retenter sur des plans plus serrés ou en plus haute définition.
