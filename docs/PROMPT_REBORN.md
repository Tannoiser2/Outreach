# Outreach Reborn: le immagini da far generare a ChatGPT

Questo documento va dato a ChatGPT così com'è. Contiene lo stile comune e un prompt per ogni immagine,
con il **nome esatto del file** da restituire. Le immagini finite vanno messe in
`Desktop/Ludoteca/Outreach/Reborn/` (anche in uno ZIP): le copio io in `assets/reborn/` del gioco.
Ogni immagine che manca viene sostituita dall'originale SPI, quindi si possono fare anche poche alla volta.

## Il gioco, in breve (da leggere prima)

*Outreach* (SPI, 1976) è un gioco di conquista della Galassia nell'anno 3000: civiltà telestetiche che
«saltano» istantaneamente fra le stelle con flotte stellari (**StarFleet**) e costruiscono insediamenti
permanenti chiamati **StarGate** (porte stellari). Nella Galassia ci sono anche **forze autonome**, civiltà
non controllate dai giocatori, e al centro del Nucleo galattico i misteriosi **gettoni della saggezza**.
L'ambientazione è la stessa di *StarForce*: fantascienza «hard» anni Settanta, niente laser e
battaglie spettacolari, ma navi-città, telepati e insediamenti che durano generazioni.

## Stile comune per TUTTE le immagini

- Fantascienza illustrata degli anni Settanta rivisitata con qualità moderna (pensare alle copertine di
  Chris Foss e John Berkey, alle tavole di Syd Mead), ma pulita e leggibile come una pedina di un gioco
  da tavolo moderno (Kickstarter / Gamefound).
- Pedine **viste dall'alto**, perfettamente **quadrate**, **512 x 512 pixel**, **PNG**, con bordo netto e
  angoli leggermente arrotondati (raggio 24 px). Niente sfondo trasparente fuori dal quadrato: il
  quadrato è pieno fino ai bordi.
- Il soggetto al centro deve essere riconoscibile anche rimpicciolito a 40 x 40 pixel: forme forti,
  contrasto alto, pochi dettagli fini.
- **Nessun testo**, nessuna lettera, nessun numero, nessuna firma, nessun logo, salvo dove il prompt
  chiede esplicitamente una lettera o un numero (e in quel caso solo quella, grande e in stampatello).
- Palette di base: spazio blu-nero profondo, stelle bianche, nebulose sobrie. Il colore del giocatore
  deve dominare il bordo e il simbolo.
- Colori dei giocatori: **blu** #6BAEE0, **giallo** #F5C628, **verde** #8CA842, **rosso** #E0332E.
- Colori delle forze autonome (più cupi, con fondo grigio-nero): **grigio** #9E9E99, **blu** #4D8CBF,
  **verde** #738C40, **giallo** #D9B333.

## 1. Flotte dei giocatori (4 immagini)

Una flotta stellare: uno stormo di 3-5 grandi astronavi-città affusolate, viste dall'alto in formazione
a cuneo, con scie luminose del colore del giocatore. Fondo: spazio scuro con un leggero bagliore del
colore del giocatore. Bordo del quadrato spesso 20 px nel colore del giocatore.

- `blu_flotta.png` — colore blu #6BAEE0
- `giallo_flotta.png` — colore giallo #F5C628
- `verde_flotta.png` — colore verde #8CA842
- `rosso_flotta.png` — colore rosso #E0332E

Prompt: *«Square 512x512 board game counter, top-down view of a fleet of 4 sleek elongated city-sized
starships in wedge formation with glowing [COLORE] engine trails, deep space background with faint stars,
thick [COLORE] border, 1970s science fiction illustration style redone with modern clean rendering, bold
readable shapes, no text, no letters, no numbers.»*

## 2. Segnalino di contatto (retro della flotta, 4 immagini)

Il retro della pedina della flotta, che si gira per segnare il **contatto**: lo stesso bordo colorato,
fondo pieno del colore del giocatore, al centro una grande lettera **C** bianca con un alone, e attorno
due archi concentrici come onde radio / onde telepatiche che si incontrano.

- `blu_contatto.png`, `giallo_contatto.png`, `verde_contatto.png`, `rosso_contatto.png`

Prompt: *«Square 512x512 board game counter, solid [COLORE] background, large bold white capital letter
C in the center with a soft glow, two concentric telepathic wave arcs meeting around it, clean flat
modern style, no other text.»*

## 3. Porte stellari dei giocatori (4 immagini)

Una **StarGate**: un grande anello o una stazione circolare vista dall'alto, con una città luminosa al
centro e moli radiali, come un insediamento permanente nello spazio. Anello e luci nel colore del
giocatore. Fondo spazio scuro.

- `blu_porta.png`, `giallo_porta.png`, `verde_porta.png`, `rosso_porta.png`

Prompt: *«Square 512x512 board game counter, top-down view of a huge circular space station shaped like
a ring with radial docking arms and a glowing city at its hub, [COLORE] lights and [COLORE] thick border,
dark starry background, 1970s sci-fi art redone in a clean modern style, no text.»*

## 4. Forze autonome (4 colori x 7 immagini)

Le civiltà autonome sono **aliene** e diverse dai giocatori: astronavi organiche o cristalline, forme
asimmetriche, colori cupi. Fondo grigio-nero, bordo del colore della forza.

Per ogni colore (`grigio`, `blu`, `verde`, `giallo`):

