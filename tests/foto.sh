#!/bin/bash
# Fotografie dello schermo per la verifica (in risultati/).
mkdir -p risultati
f() { timeout 120 xvfb-run -a -s "-screen 0 1920x1080x24" ./godot --rendering-driver opengl3 --path . -s tests/foto.gd -- "$@" 2>&1 | grep -E "SALVATO|ERROR|error" | head -8; }
f risultati/01_menu.png menu
f risultati/02_scorpii_2d.png 1 originale 2d 6 mossa
f risultati/03_cygnus_3d.png 4 originale 3d 8
f risultati/04_nucleo_reborn_3d.png 2 reborn 3d 8 ia
f risultati/05_seme_reborn_2d.png 5 reborn 2d 8 ia
f risultati/06_tabelle.png 3 originale 2d 3 tabelle
f risultati/07_plancia.png 4 originale 2d 15 plancia
f risultati/08_regole.png regole
f risultati/09_3d_senza_mappa.png 4 originale 3d 8 senzamappa
f risultati/10_3d_vicino.png 4 originale 3d 8 vicino
f risultati/11_fili_3d.png 4 reborn 3d 4 fili
for p in risultati/*.png; do convert "$p" -resize 1280x -quality 80 "${p%.png}.jpg" 2>/dev/null && rm "$p"; done
ls -la risultati
