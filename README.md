# Portable Waterfox Updater

**Waterfox portatile, sempre aggiornata.** Un updater *portable* per [Waterfox](https://www.waterfox.net/) (Windows 64 bit) scritto in PowerShell, con interfaccia WinForms. Scarica le build portable di [Portapps](https://portapps.io) da [portapps/waterfox-portable](https://github.com/portapps/waterfox-portable/releases) e le installa/aggiorna in una cartella.

Deriva dall'architettura di *Portable Opera Updater* (PowerShell).

## Cosa fa

- Legge l'ultima release dall'**API di GitHub** (tag `<versione Waterfox>-<build Portapps>`, es. `6.7.6-34`) e sceglie l'archivio `waterfox-portable-win64-<tag>.7z` (non l'installer `*-setup.exe`). Se l'API non risponde (es. rate limit) ripiega sulle pagine web della release.
- Verifica **dimensione e SHA256** (campo `digest` dell'API, altrimenti `checksums.txt`) e non lascia mai file da 0 byte.
- **Aggiorna senza toccare i tuoi dati**: sostituisce solo `app\` e `waterfox-portable.exe` (più `portapp.json`, `CHANGELOG.md`, `README.md`); `data\` (profilo) e il file `.yml` di configurazione restano intatti. Se la sostituzione fallisce, ripristina la versione precedente.
- Se **Waterfox è in esecuzione** (da quella cartella) blocca l'aggiornamento e chiede di chiuderlo.
- Gestisce la pagina di avviso di **Zscaler** (HTTP 403): apre il link nel browser, clicchi *Continua*, poi *Riprova*.
- **Autoaggiornamento** dello script da questo repo (controllo SHA256 e sintassi, backup `.bak`).
- Modalità console: `Waterfox-Updater.cmd -UpdateAll` aggiorna Waterfox se è già installata.

## Requisiti

- Windows 10/11 a 64 bit con PowerShell 5.1 (o 7). Non servono diritti di amministratore.
- **7-Zip**: se `7zr.exe`, `7z.exe` o `7za.exe` è nel `PATH` viene usato; altrimenti lo script scarica `7zr.exe` da [ip7z/7zip](https://github.com/ip7z/7zip/releases/download/26.05/7zr.exe) nella cartella temporanea `Update\`, lo usa e lo cancella a fine operazione. Non esiste più la cartella `Bin\`.

## Installazione e uso

1. Scarica `Waterfox-Updater.ps1` e `Waterfox-Updater.cmd` in una cartella a tua scelta.
2. Doppio clic su `Waterfox-Updater.cmd` (apre la GUI). Da console: `Waterfox-Updater.cmd -UpdateAll`.

Il pulsante **Installa / Aggiorna**: verde = aggiornato, rosso = aggiornamento disponibile. Opzioni: *Ignora controllo versione* (reinstalla comunque) e *Crea collegamento sul desktop*.

Parametri dello script: `-UpdateAll`, `-NoSelfUpdate`, `-InstallDir <cartella>` (default: `Waterfox` accanto allo script; puoi indicare una cartella Waterfox portable già esistente: la versione viene letta da `portapp.json`).

## Struttura su disco

```
<cartella>\
  Waterfox-Updater.ps1 / .cmd
  WaterfoxUpdater.log        log di tutto quello che succede
  Waterfox\
    waterfox-portable.exe    launcher Portapps (non compilato da questo script)
    app\                     Waterfox
    data\                    il tuo profilo (mai toccato)
    waterfox-portable.yml    la tua configurazione (mai toccata)
    portapp.json, README.md, CHANGELOG.md
    updates\Version.log      versione installata, es. 6.7.6-34|win64
```

## Zscaler / proxy aziendali

Se il download risponde 403, il programma apre il link nel browser. Clicca *Continua* nella pagina di avviso, annulla il download che parte nel browser e premi *Riprova* nella finestra del programma. Vale anche per `7zr.exe`.

## Autoaggiornamento e rilasci

`Waterfox-Updater.version` contiene `<versione>|<SHA256>` ed è generato dalla GitHub Action
[`release-meta`](.github/workflows/release-meta.yml): ad ogni push di `Waterfox-Updater.ps1` riscrive anche
l'URL `$SelfUpdateBase` con quello di questo repo. **Per rilasciare** basta alzare `$ScriptVersion` nello script e fare push su `main`.

Il repo deve essere **pubblico** perché lo script legga i file da `raw.githubusercontent.com`.
Per disattivare il controllo: `-NoSelfUpdate`.

## Note

- Il file `.ps1` va salvato **UTF-8 con BOM** e senza conversioni di fine riga (vedi `.gitattributes`): il suo SHA256 è pubblicato in `.version`.
- L'API di GitHub senza autenticazione ha un limite di 60 richieste/ora per IP: in caso di superamento lo script usa le pagine web.

## Crediti e licenza

Le build portable sono di [Portapps](https://portapps.io) (CrazyMax), Waterfox è un marchio dei rispettivi proprietari; questo progetto non è affiliato a nessuno dei due. Licenza [MIT](LICENSE).
