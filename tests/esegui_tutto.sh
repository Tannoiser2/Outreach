#!/bin/bash
# Tutte le prove, in ordine. Usato dal workflow "Verifica" (serve ./godot nella cartella del progetto).
G=./godot
echo "== importazione"
timeout 300 $G --headless --path . --import 2>&1 | grep -E "ERROR|SCRIPT ERROR|Parse Error" | head -40
echo "== controllo degli script"
timeout 120 $G --headless --path . -s tests/compila.gd 2>&1 | grep -v "^Godot Engine" | head -60
echo "== partite automatiche"
timeout 1200 $G --headless --path . -s tests/autoplay.gd 2>&1 | grep -v "^Godot Engine" | tail -60
echo "== eventi in una partita a quattro (scenario 4, 40 turni)"
DUMP=1 MAXT=40 timeout 300 $G --headless --path . -s tests/autoplay.gd -- 4 3 originali 2>&1 > /tmp/dump.txt
for k in "CONTATTO" "attacca" "neutralizzata" "DISPERSIONE" "dispersione di" "Fato di" "forza autonoma" "sceglie C" "sceglie A" "stelle faro" "gettone saggezza" "livello di civiltà" "è eliminato" "Ordine"; do echo "$k: $(grep -c "$k" /tmp/dump.txt)"; done
grep "SCN" /tmp/dump.txt
grep -E "attacca|neutralizzata|CONTATTO" /tmp/dump.txt | head -12
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