- `aut_[colore]_flotta.png` — fronte della flotta (tipo nascosto): una sola nave aliena organica vista
  dall'alto.
- `aut_[colore]_flotta_SF.png` — retro, flotta regolare: la stessa nave con sotto, grande, la sigla
  **SF**.
- `aut_[colore]_flotta_D.png` — retro, corazzata: una nave aliena più massiccia e armata con la lettera
  **D**.
- `aut_[colore]_porta.png` — fronte della porta autonoma: un insediamento alieno (un fiore cristallino
  o un alveare che orbita una stella), senza numeri.
- `aut_[colore]_porta_1.png`, `aut_[colore]_porta_3.png`, `aut_[colore]_porta_4.png` — retro della porta
  autonoma con il suo valore: lo stesso insediamento più sbiadito, con al centro il numero **1**, **3**
  o **4** grande e leggibile.

Esempio di nome: `aut_verde_porta_3.png`.

Prompt: *«Square 512x512 board game counter, top-down view of a single organic crystalline alien
starship, asymmetric and strange, muted [COLORE] glow, dark grey-black background, thick [COLORE] border,
eerie 1970s science fiction mood with modern clean rendering, no text.»* (per i retri aggiungere: *«with
a large bold [SF / D / numero] in the center»*).

## 5. Altri segnalini

- `faro.png` — **stella faro**: una supergigante luminosissima, bianca-azzurra con raggi a croce e
  alone, su fondo spazio. Deve sembrare un faro per la navigazione.
- `saggezza.png` — **gettone della saggezza**, fronte: fondo nero lucido, al centro una grande **W**
  dorata incisa, con sotto il simbolo dell'infinito, alone dorato tenue. Antico, misterioso.
- `saggezza_retro.png` — retro comune: fondo nero lucido con una trama di circuiti dorati, senza
  lettere.
- `saggezza_x.png` — retro speciale: come il precedente ma con una grande **X** rossa incandescente
  (rappresenta la scoperta che il Nucleo è esploso).
- `pv.png` — retro del **gettone del potenziale** (valore nascosto): grigio metallico con un pianeta
  stilizzato e un punto interrogativo grande al centro.

## 6. Plancia dell'interazione

- `plancia.png` — **600 x 780 pixel**, verticale. È la plancia che ogni giocatore usa per le relazioni
  con gli altri. Va mantenuta **esattamente questa struttura** (il gioco ci appoggia sopra i segnalini
  in punti fissi):
  - in alto a sinistra il titolo «[8.3] MATRICE DELL'INTERAZIONE»;
  - tre riquadri chiari in alto, da x = 15 a 190, da 205 a 380, da 397 a 572, e da y = 48 a 190, con i
    testi «NOI - Opzione A - Cooperativa», «NOI - Opzione B - Neutrale», «NOI - Opzione C - Ostile»;
  - tre grandi frecce doppie verticali fra y = 195 e y = 330;
  - sotto, una griglia 3 x 3 di riquadri (stesse colonne; righe da y = 335, 477, 619, alte 141 px).
    Riga A: «LORO Opzione A» con «Alleanza reciproca, nessun attacco» / «Alleanza a senso unico, nessun
    attacco» / «Noi abbiamo il bonus d'attacco». Riga B: «Alleanza a senso unico, nessun attacco» /
    «Nessun effetto speciale» / «Noi abbiamo il bonus d'attacco». Riga C: «Loro hanno il bonus
    d'attacco» / «Loro hanno il bonus d'attacco» / «Conflitto obbligatorio, perdite raddoppiate».
  - Stile: pannello di plancia di un gioco moderno, metallo scuro e vetro, testo chiaro molto
    leggibile; i riquadri «LORO» un po' più scuri di quelli «NOI»; la colonna C con un accento rosso, la
    A con un accento verde.
  - **Testi in italiano, esattamente come scritti qui**, senza errori: è l'unica immagine con del testo.

## 7. Immagini facoltative

- `sfondo_menu.jpg` — **1920 x 1080**, sfondo del menu: la Via Lattea vista di tre quarti, con il
  Nucleo arancione e i bracci azzurri, una grande StarGate ad anello in primo piano a sinistra e uno
  stormo di astronavi che salta verso il centro. Lasciare la metà destra più scura e pulita (ci va il
  pannello del menu). Nessun testo.
- `copertina.webp` — **540 x 720**, copertina «Reborn» per la ludoteca: la stessa scena in verticale,
  con in alto lo spazio per il titolo OUTREACH (che aggiungo io), nessun testo.

## Riepilogo dei file

| File | Quantità | Misura |
|---|---|---|
| `[colore]_flotta.png` | 4 | 512 x 512 |
| `[colore]_contatto.png` | 4 | 512 x 512 |
| `[colore]_porta.png` | 4 | 512 x 512 |
| `aut_[colore]_flotta.png`, `_SF`, `_D` | 12 | 512 x 512 |
| `aut_[colore]_porta.png`, `_1`, `_3`, `_4` | 16 | 512 x 512 |
| `faro.png`, `saggezza.png`, `saggezza_retro.png`, `saggezza_x.png`, `pv.png` | 5 | 512 x 512 |
| `plancia.png` | 1 | 600 x 780 |
| `sfondo_menu.jpg`, `copertina.webp` | 2 (facoltative) | 1920 x 1080, 540 x 720 |

Colori dei giocatori: `blu`, `giallo`, `verde`, `rosso`. Colori delle forze autonome: `grigio`, `blu`,
`verde`, `giallo`.
