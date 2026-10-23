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

## Build 41 — 0.2.0 beta

- Suite XCTest finale: **33 test passati**, nessun errore o test saltato. I nuovi casi verificano registrazione/disattivazione del login, richieste duplicate, approvazione pendente, errori e variazioni esterne del servizio, senza modificare gli elementi di login reali durante i test.
- Sulla copia Apple Development firmata: il selettore Avvia NimBar al login ha registrato e poi annullato la registrazione nel servizio reale macOS; stato finale ripristinato su disattivato come all’inizio. Non è stato eseguito un logout o riavvio del Mac.
- CUA: apertura del benvenuto da Privacy, verifica visiva dell’eliminazione del bordo bianco dopo il passaggio a pannello trasparente figlio, cambio Italiano → English → Italiano e chiusura con Continua; le impostazioni tornano interattive.
- La preferenza di nascondimento dell’icona è indipendente dalla sezione Nascoste, riutilizza la preferenza già salvata e impedisce ai recuperi ritardati di renderla nuovamente visibile. Riaprire l’app accede alle impostazioni.
- Build Release completata e pacchetti aggiornati. Firma rigorosa verificata sia nell’app del DMG montato sia nella copia estratta dallo ZIP; eseguibile identico, build 41 e collegamento Applications a /Applications. Checksum SHA-256 validi.

## Build 42 — 0.2.1 beta

- Ridisegnata la finestra Impostazioni con uno sfondo blur adattivo a chiaro/scuro/sistema, sidebar integrata e icone di sezione aggiornate.
- Compattata la pagina Generali in schede senza scorrimento; timer e istruzioni del separatore ora seguono le rispettive impostazioni.
- Ridisegnate Layout, Privacy, Aggiornamento e Info; aggiunta la scheda Crediti con autore, licenza GPL e collegamento al repository.
- Il clic destro fa una scansione fresca del display attivo e considera spazio vuoto l’impronta delle icone effettivamente nascoste.
- Compilazioni Debug e Release completate. Creato e verificato `build/packages/NimBar-0.2.1-beta.dmg`: bundle 0.2.1/build 42, layout Finder e collegamento `Applications` → `/Applications` controllati; checksum SHA-256 salvato accanto al DMG. I test XCTest e la verifica visiva interattiva non sono stati eseguiti per questa modifica.
- Firma corretta recuperata senza importare o revocare certificati: `security find-identity` nel sandbox restituiva zero identità; con accesso al Portachiavi ne risultano tre. Il certificato originale previsto dal packaging è presente e la relativa chiave privata firma correttamente. La mancanza di accesso al Portachiavi era stata interpretata erroneamente come assenza del certificato.
- `sh Scripts/package.sh --check-signing` fallisce nel sandbox con una diagnosi specifica e passa con accesso al Portachiavi, dopo aver firmato e verificato un eseguibile temporaneo. Nessun fallback ad hoc o selezione automatica di un altro account.
- Packaging completo eseguito con certificato SHA-1 `6A1A131688AC29BD01914E366951696097276710`, Team ID `L4R3ATNCT8`, valido fino al 10 settembre 2027. Firma rigorosa verificata sull’app, sul DMG firmato, sull’app estratta dal DMG e dallo ZIP; certificato incorporato confrontato con l’impronta prevista. Il designated requirement coincide con quello di `/Applications/NimBar.app`.
- `NimBar.dmg`, `NimBar.zip`, `NimBar-0.2.1-beta.dmg` e relativi checksum aggiornati. Il precedente DMG ad hoc 0.2.1 è stato sostituito con quello firmato Apple Development. Questa firma non equivale a Developer ID o notarizzazione.

## Build 43 — 0.2.2 beta

- Il menu contestuale su clic destro viene mostrato solo negli spazi vuoti verificati o sull’impronta di un’icona gestita nascosta. Il controllo Accessibility nativo distingue gli elementi menu sotto il puntatore; se non riesce a identificarli, NimBar non intercetta il clic.
- Il clic destro sull’icona NimBar continua a mostrare il menu normale. Il clic sinistro negli spazi vuoti mantiene il percorso di recupero delle icone.
- Build Release completata e pacchetti generati da `Scripts/package.sh`. Firma Apple Development verificata sull’app e sul DMG; l’identità è `Apple Development: emanuele.giuliana612@live.it (C58GK962H9)`, Team ID `L4R3ATNCT8`.
- `hdiutil verify` conferma l’integrità del DMG. SHA-256 di `build/packages/NimBar.dmg`: `9e8809ccbfb2e681f8c2df2bb35e50dae3a3dd263391d412a381c834650e1fad`.
- I test XCTest non sono stati eseguiti.

## Build 44 — 0.2.1 beta (versione richiesta per questo pacchetto)

- L’icona selezionata nel riquadro “Icona barra menu” è contenuta in un frame fisso 16 × 16 pt, come le altre opzioni, evitando che l’asset originale mantenga la sua dimensione intrinseca.
- Release build completata e pacchetti firmati verificati tramite `Scripts/package.sh`; il DMG contiene NimBar 0.2.1/build 44.

## Build 45 — 0.2.1 beta

- Riprodotto il problema in un menu SwiftUI nativo isolato: Chevron 77 × 14 pt, originale 312 × 158 pt. I modificatori della vista non limitavano l’immagine estratta dal menu nativo.
- La correzione ridimensiona una copia NSImage a un bordo massimo di 16 pt, conservando la rappresentazione ad alta risoluzione e senza modificare l’asset condiviso.
- `python3 Scripts/check-icon-selector.py` usa direttamente il renderer di SettingsView nel menu nativo: Originale, Chevron, Chevron giù e Punto sono tutti alti 14 pt. Prima della correzione la prova segnalava il selettore originale troppo grande.
- Compilazione Release e packaging completati; firme dell’app e del DMG e contenuto di DMG/ZIP verificati da `Scripts/package.sh` con il certificato Apple Development originale. Versione bundle 0.2.1, build 45.

