# Testing

## Beta 0.2.0 — build 36, 16 ottobre 2026

- XCTest: **20 test passati**. I casi nuovi coprono sorgente e display congelati, generazioni obsolete, candidati memorizzati di un altro monitor, hit ambigui, modalità aggiornamenti persistente, assenza della fonte senza risultati inventati, cadenza giornaliera e installazione automatica rimandata fino all’inattività. Il servizio degli aggiornamenti è simulato solo nei test e non esegue rete o installazioni.
- I test usano snapshot sintetici; il test host non avvia l’app né modifica la barra reale. Risultato: `/private/tmp/NimBarTests/Logs/Test/Test-NimBar-2026.10.16_13-03-50-+0200.xcresult`.
- Build Release firmata Apple Development riuscita. Firme rigorose delle copie in DMG, ZIP e Applicazioni verificate con accesso al Portachiavi. Eseguibili identici e checksum SHA-256 dei pacchetti verificati.
- Controllo UI sulla copia installata: sezione Aggiornamento sopra Esci; opzioni Manuale, Cerca automaticamente e Scarica e installa automaticamente; verifica manuale segnala la fonte GitHub mancante senza dichiarare l’app aggiornata.
- La cattura effettiva del Cmd-drag da parte dei pannelli AppKit e il mantenimento dell’ordine nativo su due monitor richiedono ancora una prova fisica con i tasti reali. I test non dimostrano la consegna degli eventi da parte di WindowServer in ogni configurazione.
- Versione rimasta 0.2.0 beta su richiesta dell’utente; build interna 36. La precedente app è conservata temporaneamente in `/private/tmp/NimBar-before-build36-2b1b8b0733.app`.

## Beta 0.2.0 — build 35, 16 ottobre 2026

- Build Release macOS 27 arm64 completata con successo dopo aver separato la scansione del display principale dalla scansione live del display attivo.
- Firma Apple Development della stessa identità verificata con accesso completo al Portachiavi; DMG e ZIP generati e checksum SHA-256 verificati.
- Verifica a runtime su barra reale e monitor multipli ancora da eseguire: il marker overlay e il limite prima delle icone di sistema richiedono una conferma interattiva dell’utente.
- Nessuna suite di test è stata eseguita per questa modifica.
- Versione inclusa 0.2.0; build interna 35.

## Beta 0.2.0 — build 34, 16 ottobre 2026

- Build Release arm64 riuscita con la stessa identità Apple Development; script di packaging completato per DMG e ZIP.
- La zona vuota è calcolata dalla geometria `NSScreen.frame`/`visibleFrame`, e lo schermo viene selezionato e aggiornato prima di valutare i click su display diversi.
- Il click originale resta nel normale percorso di macOS; il reveal si attiva soltanto se il punto non appartiene a un’icona visibile, all’icona NimBar o alle voci del menu dell’app in primo piano.
- Non è disponibile una prova fisica su MacBook Air M1 senza notch: la compatibilità su quel modello resta da confermare dall’utente dopo l’installazione.
- Versione inclusa 0.2.0, build 34; firma Apple Development verificata su disco e sulla copia in Applicazioni. DMG e ZIP generati; checksum SHA-256 verificati.
- La copia aggiornata `/Applications/NimBar.app` è stata avviata. Il selettore mostra l’etichetta fuori dal menu e ogni voce con simbolo e nome.

## Beta 0.1.22.11 — build 33, 16 ottobre 2026

- Build Release macOS 27 riuscita, con firma Apple Development della stessa identità già autorizzata.
- Verifica interattiva del Layout: simboli originali e orologio reale, senza wallpaper nei ritagli, app e voci di sistema leggibili.
- L’utente ha confermato che durante ⌘ + ⌥ le immagini rimangono intere; ha segnalato una qualità insufficiente nella prima build di prova. La misura successiva ha rilevato bitmap 1× provenienti dal monitor esterno.
- Correzione successiva: cattura `best` almeno 2× e preferenza per la replica Retina dello stesso proprietario. Misura finale: ad esempio Amphetamine 31 × 33 punti → 62 × 66 pixel; Wi-Fi 22 × 33 punti → 44 × 66 pixel; la cache finale delle icone presenti risulta 2×. Coordinate e assegnazioni del drag restano sullo schermo scelto.
- DMG controllato in Finder: finestra 582 × 300, icone da 100, freccia centrale, collegamento Applications → /Applications. Nessuna modifica a FinderInfo del bundle firmato.
- Firma rigorosa verificata sulle app dentro DMG e ZIP e sulla copia in Applicazioni; eseguibili identici e checksum SHA-256 verificati.
- XCTest non rieseguito per questa modifica; i 14 test riportati sotto riguardano la beta precedente. La valutazione visiva finale della nitidezza da parte dell’utente resta da confermare dopo l’ultima correzione 2×.

