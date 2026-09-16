# Make the Vulkan-preferring build the default par-term, as soon as the running window is closed.
#
# The running par-term holds a lock on its own image, and this watcher is started by Task Scheduler so
# it survives the terminal being closed (the agent session inside it dies at the same moment). It waits
# for a clean exit, backs up the current binary, installs the new one, verifies the hash, and brings
# par-term back up on the new build.
#
# ASCII-only on purpose: PowerShell 5.1 decodes a BOM-less script with the system codepage.
$ErrorActionPreference = 'Stop'

$root = 'C:\Users\jky72\par-term'
$new = Join-Path $root 'par-term-vulkan.exe'
$exe = Join-Path $root 'par-term.exe'
$bak = Join-Path $root 'par-term-prev-dx12.exe'
$log = Join-Path $root 'galaxy-work\outputs\vulkan-default.log'

function Write-Log([string]$message) {
  $line = '[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $message
  Add-Content -Path $log -Value $line
}

Write-Log 'watcher started; waiting for par-term to exit (max 60 min)'

$deadline = (Get-Date).AddMinutes(60)
while ((Get-Process -Name 'par-term' -ErrorAction SilentlyContinue) -and ((Get-Date) -lt $deadline)) {
  Start-Sleep -Seconds 2
}

if (Get-Process -Name 'par-term' -ErrorAction SilentlyContinue) {
  Write-Log 'timeout: par-term is still running, nothing was replaced'
  exit 1
}

if (-not (Test-Path $new)) {
  Write-Log "FAIL: $new is missing"
  exit 2
}

$newHash = (Get-FileHash $new -Algorithm SHA256).Hash
Write-Log "incoming build sha256 $newHash"

Copy-Item -Path $exe -Destination $bak -Force
Copy-Item -Path $new -Destination $exe -Force

$exeHash = (Get-FileHash $exe -Algorithm SHA256).Hash
if ($exeHash -ne $newHash) {
  Write-Log 'FAIL: hash mismatch after copy; restoring the backup'
  Copy-Item -Path $bak -Destination $exe -Force
  exit 3
}

Write-Log "OK: par-term.exe is now the Vulkan-preferring build (backup: $bak)"
Start-Process -FilePath $exe -WorkingDirectory $root
Write-Log 'relaunched par-term on the new build'

schtasks /Delete /TN ParTermVulkanDefault /F | Out-Null
Write-Log 'scheduled task removed'
