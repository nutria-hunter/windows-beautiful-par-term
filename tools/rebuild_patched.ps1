$ErrorActionPreference = 'Continue'
$dst = 'C:\Users\jky72\par-term\build\par-term'
$log = 'C:\Users\jky72\par-term\build\rebuild.log'
Set-Location $dst

$cargo = Join-Path $env:USERPROFILE '.cargo\bin\cargo.exe'
Write-Output '--- incremental cargo build --release ---'
$sw = [System.Diagnostics.Stopwatch]::StartNew()
& $cargo build --release 2>&1 | Tee-Object -FilePath $log | Out-Null
$code = $LASTEXITCODE
$sw.Stop()
Write-Output ("exit code: " + $code + "   elapsed: " + [math]::Round($sw.Elapsed.TotalMinutes,1) + " min")

Write-Output '--- errors ---'
if (Test-Path $log) {
  Get-Content $log | Select-String -Pattern '^(error|warning: unused)' | Select-Object -First 15 |
    ForEach-Object { Write-Output $_.Line }
}
Write-Output '--- last 25 lines ---'
if (Test-Path $log) { Get-Content $log -Tail 25 | ForEach-Object { Write-Output $_ } }

$exe = Join-Path $dst 'target\release\par-term.exe'
if (Test-Path $exe) {
  $fi = Get-Item $exe
  Write-Output ("BUILT: " + [math]::Round($fi.Length/1MB,1) + " MB  " + $fi.LastWriteTime)
  # refresh the saved patch so it matches the binary
  git diff > 'C:\Users\jky72\par-term\build\tab-bar-drag.patch' 2>&1
  Write-Output 'patch refreshed'
} else {
  Write-Output 'NO BINARY PRODUCED'
}
