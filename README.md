# Outreach, versione digitale

Versione digitale di **Outreach: The Conquest of the Galaxy, 3000 AD** (SPI, 1976, Irad B. Hardy),
il capostipide dei giochi 4X di esplorazione, colonizzazione e conflitto galattico.

Si gioca nel browser: https://tannoiser2.github.io/Outreach/ (e sulla ludoteca privata).

## Cosa c'è

- **I cinque scenari** del regolamento: Conflitto per Scorpii (2), La via per il Nucleo (3), Il Grande
  Salto della PSL (solitario), Lotta per Cygnus-Carina (4), La fortuna del sorteggio (da 1 a 4, con i
  Venti Seme).
- **Tutto il turno**: ordine di spostamento, salti regolari, continui e di riserva con dispersione,
  esplorazione con i gettoni del potenziale, contatto, interazione (A/B/C) con la plancia, conflitto con
  capacità dichiarate, riduzione, Fato con dissoluzioni, forze autonome e saggezza, risorse
  (porte, aumenti, riattivazioni, flotte, manutenzione), stelle faro scoperte, polvere interstellare,
  Nucleo e gettoni saggezza (con la X diversa per scenario).
- **Tabelle originali e rivedute**: dispersione SkyGazer, tabelle versione 3 (dispersione, conflitto,
  conversione), Fato riveduto, conversione riveduta, e il **Sistema del Fato alternativo** dei Gilham
  (Phoenix n. 11) con i punti civiltà.
- **Mappa 2D** con la mappa SPI originale (letta per terreni, stelle faro e polvere) e le pedine del
  modulo TTS; **mappa 3D** con la griglia di esagoni e sopra la galassia come una nuvola trasparente a
  più strati. Grafica **originale** o **Reborn** (immagini nuove in `assets/reborn/`, vedi
  `docs/PROMPT_REBORN.md`).
- **IA** per i posti vuoti, gioco a turno sullo stesso dispositivo con le informazioni segrete
  nascoste, **online** con Firebase (stanze con codice), **salvataggi** su Firebase con un codice di sei
  lettere, **replay** finale senza segreti.
- Regolamento, tabelle e plancia **in italiano** dentro il gioco (`assets/regole.md`).

## Struttura

- `assets/mappa.json`: terreno di ogni esagono, stelle faro, lati di polvere (dalla mappa originale).
- `scripts/data/od_data.gd`: geometria degli esagoni, tabelle, gettoni, scenari.
- `scripts/core/engine.gd`: le regole; `scripts/core/ai.gd`: l'avversario automatico.
- `scripts/ui/`: menu, schermata di gioco, mappa 2D (`board2d.gd`) e 3D (`board3d.gd`), tabelle, regole.
- `scripts/net/`: Firebase (radice `outreach` del database condiviso: stanze e partite salvate).

## Prove

Il workflow **Verifica** gira a ogni modifica e scrive i risultati (partite IA in tutti gli scenari e
varianti, salvataggio e ricarica, fotografie dello schermo, controllo dei caratteri, esportazione web)
nel ramo `verifica-risultati`. A mano:

```
godot --headless --path . -s tests/autoplay.gd -- 4 1 v3
godot --headless --path . -s tests/salva_carica.gd
xvfb-run godot --path . -s tests/foto.gd -- /tmp/foto.png 4 originale 3d 8
python3 tools/controlla_glifi.py
```

## Pubblicazione

Solo a richiesta: Actions, *Pubblica*, *Run workflow*, oppure un commit su main con `[pubblica]` nel
messaggio. Pubblica su GitHub Pages e, con i segreti Cloudflare, sulla ludoteca privata.
