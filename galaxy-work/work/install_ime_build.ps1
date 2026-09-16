# Swap in the freshly built par-term and keep the previous binary as a rollback.
#
# par-term.exe and target\release\par-term.exe start out hard-linked, but a rebuild replaces the
# file in target\, so the copy in par-term\ keeps the OLD bytes. The running par-term also holds a
# lock on its own image, so the copy can only happen once it has exited - this script waits for
# that, which is why it exists instead of a one-line Copy-Item.
#
# ASCII source on purpose: PowerShell 5.1 decodes a BOM-less script with the system codepage.
#
# Usage (from any shell):
#   powershell -NoProfile -File install_ime_build.ps1

param(
  [string]$Source = 'C:\Users\jky72\par-term\build\par-term\target\release\par-term.exe',
  [string]$Target = 'C:\Users\jky72\par-term\par-term.exe',
  [string]$Backup = 'C:\Users\jky72\par-term\par-term-prev-imefix.exe',
  [int]$TimeoutSeconds = 600
)

$ErrorActionPreference = 'Stop'

$srcHash = (Get-FileHash $Source -Algorithm SHA256).Hash
Write-Output "source : $Source"
Write-Output "sha256 : $srcHash"

$running = Get-Process -Name 'par-term' -ErrorAction SilentlyContinue
if ($running) {
  Write-Output "par-term is running (pid $($running.Id -join ', ')). Close it and this script will finish the swap."
  Write-Output "waiting up to $TimeoutSeconds s ..."
  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  while ((Get-Process -Name 'par-term' -ErrorAction SilentlyContinue) -and (Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 2
  }
  if (Get-Process -Name 'par-term' -ErrorAction SilentlyContinue) {
    Write-Output 'FAIL: par-term is still running; nothing was replaced.'
    exit 1
  }
}

Copy-Item -Path $Target -Destination $Backup -Force
Copy-Item -Path $Source -Destination $Target -Force
$newHash = (Get-FileHash $Target -Algorithm SHA256).Hash
Write-Output "backup : $Backup"
Write-Output "installed: $Target"
Write-Output "sha256 : $newHash"
if ($newHash -eq $srcHash) {
  Write-Output 'OK: installed binary matches the build. Start par-term again.'
} else {
  Write-Output 'FAIL: installed hash does not match the build.'
  exit 1
}
