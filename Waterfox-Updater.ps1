#Requires -Version 5.1
<#
.SYNOPSIS
  Portable Waterfox Updater - GUI WinForms (PowerShell 5.1 / 7).
.DESCRIPTION
  Scarica e aggiorna Waterfox portable (win64) dalle release di https://github.com/portapps/waterfox-portable/releases.
  Versione e asset vengono letti dall'API di GitHub (con digest SHA256); si usa l'archivio .7z (non l'installer *-setup.exe).
  L'archivio e' un portable Portapps gia' pronto (waterfox-portable.exe, app\, portapp.json): l'aggiornamento
  SOSTITUISCE app\ e l'exe e NON tocca data\ (profilo) ne' il file di configurazione .yml dell'utente.
  Per estrarre usa 7-Zip dal PATH; se non c'e', scarica 7zr.exe nella cartella temporanea Update\.
  Gestisce la pagina di avviso Zscaler (HTTP 403): apre il link nel browser, tu clicchi "Continua", poi si riprova.
  Autoaggiornamento da GitHub (se $SelfUpdateBase e' impostato): confronta Waterfox-Updater.version e verifica SHA256.
  Log: WaterfoxUpdater.log accanto allo script. Versione installata: <cartella>\updates\Version.log
.PARAMETER UpdateAll
  Modalita' console: aggiorna Waterfox se e' gia' installato ed esce.
.PARAMETER NoSelfUpdate
  Salta il controllo di aggiornamento dello script.
.PARAMETER InstallDir
  Cartella di installazione di Waterfox portable (default: <cartella dello script>\Waterfox).
#>
[CmdletBinding()]
param([switch]$UpdateAll, [switch]$NoSelfUpdate, [string]$InstallDir)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
try {
    [Net.WebRequest]::DefaultWebProxy = [Net.WebRequest]::GetSystemWebProxy()
    [Net.WebRequest]::DefaultWebProxy.Credentials = [Net.CredentialCache]::DefaultCredentials
} catch {}
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

function Pth { [IO.Path]::Combine([string[]]$args) }

$Root     = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$WorkDir  = Pth $Root 'Update'
$LogFile  = Pth $Root 'WaterfoxUpdater.log'
$InstDir  = if ($InstallDir) { [IO.Path]::GetFullPath($InstallDir) } else { Pth $Root 'Waterfox' }
$BrowserUA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36'
$ApiUA     = 'Portable-Waterfox-Updater'

$Repo        = 'portapps/waterfox-portable'
$ApiLatest   = "https://api.github.com/repos/$Repo/releases/latest"
$AtomUrl     = "https://github.com/$Repo/releases.atom"
$AssetsPage  = "https://github.com/$Repo/releases/expanded_assets/{0}"
$DownloadFmt = "https://github.com/$Repo/releases/download/{0}/{1}"
# Archivio estraibile con 7zr: waterfox-portable-win64-<versione>-<build>.7z (NON il *-setup.exe, che e' Inno Setup)
$AssetPattern = '^waterfox-portable-win64-.+\.7z$'
$SevenZipUrl  = 'https://github.com/ip7z/7zip/releases/download/26.05/7zr.exe'

$ScriptVersion   = '1.0.0'
# Cartella "raw" su GitHub con Waterfox-Updater.ps1 e Waterfox-Updater.version.
# Nel repo viene riscritta in automatico dalla GitHub Action (.github/workflows/release-meta.yml).
# Vuoto o con "YOUR_USER" = autoaggiornamento disattivato.
$SelfUpdateBase  = 'https://raw.githubusercontent.com/cmldo/portable-waterfox-updater/main'

# --- Testi -------------------------------------------------------------------------------------
$lang = [Globalization.CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName
if ($lang -eq 'it') {
    $T = @{
        Title='Portable Waterfox Updater'; RemoteVer='Versione remota'; LocalVer='Versione installata'
        NotInstalled='non installato'; Install='Installa'; Update='Aggiorna'; Exit='Esci'
        IgnoreVer='Ignora controllo versione'; Shortcut='Crea collegamento sul desktop'; Ready='Pronto'
        Checking='Controllo versione...'; Download='Download {0}'
        Unpack='Estrazione in corso...'; Installing='Installazione...'; Done='Completato: {0}'
        UpToDate='Waterfox e'' gia'' aggiornato.'
        Running='Waterfox e'' in esecuzione: chiudilo (anche dalla barra di sistema) e premi Riprova.'
        PressRetry='Premi Invio per riprovare (q per annullare)'
        ZBlock = "Il download di {0} e' stato bloccato (403), probabilmente dalla pagina di avviso di Zscaler.`n`nHo aperto il link nel browser: clicca 'Continua' (poi puoi annullare il download del browser) e premi Riprova."
        ErrTitle='Errore'; NoRemote="Nessuna versione remota disponibile.`nControlla connessione/proxy (vedi log)."
        Aborted='Operazione annullata.'; Need64='Questo programma richiede Windows a 64 bit.'
        NotInstalledMsg='Waterfox non e'' installato: usa la finestra grafica per la prima installazione.'
        SelfUpd='Nuova versione dello script disponibile: {0} (attuale {1}).`nAggiornare ora?'
    }
} else {
    $T = @{
        Title='Portable Waterfox Updater'; RemoteVer='Remote version'; LocalVer='Installed version'
        NotInstalled='not installed'; Install='Install'; Update='Update'; Exit='Exit'
        IgnoreVer='Ignore version check'; Shortcut='Create desktop shortcut'; Ready='Ready'
        Checking='Checking version...'; Download='Downloading {0}'
        Unpack='Unpacking...'; Installing='Installing...'; Done='Done: {0}'
        UpToDate='Waterfox is already up to date.'
        Running='Waterfox is running: close it (also from the system tray) and press Retry.'
        PressRetry='Press Enter to retry (q to cancel)'
        ZBlock = "The download of {0} was blocked (403), most likely by the Zscaler warning page.`n`nI opened the link in your browser: click 'Continue' (you can then cancel the browser download) and press Retry."
        ErrTitle='Error'; NoRemote="No remote version available.`nCheck connection/proxy (see log)."
        Aborted='Operation cancelled.'; Need64='This program requires 64-bit Windows.'
        NotInstalledMsg='Waterfox is not installed: use the GUI for the first installation.'
        SelfUpd='A new script version is available: {0} (current {1}).`nUpdate now?'
    }
}

# --- Stato condiviso ---------------------------------------------------------------------------
$script:Console = [bool]$UpdateAll
$script:Busy    = $false
$script:Abort   = $false
$script:Remote  = $null
$script:Opt     = @{ IgnoreVer = $false; Shortcut = $false }
$script:DlTitle = ''
$script:LastStatus = ''

function Write-Log([string]$m) {
    try { Add-Content -LiteralPath $LogFile -Value ('{0:yyyy-MM-dd HH:mm:ss} {1}' -f (Get-Date), $m) -Encoding UTF8 } catch {}
}
function Pump { if (-not $script:Console) { [System.Windows.Forms.Application]::DoEvents() } }

function Set-Status([string]$text, [int]$pct = 0, [string]$right = '') {
    if ($script:Console) {
        if ($text -ne $script:LastStatus) { Write-Host $text; $script:LastStatus = $text }
        if ($pct -gt 0) { Write-Progress -Activity $T.Title -Status "$text $right" -PercentComplete $pct } else { Write-Progress -Activity $T.Title -Completed }
        return
    }
    $script:lblStatus.Text = $text
    $script:lblRight.Text  = $right
    $script:bar.Value      = [Math]::Max(0, [Math]::Min(100, $pct))
    Pump
}

function Show-Error([string]$msg) {
    Write-Log "ERRORE: $msg"
    if ($script:Console) { Write-Host "ERRORE: $msg" -ForegroundColor Red; return }
    [void][System.Windows.Forms.MessageBox]::Show("$msg`n`nLog: $LogFile", $T.ErrTitle, 'OK', 'Error')
}

function ConvertTo-Text($c) { if ($c -is [byte[]]) { [Text.Encoding]::UTF8.GetString($c) } else { [string]$c } }

# --- Stato locale ------------------------------------------------------------------------------
function Test-Installed { Test-Path -LiteralPath (Pth $InstDir 'waterfox-portable.exe') }

# Versione installata "<versione>-<build>": prima updates\Version.log, poi portapp.json (installazioni gia' esistenti)
function Get-LocalVersion {
    $log = Pth $InstDir 'updates' 'Version.log'
    if (Test-Path -LiteralPath $log) {
        $v = ((Get-Content -LiteralPath $log -Raw).Trim().Split('|'))[0].Trim()
        if ($v) { return $v }
    }
    $pj = Pth $InstDir 'portapp.json'
    if (Test-Path -LiteralPath $pj) {
        try {
            $j = Get-Content -LiteralPath $pj -Raw | ConvertFrom-Json
            if ($j.version -and $j.release) { return ('{0}-{1}' -f $j.version, $j.release) }
        } catch {}
    }
    $null
}

function ConvertTo-Ver([string]$s) {
    $m = [regex]::Match($s, '^v?(\d+(?:\.\d+){0,3})-(\d+)$')
    if (-not $m.Success) { return $null }
    try { [version]('{0}.{1}' -f $m.Groups[1].Value, $m.Groups[2].Value) } catch { $null }
}

function Test-Outdated {
    $r = $script:Remote
    if (-not $r -or -not (Test-Installed)) { return $false }
    $l = Get-LocalVersion
    if (-not $l) { return $true }
    $a = ConvertTo-Ver $r.Version; $b = ConvertTo-Ver $l
    if ($a -and $b) { return ($a -gt $b) }
    return ($r.Version -ne $l)
}

# --- Versione remota (API GitHub, con ripiego sulle pagine web) ---------------------------------
function Get-ChecksumFromFile([string]$Url, [string]$Name) {
    $r = Invoke-WebRequest -UseBasicParsing -Uri $Url -UserAgent $ApiUA -TimeoutSec 30
    foreach ($line in ((ConvertTo-Text $r.Content) -split "`r?`n")) {
        $m = [regex]::Match($line.Trim(), '^([0-9a-fA-F]{64})\s+\*?(.+)$')
        if ($m.Success -and $m.Groups[2].Value.Trim() -eq $Name) { return $m.Groups[1].Value.ToUpper() }
    }
    ''
}

function Get-RemoteApi {
    $r = Invoke-WebRequest -UseBasicParsing -Uri $ApiLatest -UserAgent $ApiUA -Headers @{ Accept = 'application/vnd.github+json' } -TimeoutSec 30
    $j = (ConvertTo-Text $r.Content).TrimStart([char]0xFEFF) | ConvertFrom-Json
    if (-not $j.tag_name) { throw 'Risposta API inattesa (tag_name mancante).' }
    $assets = @($j.assets)
    $a = $assets | Where-Object { $_.name -match $AssetPattern } | Select-Object -First 1
    if (-not $a) { throw ("Nessun archivio .7z win64 nella release {0}. Asset: {1}" -f $j.tag_name, (($assets | ForEach-Object { $_.name }) -join ', ')) }
    $sha = ''
    if ([string]$a.digest -match '^sha256:([0-9a-fA-F]{64})$') { $sha = $Matches[1].ToUpper() }
    else {
        $c = $assets | Where-Object { $_.name -like '*checksum*' -or $_.name -like '*sha256*' } | Select-Object -First 1
        if ($c) { try { $sha = Get-ChecksumFromFile ([string]$c.browser_download_url) ([string]$a.name) } catch { Write-Log "Checksum non letto: $($_.Exception.Message)" } }
    }
    [pscustomobject]@{ Version = [string]$j.tag_name; Name = [string]$a.name; Url = [string]$a.browser_download_url; Size = [long]$a.size; Sha256 = $sha; Source = 'api' }
}

# Ripiego (es. rate limit dell'API, 60 richieste/ora per IP): feed atom delle release + pagina degli asset
function Get-RemoteWeb {
    $atom = ConvertTo-Text (Invoke-WebRequest -UseBasicParsing -Uri $AtomUrl -UserAgent $BrowserUA -TimeoutSec 30).Content
    $m = [regex]::Match($atom, 'releases/tag/([^"<&\s]+)')
    if (-not $m.Success) { throw 'Nessuna release nel feed.' }
    $tag = $m.Groups[1].Value
    $html = ConvertTo-Text (Invoke-WebRequest -UseBasicParsing -Uri ($AssetsPage -f $tag) -UserAgent $BrowserUA -TimeoutSec 30).Content
    $rx = [regex]('releases/download/' + [regex]::Escape($tag) + '/([^"]+)"')
    foreach ($x in $rx.Matches($html)) {
        $name = $x.Groups[1].Value
        if ($name -notmatch $AssetPattern) { continue }
        $rest = $html.Substring($x.Index + $x.Length)
        $next = $rest.IndexOf('releases/download/')
        if ($next -ge 0) { $rest = $rest.Substring(0, $next) }
        $s = [regex]::Match($rest, 'sha256:([0-9a-fA-F]{64})')
        $sha = if ($s.Success) { $s.Groups[1].Value.ToUpper() } else { '' }
        if (-not $sha -and $html -match ('releases/download/' + [regex]::Escape($tag) + '/(checksums?[^"]*\.txt)"')) {
            try { $sha = Get-ChecksumFromFile ($DownloadFmt -f $tag, $Matches[1]) $name } catch {}
        }
        return [pscustomobject]@{ Version = $tag; Name = $name; Url = ($DownloadFmt -f $tag, $name); Size = [long]0; Sha256 = $sha; Source = 'web' }
    }
    throw "Nessun archivio .7z win64 nella release $tag."
}

function Get-RemoteInfo {
    $apiErr = ''
    try { return (Get-RemoteApi) }
    catch { $apiErr = $_.Exception.Message }
    Write-Log "API GitHub fallita: $apiErr -> provo con le pagine web"
    try { return (Get-RemoteWeb) }
    catch { throw ("API: {0} | Web: {1}" -f $apiErr, $_.Exception.Message) }
}

function Refresh-Remote {
    $script:Remote = $null
    Set-Status $T.Checking 30
    try {
        $r = Get-RemoteInfo
        if (-not (ConvertTo-Ver $r.Version)) { Write-Log "Attenzione: tag in formato inatteso: $($r.Version)" }
        $script:Remote = $r
        Write-Log ("Remoto ({0}): {1} -> {2} (sha256 {3}, {4} byte)" -f $r.Source, $r.Version, $r.Name, $(if ($r.Sha256) { 'si' } else { 'NO' }), $r.Size)
    }
    catch { Write-Log ("Versione remota non ottenuta: {0}" -f $_.Exception.Message) }
    Set-Status $T.Ready 0
    if (-not $script:Remote) { Show-Error $T.NoRemote }
}

# --- Download (con gestione Zscaler) -----------------------------------------------------------
function Save-Download([string]$Url, [string]$Dest, [scriptblock]$OnProgress) {
    $resp = $null
    try {
        $req = [Net.HttpWebRequest]::Create($Url)
        $req.UserAgent = $BrowserUA
        $req.Timeout = 30000; $req.ReadWriteTimeout = 30000
        $req.Proxy = [Net.WebRequest]::GetSystemWebProxy()
        $req.Proxy.Credentials = [Net.CredentialCache]::DefaultCredentials
        $resp = $req.GetResponse()
        if ($resp.ContentType -like 'text/html*') { return @{ Ok = $false; Status = 403; Message = 'Risposta HTML (pagina di blocco?)' } }
        $total = $resp.ContentLength
        $in  = $resp.GetResponseStream()
        $out = [IO.File]::Create($Dest)
        try {
            $buf = New-Object byte[] 262144
            $done = [long]0
            $sw = [Diagnostics.Stopwatch]::StartNew(); $last = 0
            while (($n = $in.Read($buf, 0, $buf.Length)) -gt 0) {
                if ($script:Abort) { throw 'Annullato' }
                $out.Write($buf, 0, $n); $done += $n
                if ($sw.ElapsedMilliseconds - $last -ge 120) { $last = $sw.ElapsedMilliseconds; & $OnProgress $done $total }
            }
            & $OnProgress $done $total
        } finally { $out.Dispose() }
        if ($total -gt 0 -and $done -ne $total) { throw "Download incompleto ($done di $total byte)." }
        return @{ Ok = $true; Status = 200; Message = '' }
    }
    catch [Net.WebException] {
        $st = 0; if ($_.Exception.Response) { $st = [int]$_.Exception.Response.StatusCode }
        Remove-Item -LiteralPath $Dest -Force -ErrorAction SilentlyContinue
        return @{ Ok = $false; Status = $st; Message = $_.Exception.Message }
    }
    catch {
        Remove-Item -LiteralPath $Dest -Force -ErrorAction SilentlyContinue
        return @{ Ok = $false; Status = 0; Message = $_.Exception.Message }
    }
    finally { if ($resp) { $resp.Close() } }
}

function Request-Unlock([string]$Url, [string]$Name) {
    Write-Log "403 su $Name -> richiesto sblocco Zscaler nel browser"
    try { Start-Process $Url } catch { Write-Log "Start-Process fallito: $($_.Exception.Message)" }
    if ($script:Console) {
        Write-Host ($T.ZBlock -f $Name) -ForegroundColor Yellow
        $a = Read-Host $T.PressRetry
        return ($a -ne 'q')
    }
    $res = [System.Windows.Forms.MessageBox]::Show(($T.ZBlock -f $Name), $T.Title, 'RetryCancel', 'Warning')
    return ($res -eq 'Retry')
}

function Set-DownloadStatus($done, $total) {
    $pct = if ($total -gt 0) { [int](100 * $done / $total) } else { 0 }
    Set-Status ($T.Download -f $script:DlTitle) $pct ('{0:N1} / {1:N1} MB' -f ($done / 1MB), ($total / 1MB))
}

# Scarica $Url in $Dest (max 5 tentativi, con sblocco Zscaler). Controlla sempre errore, dimensione e SHA256.
function Get-File([string]$Url, [string]$Dest, [long]$Size = 0, [string]$Sha256 = '') {
    $res = $null
    for ($try = 1; $try -le 5; $try++) {
        $res = Save-Download -Url $Url -Dest $Dest -OnProgress { param($d, $tot) Set-DownloadStatus $d $tot }
        if ($res.Ok) { break }
        if ($script:Abort) { throw $T.Aborted }
        if ($res.Status -eq 403) {
            if (Request-Unlock $Url (Split-Path $Dest -Leaf)) { continue }
            throw $T.Aborted
        }
        throw ('Download fallito: ' + $res.Message)
    }
    if (-not $res.Ok) { throw ('Download fallito dopo vari tentativi: ' + $res.Message) }

    if (-not (Test-Path -LiteralPath $Dest)) { throw 'Download fallito: file non creato.' }
    $len = (Get-Item -LiteralPath $Dest).Length
    if ($len -eq 0 -or ($Size -gt 0 -and $len -ne $Size)) { throw "Dimensione inattesa del file scaricato ($len byte, attesi $Size)." }
    if ($Sha256) {
        $h = (Get-FileHash -LiteralPath $Dest -Algorithm SHA256).Hash
        if ($h -ne $Sha256) { throw 'Checksum SHA256 non valido: file corrotto o alterato.' }
        Write-Log "Download OK: $Dest ($len byte, SHA256 verificato)"
    } else {
        Write-Log "Download OK: $Dest ($len byte, nessun SHA256 disponibile)"
    }
}

# --- 7-Zip: dal PATH, altrimenti 7zr.exe scaricato nella cartella temporanea --------------------
function Get-7z {
    foreach ($n in '7zr.exe', '7z.exe', '7za.exe') {
        $c = Get-Command $n -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($c) { Write-Log "7-Zip dal PATH: $($c.Source)"; return $c.Source }
    }
    $dest = Pth $WorkDir '7zr.exe'
    Write-Log "7-Zip non trovato nel PATH: scarico $SevenZipUrl"
    $script:DlTitle = '7zr.exe'
    Get-File $SevenZipUrl $dest
    $b = [IO.File]::ReadAllBytes($dest)
    if ($b.Length -lt 100KB -or $b[0] -ne 0x4D -or $b[1] -ne 0x5A) { throw '7zr.exe scaricato non valido (non e'' un eseguibile Windows).' }
    return $dest
}

# --- Installazione -----------------------------------------------------------------------------
function Get-RunningWaterfox {
    $dir = $InstDir.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    $res = @()
    foreach ($p in @(Get-Process -Name 'waterfox', 'waterfox-portable' -ErrorAction SilentlyContinue)) {
        $path = $null; try { $path = $p.Path } catch {}
        if ($path -and $path.StartsWith($dir, [StringComparison]::OrdinalIgnoreCase)) { $res += $p }
    }
    $res
}

function Wait-WaterfoxClosed {
    while ($true) {
        $r = @(Get-RunningWaterfox)
        if (-not $r.Count) { return }
        Write-Log "Waterfox in esecuzione da '$InstDir' ($($r.Count) processi)"
        if ($script:Console) {
            Write-Host $T.Running -ForegroundColor Yellow
            if ((Read-Host $T.PressRetry) -eq 'q') { throw $T.Aborted }
        } else {
            if ([System.Windows.Forms.MessageBox]::Show($T.Running, $T.Title, 'RetryCancel', 'Warning') -ne 'Retry') { throw $T.Aborted }
        }
    }
}

function Invoke-Retry([scriptblock]$Action, [int]$Tries = 10) {
    for ($k = 1; ; $k++) {
        try { & $Action; return }
        catch {
            if ($k -ge $Tries) { throw }
            Write-Log "Tentativo $k fallito: $($_.Exception.Message)"
            Start-Sleep -Milliseconds 700; Pump
        }
    }
}

function Move-Dir([string]$From, [string]$To) {
    try { [IO.Directory]::Move($From, $To) }
    catch {
        Copy-Item -LiteralPath $From -Destination $To -Recurse -Force
        Remove-Item -LiteralPath $From -Recurse -Force
    }
}

function Install-Waterfox([bool]$Force = $false) {
    $r = $script:Remote
    if (-not $r) { throw 'Versione remota non disponibile.' }
    $target = $InstDir

    if ((Test-Installed) -and -not $Force -and -not (Test-Outdated)) { Write-Log "Gia' aggiornato ($(Get-LocalVersion))"; return 'uptodate' }
    Wait-WaterfoxClosed

    New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
    $dl  = Pth $WorkDir $r.Name
    $ext = Pth $WorkDir 'ext'
    Remove-Item -LiteralPath $ext -Recurse -Force -ErrorAction SilentlyContinue

    try {
        $script:DlTitle = "Waterfox $($r.Version)"
        Write-Log "=== Installazione $script:DlTitle in '$target'"
        Get-File $r.Url $dl $r.Size $r.Sha256

        Set-Status $T.Unpack 100
        $z = Get-7z
        $proc = Start-Process -FilePath $z -ArgumentList ('x "{0}" -o"{1}" -y' -f $dl, $ext) -PassThru -WindowStyle Hidden
        $null = $proc.Handle
        while (-not $proc.HasExited) { Pump; Start-Sleep -Milliseconds 80 }
        Write-Log "7z exit code: $($proc.ExitCode)"
        if ($proc.ExitCode -gt 1) { throw "Estrazione fallita (7z exit code $($proc.ExitCode))." }

        $exeSrc = Get-ChildItem -LiteralPath $ext -Recurse -File -Filter 'waterfox-portable.exe' -ErrorAction SilentlyContinue |
                  Sort-Object { $_.FullName.Length } | Select-Object -First 1
        $base = if ($exeSrc) { $exeSrc.DirectoryName } else { $null }
        if (-not $base -or -not (Test-Path -LiteralPath (Pth $base 'app' 'waterfox.exe'))) {
            Write-Log 'waterfox-portable.exe o app\waterfox.exe NON trovati. Contenuto estratto:'
            Get-ChildItem -LiteralPath $ext -Recurse -Depth 3 -ErrorAction SilentlyContinue | Select-Object -First 80 |
                ForEach-Object { Write-Log ('  ' + $_.FullName.Substring($ext.Length) + $(if ($_.PSIsContainer) { '\' } else { "  ($($_.Length))" })) }
            throw 'Struttura dell''archivio inattesa (manca waterfox-portable.exe o app\waterfox.exe). Invia il log.'
        }
        Write-Log "Archivio estratto in '$base'"

        Set-Status $T.Installing 100
        Wait-WaterfoxClosed
        New-Item -ItemType Directory -Force -Path $target | Out-Null

        # Sostituisce SOLO app\ e i file del launcher. data\ e il file .yml di configurazione non vengono mai toccati.
        $appCur = Pth $target 'app'; $appOld = Pth $target 'app.old'; $appNew = Pth $base 'app'
        $exeCur = Pth $target 'waterfox-portable.exe'; $exeOld = Pth $target 'waterfox-portable.exe.old'
        Remove-Item -LiteralPath $appOld -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $exeOld -Force -ErrorAction SilentlyContinue
        $hadApp = Test-Path -LiteralPath $appCur
        $hadExe = Test-Path -LiteralPath $exeCur
        try {
            if ($hadApp) { Invoke-Retry { Move-Dir $appCur $appOld } }
            Invoke-Retry { Move-Dir $appNew $appCur }
            if ($hadExe) { Copy-Item -LiteralPath $exeCur -Destination $exeOld -Force }
            Invoke-Retry { Copy-Item -LiteralPath (Pth $base 'waterfox-portable.exe') -Destination $exeCur -Force }
            foreach ($f in 'portapp.json', 'CHANGELOG.md', 'README.md') {
                $s = Pth $base $f
                if (Test-Path -LiteralPath $s) { Copy-Item -LiteralPath $s -Destination (Pth $target $f) -Force }
            }
        }
        catch {
            Write-Log "Sostituzione fallita ($($_.Exception.Message)): ripristino la versione precedente"
            if ($hadApp -and (Test-Path -LiteralPath $appOld)) {
                Remove-Item -LiteralPath $appCur -Recurse -Force -ErrorAction SilentlyContinue
                try { Move-Dir $appOld $appCur } catch { Write-Log "Ripristino app\ fallito: $($_.Exception.Message)" }
            }
            if ($hadExe -and (Test-Path -LiteralPath $exeOld)) {
                try { Copy-Item -LiteralPath $exeOld -Destination $exeCur -Force; Remove-Item -LiteralPath $exeOld -Force } catch { Write-Log "Ripristino exe fallito: $($_.Exception.Message)" }
            }
            throw
        }
        Remove-Item -LiteralPath $appOld -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $exeOld -Force -ErrorAction SilentlyContinue

        $upd = Pth $target 'updates'
        New-Item -ItemType Directory -Force -Path $upd | Out-Null
        Set-Content -LiteralPath (Pth $upd 'Version.log') -Value ("{0}|win64" -f $r.Version) -NoNewline -Encoding ASCII

        if ($script:Opt.Shortcut) {
            try {
                $lnk = Pth ([Environment]::GetFolderPath('DesktopDirectory')) 'Waterfox Portable.lnk'
                if (-not (Test-Path -LiteralPath $lnk)) {
                    $sh = New-Object -ComObject WScript.Shell
                    $l = $sh.CreateShortcut($lnk)
                    $l.TargetPath = $exeCur; $l.WorkingDirectory = $target; $l.IconLocation = "$exeCur,0"
                    $l.Save()
                }
            } catch { Write-Log "Collegamento non creato: $($_.Exception.Message)" }
        }
        Write-Log "Installato Waterfox $($r.Version) in '$target'"
        Set-Status ($T.Done -f "Waterfox $($r.Version)") 0
        return 'installed'
    }
    finally {
        Remove-Item -LiteralPath $WorkDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Install-One {
    if ((Test-Installed) -and -not (Test-Outdated) -and -not $script:Opt.IgnoreVer) {
        if ($script:Console) { Write-Host $T.UpToDate } else { [void][System.Windows.Forms.MessageBox]::Show($T.UpToDate, $T.Title, 'OK', 'Information') }
        return
    }
    [void](Install-Waterfox $true)
}

# Modalita' -UpdateAll: aggiorna solo se Waterfox e' gia' installato
function Update-Installed {
    if (-not (Test-Installed)) { Write-Host $T.NotInstalledMsg; Write-Log 'UpdateAll: non installato, nulla da fare'; return }
    if (Test-Outdated) { [void](Install-Waterfox $false) } else { Write-Host $T.UpToDate }
}

# --- Autoaggiornamento da GitHub ---------------------------------------------------------------
# Waterfox-Updater.version = "<versione>|<sha256 di Waterfox-Updater.ps1>". Ritorna $true se ha aggiornato e rilanciato lo script.
function Invoke-SelfUpdate {
    if ($NoSelfUpdate -or [string]::IsNullOrWhiteSpace($SelfUpdateBase) -or $SelfUpdateBase -match 'YOUR_USER' -or -not $PSCommandPath) { return $false }
    $tmp = "$PSCommandPath.new"
    try {
        $base = $SelfUpdateBase.TrimEnd('/')
        $resp = Invoke-WebRequest -UseBasicParsing -Uri "$base/Waterfox-Updater.version" -TimeoutSec 10
        $txt  = if ($resp.Content -is [byte[]]) { [Text.Encoding]::UTF8.GetString($resp.Content) } else { [string]$resp.Content }
        $v = $txt.Trim([char]0xFEFF, ' ', "`r", "`n", "`t").Split('|')
        $newVer = $v[0].Trim(); $sha = if ($v.Count -gt 1) { $v[1].Trim() } else { '' }
        if ([version]$newVer -le [version]$ScriptVersion) { return $false }
        Write-Log "Autoaggiornamento: disponibile $newVer (attuale $ScriptVersion)"
        if (-not $script:Console) {
            $a = [System.Windows.Forms.MessageBox]::Show(($T.SelfUpd -f $newVer, $ScriptVersion), $T.Title, 'YesNo', 'Question')
            if ($a -ne 'Yes') { return $false }
        }
        Invoke-WebRequest -UseBasicParsing -Uri "$base/Waterfox-Updater.ps1" -OutFile $tmp -TimeoutSec 60
        if ($sha -and ((Get-FileHash -LiteralPath $tmp -Algorithm SHA256).Hash -ne $sha)) { throw 'SHA256 non corrispondente' }
        $errs = $null; $tk = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($tmp, [ref]$tk, [ref]$errs)
        if ($errs -and $errs.Count) { throw 'il file scaricato non e'' uno script PowerShell valido' }
        Copy-Item -LiteralPath $PSCommandPath -Destination "$PSCommandPath.bak" -Force
        Move-Item -LiteralPath $tmp -Destination $PSCommandPath -Force
        Write-Log "Script aggiornato a $newVer (backup: $PSCommandPath.bak). Riavvio."
        $al = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f $PSCommandPath))
        if ($UpdateAll) { $al += '-UpdateAll' }
        if ($InstallDir) { $al += '-InstallDir'; $al += ('"{0}"' -f $InstallDir) }
        Start-Process -FilePath (Get-Process -Id $PID).Path -ArgumentList $al
        return $true
    }
    catch { Write-Log "Autoaggiornamento fallito: $($_.Exception.Message)"; return $false }
    finally { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
}

# ==== MAIN ====
if (-not [Environment]::Is64BitOperatingSystem) {
    if ($script:Console) { Write-Host $T.Need64 -ForegroundColor Red } else { [void][System.Windows.Forms.MessageBox]::Show($T.Need64, $T.Title, 'OK', 'Error') }
    exit 1
}

# =================================================================================================
# Modalita' console (-UpdateAll)
# =================================================================================================
if ($script:Console) {
    Write-Log '--- avvio -UpdateAll'
    if (Invoke-SelfUpdate) { exit 0 }
    Refresh-Remote
    if (-not $script:Remote) { exit 1 }
    try { Update-Installed } catch { Show-Error $_.Exception.Message; exit 1 }
    Write-Host 'Fatto.'
    exit 0
}

# =================================================================================================
# GUI
# =================================================================================================
function Pt($x, $y) { New-Object System.Drawing.Point($x, $y) }
function Sz($w, $h) { New-Object System.Drawing.Size($w, $h) }
function New-Label([string]$text, $x, $y, $w = 0, $h = 0) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $text; $l.Location = Pt $x $y
    if ($w) { $l.AutoSize = $false; $l.Size = Sz $w $h } else { $l.AutoSize = $true }
    $l
}

$form = New-Object System.Windows.Forms.Form
$form.Text = "$($T.Title) $ScriptVersion"
$form.ClientSize = Sz 360 250
$form.FormBorderStyle = 'FixedSingle'; $form.MaximizeBox = $false; $form.StartPosition = 'CenterScreen'
$form.Font = New-Object System.Drawing.Font('Segoe UI', 9)
foreach ($ico in 'Waterfox Updater.ico') {
    $p = Pth $Root $ico
    if (Test-Path -LiteralPath $p) { try { $form.Icon = New-Object System.Drawing.Icon($p); break } catch {} }
}
$tip = New-Object System.Windows.Forms.ToolTip

# Versioni + pulsante installa/aggiorna
$grp1 = New-Object System.Windows.Forms.GroupBox
$grp1.Location = Pt 10 6; $grp1.Size = Sz 340 80
$grp1.Controls.Add((New-Label $T.RemoteVer 10 22))
$script:lblRemote = New-Label '...' 128 22; $grp1.Controls.Add($script:lblRemote)
$grp1.Controls.Add((New-Label $T.LocalVer 10 48))
$script:lblLocal = New-Label '...' 128 48; $grp1.Controls.Add($script:lblLocal)
$script:btnMain = New-Object System.Windows.Forms.Button
$script:btnMain.Text = $T.Install; $script:btnMain.Location = Pt 232 26; $script:btnMain.Size = Sz 98 32
$grp1.Controls.Add($script:btnMain)
$form.Controls.Add($grp1)
$script:grp1 = $grp1

# Cartella e opzioni
$script:lblDir = New-Label $InstDir 16 94 328 18
$script:lblDir.AutoEllipsis = $true
$tip.SetToolTip($script:lblDir, $InstDir)
$script:chkIgn = New-Object System.Windows.Forms.CheckBox
$script:chkIgn.Text = $T.IgnoreVer; $script:chkIgn.AutoSize = $true; $script:chkIgn.Location = Pt 16 120
$script:chkLnk = New-Object System.Windows.Forms.CheckBox
$script:chkLnk.Text = $T.Shortcut; $script:chkLnk.AutoSize = $true; $script:chkLnk.Location = Pt 16 144
$script:btnExit = New-Object System.Windows.Forms.Button
$script:btnExit.Text = $T.Exit; $script:btnExit.Location = Pt 275 136; $script:btnExit.Size = Sz 75 28
$form.Controls.AddRange(@($script:lblDir, $script:chkIgn, $script:chkLnk, $script:btnExit))

# Stato / progresso
$grp3 = New-Object System.Windows.Forms.GroupBox
$grp3.Location = Pt 10 172; $grp3.Size = Sz 340 72
$script:lblStatus = New-Label $T.Ready 8 16 220 20
$script:lblRight  = New-Label '' 200 16 132 20; $script:lblRight.TextAlign = 'TopRight'
$script:bar = New-Object System.Windows.Forms.ProgressBar
$script:bar.Location = Pt 8 42; $script:bar.Size = Sz 324 14
$grp3.Controls.AddRange(@($script:lblStatus, $script:lblRight, $script:bar))
$form.Controls.Add($grp3)

# --- Logica UI ---
function Refresh-UI {
    $green = [System.Drawing.Color]::FromArgb(126, 205, 126)
    $red   = [System.Drawing.Color]::FromArgb(236, 112, 112)
    $r = $script:Remote
    $inst = Test-Installed; $l = Get-LocalVersion
    $script:lblRemote.Text = if ($r) { $r.Version } else { 'n/d' }
    $script:lblLocal.Text  = if (-not $inst) { $T.NotInstalled } elseif ($l) { $l } else { '?' }
    $b = $script:btnMain
    $b.Text = if ($inst) { $T.Update } else { $T.Install }
    $b.Enabled = [bool]$r
    $b.UseVisualStyleBackColor = $true
    if ($inst) {
        $b.UseVisualStyleBackColor = $false
        $b.BackColor = if (Test-Outdated) { $red } else { $green }
    }
}

function Invoke-Op([scriptblock]$Work, $Arg = $null) {
    if ($script:Busy) { return }
    $script:Busy = $true
    foreach ($c in $script:grp1, $script:chkIgn, $script:chkLnk) { $c.Enabled = $false }
    try { & $Work $Arg }
    catch { if ($_.Exception.Message -ne $T.Aborted) { Show-Error $_.Exception.Message } else { Write-Log 'Annullato dall''utente' } }
    finally {
        $script:Busy = $false
        foreach ($c in $script:grp1, $script:chkIgn, $script:chkLnk) { $c.Enabled = $true }
        Set-Status $T.Ready 0
        Refresh-UI
    }
}

$script:chkIgn.Add_CheckedChanged({ $script:Opt.IgnoreVer = $script:chkIgn.Checked })
$script:chkLnk.Add_CheckedChanged({ $script:Opt.Shortcut = $script:chkLnk.Checked })
$script:btnMain.Add_Click({ Invoke-Op { Install-One } })
$script:btnExit.Add_Click({ $form.Close() })
$form.Add_FormClosing({ $script:Abort = $true })
$form.Add_FormClosed({ Remove-Item -LiteralPath $WorkDir -Recurse -Force -ErrorAction SilentlyContinue })

$form.Add_Shown({
    Write-Log '--- avvio GUI'
    Invoke-Op {
        if (Invoke-SelfUpdate) { $form.Close(); return }
        if (@(Get-RunningWaterfox).Count) {
            [void][System.Windows.Forms.MessageBox]::Show($T.Running, $T.Title, 'OK', 'Exclamation')
        }
        Refresh-Remote
    }
})

Refresh-UI
[void]$form.ShowDialog()
