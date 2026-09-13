$ErrorActionPreference = 'Continue'
$dir = 'C:\Users\jky72\par-term\toolchain'
New-Item -ItemType Directory -Force -Path $dir | Out-Null
Set-Location $dir
Write-Output "workdir: $dir"

$init = Join-Path $dir 'rustup-init.exe'
if (-not (Test-Path $init) -or (Get-Item $init).Length -lt 1000000) {
  Write-Output 'downloading rustup-init.exe ...'
  curl.exe -sL -o $init 'https://static.rust-lang.org/rustup/dist/x86_64-pc-windows-msvc/rustup-init.exe'
}
if (-not (Test-Path $init)) { Write-Output 'ERROR: download failed'; exit 1 }
Write-Output ("rustup-init.exe size = " + (Get-Item $init).Length + " bytes")

Write-Output 'installing toolchain (stable-x86_64-pc-windows-msvc, minimal profile) ...'
& $init -y --default-toolchain stable-x86_64-pc-windows-msvc --profile minimal 2>&1 |
  ForEach-Object { Write-Output $_ }

$cargo = Join-Path $env:USERPROFILE '.cargo\bin\cargo.exe'
$rustc = Join-Path $env:USERPROFILE '.cargo\bin\rustc.exe'
Write-Output '--- verify ---'
if (Test-Path $rustc) { & $rustc --version } else { Write-Output 'rustc MISSING' }
if (Test-Path $cargo) { & $cargo --version } else { Write-Output 'cargo MISSING' }
& $cargo -Vv 2>&1 | Select-String -Pattern 'host|release' | ForEach-Object { Write-Output $_ }
