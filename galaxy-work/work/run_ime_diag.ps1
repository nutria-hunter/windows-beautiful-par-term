# Launch an instrumented par-term and watch it for an IME composition box, as one detached job.
#
# The pid cannot be handed over by hand: the window is closed by its user between turns, and a
# watcher started with a stale pid reports "no visible window" instead of watching anything. So the
# launch and the watch are one process - the watcher gets the pid of the window this script just
# opened, and par-term is left running afterwards for the caller to type into.
#
# ASCII source on purpose: PowerShell 5.1 decodes a BOM-less script with the system codepage.
#
# Usage: powershell -NoProfile -File .\run_ime_diag.ps1 -Seconds 240

param(
  [int]$Seconds = 240,
  [string]$Exe = 'C:\Users\jky72\par-term\par-term.exe',
  [string]$Watcher = 'C:\Users\jky72\par-term\galaxy-work\work\watch_ime_windows.py',
  [string]$Python = 'C:\Users\jky72\AppData\Local\Programs\Python\Python310\python.exe'
)

$ErrorActionPreference = 'Continue'

# Debug macros need DEBUG_LEVEL; the log crate needs --log-level (config has log_level: off).
$env:DEBUG_LEVEL = '3'

$p = Start-Process $Exe -PassThru -ArgumentList @('--log-level', 'info')
Write-Output "started par-term pid=$($p.Id)"
Start-Sleep -Seconds 6

if (-not (Get-Process -Id $p.Id -ErrorAction SilentlyContinue)) {
  Write-Output "FAIL: par-term exited during startup"
  exit 1
}

& $Python $Watcher --pid $p.Id --seconds $Seconds
Write-Output "watch finished; par-term pid=$($p.Id) is still running for the caller to type into"
