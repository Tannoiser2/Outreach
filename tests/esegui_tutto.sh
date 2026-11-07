#!/bin/bash
# Tutte le prove, in ordine. Usato dal workflow "Verifica" (serve ./godot nella cartella del progetto).
G=./godot
echo "== importazione"
timeout 300 $G --headless --path . --import 2>&1 | grep -E "ERROR|SCRIPT ERROR|Parse Error" | head -40
echo "== controllo degli script"
timeout 120 $G --headless --path . -s tests/compila.gd 2>&1 | grep -v "^Godot Engine" | head -60
echo "== partite automatiche"
timeout 1200 $G --headless --path . -s tests/autoplay.gd 2>&1 | grep -v "^Godot Engine" | tail -60
if [ -f tests/salva_carica.gd ]; then
  echo "== salvataggio e ricarica"
  timeout 300 $G --headless --path . -s tests/salva_carica.gd 2>&1 | grep -v "^Godot Engine" | tail -20
fi
if [ -f tests/online_prova.gd ]; then
  echo "== online simulato"
  timeout 300 $G --headless --path . -s tests/online_prova.gd 2>&1 | grep -v "^Godot Engine" | tail -20
fi
if [ -f tests/foto.sh ]; then
  echo "== fotografie"
  bash tests/foto.sh 2>&1 | tail -40
fi
if [ -f tools/controlla_glifi.py ]; then
  echo "== glifi"
  python3 tools/controlla_glifi.py
fi
echo "== fine"
