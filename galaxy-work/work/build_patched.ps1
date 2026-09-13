$ErrorActionPreference = 'Continue'
$src = 'C:\tmp\pi-github-repos\runtime-h5bYj8\ed9df33d6dd00470af0d461f37bdf150039cf4c307191a08a84957f680d27152'
$work = 'C:\Users\jky72\par-term\build'
$dst = Join-Path $work 'par-term'
$log = Join-Path $work 'build.log'

New-Item -ItemType Directory -Force -Path $work | Out-Null
if (Test-Path $dst) { Write-Output "removing previous copy ..."; Remove-Item -Recurse -Force $dst }
Write-Output "copying source -> $dst"
Copy-Item -Recurse -Force $src $dst

Set-Location $dst
Write-Output '--- patched files (git status) ---'
git status --short 2>&1 | ForEach-Object { Write-Output $_ }
Write-Output '--- saving patch ---'
git diff > (Join-Path $work 'tab-bar-drag.patch') 2>&1
Get-Item (Join-Path $work 'tab-bar-drag.patch') | Select-Object Length | ForEach-Object { Write-Output ("patch bytes: " + $_.Length) }

$cargo = Join-Path $env:USERPROFILE '.cargo\bin\cargo.exe'
$rustc = Join-Path $env:USERPROFILE '.cargo\bin\rustc.exe'
Write-Output '--- toolchain ---'
& $rustc -vV 2>&1 | Where-Object { $_ -match 'host|release' } | ForEach-Object { Write-Output $_ }

Write-Output '--- cargo build --release (this takes a while) ---'
$sw = [System.Diagnostics.Stopwatch]::StartNew()
& $cargo build --release 2>&1 | Tee-Object -FilePath $log | Out-Null
$code = $LASTEXITCODE
$sw.Stop()
Write-Output ("exit code: " + $code + "   elapsed: " + [math]::Round($sw.Elapsed.TotalMinutes,1) + " min")
Write-Output '--- last 45 log lines ---'
if (Test-Path $log) { Get-Content $log -Tail 45 | ForEach-Object { Write-Output $_ } }
Write-Output '--- errors/warnings summary ---'
if (Test-Path $log) {
  Get-Content $log | Select-String -Pattern '^error' | Select-Object -First 20 | ForEach-Object { Write-Output $_.Line }
}
$exe = Join-Path $dst 'target\release\par-term.exe'
if (Test-Path $exe) {
  $fi = Get-Item $exe
  Write-Output ("BUILT: " + $exe + "  " + [math]::Round($fi.Length/1MB,1) + " MB  " + $fi.LastWriteTime)
} else {
  Write-Output 'NO BINARY PRODUCED'
}
