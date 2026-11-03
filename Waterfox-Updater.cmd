@echo off
rem Avvia Waterfox-Updater.ps1 senza dover scrivere il comando.
rem Senza argomenti: GUI (finestra console nascosta). Con argomenti (es. -UpdateAll): console visibile.
if "%~1"=="" (
    start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0Waterfox-Updater.ps1"
) else (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Waterfox-Updater.ps1" %*
    pause
)
