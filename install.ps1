<#
.SYNOPSIS
    새 PC에 par-term(이 포크)을 설치합니다.

.DESCRIPTION
    release/par-term.exe 를 설치 폴더로, config/config.yaml 과
    config/shaders/tilted-spiral.glsl 을 %APPDATA%\par-term\ 아래로 복사합니다.
    기존 파일은 덮어쓰기 전에 .bak-<타임스탬프> 로 백업합니다.

    -WhatIf 를 붙이면 실제로 복사하지 않고 계획만 보여줍니다.

.PARAMETER InstallDir
    실행파일을 둘 폴더입니다. 기본값은 %USERPROFILE%\par-term.

.PARAMETER SkipConfig
    설정과 셰이더는 건드리지 않고 실행파일만 갱신합니다.
    이미 쓰던 설정을 유지한 채 바이너리만 올릴 때 씁니다.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -WhatIf

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -SkipConfig
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$InstallDir = (Join-Path $env:USERPROFILE 'par-term'),
    [switch]$SkipConfig
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = $PSScriptRoot
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'

function Copy-WithBackup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination,
        [Parameter(Mandatory)][bool]$DryRun
    )

    if (-not (Test-Path -LiteralPath $Source)) {
        throw "배포본에 파일이 없습니다: $Source"
    }

    Write-Host "  $Destination"
    if ($DryRun) {
        Write-Host '    (미리보기 — 복사하지 않음)'
        return
    }

    $parent = Split-Path -Parent $Destination
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
        Write-Host '    (폴더 생성)'
    }

    if (Test-Path -LiteralPath $Destination) {
        $backup = "$Destination.bak-$stamp"
        Copy-Item -LiteralPath $Destination -Destination $backup -Force
        Write-Host "    기존 파일 백업 -> $backup"
    }

    Copy-Item -LiteralPath $Source -Destination $Destination -Force
    Write-Host '    복사 완료'
}

Write-Host 'par-term 설치'
if ($WhatIfPreference) {
    Write-Host '(미리보기 모드: 실제로 복사하지 않습니다)'
}
Write-Host ''

Write-Host '[1/3] 실행파일'
Copy-WithBackup -Source (Join-Path $repoRoot 'release/par-term.exe') `
    -Destination (Join-Path $InstallDir 'par-term.exe') -DryRun $WhatIfPreference

if ($SkipConfig) {
    Write-Host '[2/3] 설정 — 건너뜀 (-SkipConfig)'
    Write-Host '[3/3] 배경 셰이더 — 건너뜀 (-SkipConfig)'
}
else {
    $appDir = Join-Path $env:APPDATA 'par-term'
    Write-Host '[2/3] 설정'
    Copy-WithBackup -Source (Join-Path $repoRoot 'config/config.yaml') `
        -Destination (Join-Path $appDir 'config.yaml') -DryRun $WhatIfPreference

    Write-Host '[3/3] 배경 셰이더'
    Copy-WithBackup -Source (Join-Path $repoRoot 'config/shaders/tilted-spiral.glsl') `
        -Destination (Join-Path $appDir 'shaders/tilted-spiral.glsl') -DryRun $WhatIfPreference
}

$exePath = Join-Path $InstallDir 'par-term.exe'
Write-Host ''
Write-Host '다음 단계'
Write-Host '  1) 폰트: Maple Mono NF KR 을 설치하세요 (없으면 폴백되어 글자가 밋밋해집니다)'
Write-Host "  2) 실행: & '$exePath'"
Write-Host ''
Write-Host '되돌리기: release/par-term-official-0.45.0.exe 를 같은 자리에 덮어쓰세요.'