## Build 46 — 0.2.1 beta

- Migliorato il contrasto chiaro con un velo bianco traslucido sul blur nativo, testo principale scuro, descrizioni più marcate, messaggi verde/arancio più scuri e contorni delle schede più visibili. La selezione nella sidebar usa un blu più scuro. Benvenuto e Crediti condividono lo sfondo adattivo.
- Anteprime dei componenti reali renderizzate con NSHostingView in chiaro, scuro e nuovamente chiaro; le due immagini chiare sono identiche. Verifica del contrasto sRGB sullo sfondo minimo previsto dal velo bianco: testo principale 9,29:1, secondario 5,23:1, successo 4,95:1, avviso 4,65:1. Sono verifiche dei componenti e della palette, non una prova interattiva dell’intera app su ogni sfondo.
- Il controllo regressione del selettore icone passa: tutte le scelte mantengono 14 pt di altezza.
- Build Release completata, firma Apple Development originale e contenuto di DMG/ZIP verificati da `Scripts/package.sh`; bundle 0.2.1, build 46. Checksum SHA-256 dei pacchetti validi.
- Una prova della pulizia con file temporanei verifica che soltanto i vecchi archivi NimBar versionati e i loro checksum siano rimossi. La cartella finale contiene un solo DMG, un solo ZIP e `SHA256SUMS.txt`; i metadati Finder sono preservati.


## 0.3.0.1 alpha — build 47 (2026-10-17)

- Debug build and the SettingsStoreTests suite passed: 39 cases. The host exits initialization before creating real status items or applying visibility.
- Added gesture tests cover persisted opt-in settings, complementary directions, accumulated horizontal threshold, one action per phased stroke, momentum rejection, natural-scrolling inversion, vertical rejection, off-bar origins, display locking and wheel idle rearming.
- An in-memory URLProtocol feed verifies alpha/beta/stable filtering and rejects malformed or mismatched tag/channel combinations, without reaching GitHub. Version tests verify alpha revision/channel precedence. Bundle metadata test confirms an explicit supported release channel.
- An isolated native SwiftUI preview extracted the actual General panel and helpers, with temporary preferences and a fake login service. English and Italian, light and dark variants each measured 746 × 517 pt, within the existing settings page. Reviewed the rendered Italian light and English dark images; no scrolling or truncated swipe selectors. This is a component preview, not a physical input test.
- Release packaging passed the original-certificate/private-key preflight, app and DMG strict signature checks, DMG integrity, and extracted DMG/ZIP content checks. ZIP Info.plist confirms public version 0.3.0.1, channel alpha, build 47. Final SHA-256 checksums match; local output has one DMG and one ZIP.
- Physical swipe delivery/direction over real hidden menu-bar areas on trackpad, Magic Mouse and other horizontal-scroll devices remains a manual hardware check. No real menu-bar manipulation was performed by the tests. No alpha GitHub release was published.


### Rollback backup preparation (2026-10-17)

Saved and verified the current 0.3.0.1 alpha build 47 DMG, ZIP, checksum file and source snapshot before animation work. The backup helper passed isolated fixtures for first-run/no previous package, repeat/idempotent reuse, corrupted-backup refusal, incomplete-current-package refusal and preservation of the originals. The packaging shell syntax check passed. No animation code or application binary was changed during this grilling round. Full integration of the backup calls will run when the next confirmed application build is packaged.

## 0.3.0.2 alpha — build 48 (2026-10-17)

- Debug build passed. All 43 SettingsStoreTests passed, including the existing protected-input, divider, cross-display and swipe regressions.
- New isolated fixtures verify reversible neighbour movement and ordering, source/system/foreign-display exclusion, bounds clamping, 2x background slot clearing with untouched outside pixels, rejection of unsafe capture edges, shared spring timing and original glyph size, and source visibility only at handoff.
- The tests instantiate synthetic AppKit views/layers and image fixtures, without changing the real menu bar, installing input monitors or registering login items. Physical spring smoothness, early modifier-to-drag timing and the handoff on one/two displays still require acceptance on user hardware.
- The user confirmed the previous swipe feature works perfectly. Its behaviour and input path are preserved.

Release packaging passed the original-certificate/private-key preflight, strict app/DMG signatures, DMG integrity, extracted DMG/ZIP content verification, version/channel metadata and SHA-256 checks. Immutable backups for both build 47 and build 48 were verified; the current packages folder contains one DMG and one ZIP. Backup source snapshots represent packaging time; this final validation note was added afterwards.

## 0.3.0 beta — build 49 (2026-10-23)

- All 43 SettingsStoreTests passed, including swipe handling, beta/alpha release ordering, protected drag, native-order reflow, system/display exclusion, and synthetic layer animation fixtures.
- Release packages report version 0.3.0, channel beta, build 49. The original Apple Development identity and strict package checks passed; SHA-256 values are listed in `build/packages/SHA256SUMS.txt`.
- The previous alpha and the new beta installers/source snapshots are preserved in `build/backups`. The published application is signed but not notarized and does not use a Developer ID distribution certificate.
- The user reports no bugs in this version. The coordinated live animation is now ready for beta release; the automated fixtures do not simulate physical dragging on the live menu bar.