## Risultati verificati — 16 ottobre 2026

Versione: **0.1.21.11 beta**, build 32, macOS 27 su Mac arm64.

- XCTest: **14 test passati**. Coprono impostazioni e persistenza, distinzione Nascoste/Sempre nascoste, normalizzazione delle immagini, risoluzione dell’aspetto, identificazione del proprietario dopo un drag, confine corrente, hit test, sorgenti ambigue, drop fuori barra e separazione degli schermi.
- I test unitari usano snapshot sintetici e non modificano la barra reale.
- Verifica interattiva: superficie principale chiara bianca, testi leggibili e ritorno da modalità Chiara a Sistema con ripristino dell’aspetto scuro del Mac.
- La copia firmata in `/Applications/NimBar.app` riconosce Accessibilità e Registrazione schermo autorizzate.
- Prova fisica confermata dall’utente: tenendo premuti ⌘ + ⌥, il separatore compare e il trascinamento cambia la visibilità. Prova eseguita sulla barra del monitor esterno con due schermi collegati.
- Build Release firmata Apple Development, Team ID `L4R3ATNCT8`. Verifica rigorosa della firma sulla copia installata e sulle app estratte da DMG e ZIP.
- DMG con collegamento ad Applicazioni; checksum SHA-256 di DMG e ZIP verificati.
- Diagnostica temporanea dei modificatori rimossa dalla build definitiva.

## Limiti della verifica

Non sono stati verificati tutti gli assetti multischermo, riavvio, sleep/wake, consumo energetico o versioni macOS precedenti. La firma Development verificata non equivale alla notarizzazione per la distribuzione pubblica.


## Build 37 — 0.2.0 beta

- Eseguiti 27 test XCTest: tutti passati. Host test privo di status item o applicazione di visibilità reale.
- Nuove regressioni: filtro mouse per soli bersagli gestiti e shortcut scelto, prosecuzione del filtro fino al rilascio fuori display e dopo il rilascio dei modificatori, normale riordino Cmd fuori modalità lasciato passare, attraversamento immediato reversibile senza campioni duplicati, recupero della sola icona NimBar nascosta.
- Lingue: default English, conferma esplicita della lingua iniziale, persistenza, callback immediata, ricalcolo dei messaggi già creati, parità delle 140 chiavi e dei segnaposto tra English e Italiano, errori del bridge tradotti.
- La prova XCTest copre logica e geometria sintetica; non dimostra il comportamento del driver eventi o l’ordine reale su due monitor. Serve ancora una prova con tasti e mouse fisici su entrambi i display per confermare il riordino eliminato in quella configurazione.

- Controllo UI della copia firmata `/Applications/NimBar.app`: benvenuto iniziale English con Accessibilità/Registrazione schermo già riconosciute; passaggio Italiano e ritorno English senza riavvio, inclusi messaggio di scansione, titoli, sidebar, selettore icone e sezione Aggiornamento. Nessun avviso di filtro indisponibile su questo Mac.
- Packaging: verificata firma Apple Development con Team `L4R3ATNCT8` tramite `codesign --verify --deep --strict` su app installata, copia estratta dallo ZIP e copia montata dal DMG. Tutte riportano `0.2.0` build `37`, stesso hash dell’eseguibile, entrambe le risorse lingua. Checksum dei pacchetti validi; collegamento DMG `Applications` diretto a `/Applications`.
- Copia precedente conservata in `/private/tmp/NimBar-before-build37-5ee8d1bef9.app`.


## Build 38 — 0.2.0 beta

- Aggiunto test di regressione sullo spostamento del confine di una larghezza icona, sul nuovo hit boundary, sull’inversione e sul limite prima della zona di sistema.
- Verificare con ⌘⌥ e mouse fisici: una icona visibile trascinata a sinistra fa scorrere la linea a destra; la stessa riportata a destra fa scorrere la linea a sinistra. Ripetere partendo da un’icona nascosta e su ciascun monitor. Il resto del drag e l’ordine restano invariati.
- Suite finale eseguita dopo l’ultima modifica: 28 test XCTest superati.
- CUA: la copia firmata build 38 si apre in Applicazioni; la lingua già salvata e le sezioni Generali/Info restano operative. Prova visiva disponibile del nuovo tratto durante un drag fisico non eseguita, quindi il movimento e l’inversione sui monitor devono ancora essere confermati dall’utente.
- App installata, app nel DMG e app nello ZIP verificati con firma rigorosa, versione 0.2.0 build 38 e Team ID Apple Development `L4R3ATNCT8`; hash eseguibile identico e localizzazioni presenti in entrambi i pacchetti. Checksum validi e collegamento `Applications` nel DMG verificato.
