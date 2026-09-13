# Capture a time series of frames from a single par-term run.
#
# Twinkle cannot be judged from two separate launches: iTime restarts each run, so both captures
# land on nearly the same phase. Frames from one run advance iTime continuously, which is the
# only way to measure how much a star's brightness actually moves over time. Star positions in
# the sky field are screen-fixed, so the same pixel can be sampled across the whole series.
#
# Usage: powershell -NoProfile -File shader_series.ps1 -Dir <folder> [-Frames 8] [-Interval 2.5]
param(
    [Parameter(Mandatory)][string]$Dir,
    [int]$Frames = 8,
    [double]$Interval = 2.5,
    [int]$Width = 1300,
    [int]$Height = 900,
    [string]$Exe = 'C:\Users\jky72\par-term\par-term.exe'
)

$ErrorActionPreference = 'Continue'
Add-Type @'
using System;
using System.Runtime.InteropServices;
public class Series {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint f);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
}
'@
[void][Series]::SetProcessDPIAware()

if (-not (Test-Path -LiteralPath $Dir)) {
    New-Item -ItemType Directory -Force -Path $Dir | Out-Null
}

$proc = Start-Process $Exe -PassThru
Start-Sleep -Seconds 3

$state = @{ area = 0; hwnd = [IntPtr]::Zero }
$cb = {
    param($h, $l)
    $owner = 0; [void][Series]::GetWindowThreadProcessId($h, [ref]$owner)
    if ($owner -ne $proc.Id -or -not [Series]::IsWindowVisible($h)) { return $true }
    $r = New-Object Series+RECT; [void][Series]::GetWindowRect($h, [ref]$r)
    $a = ($r.R - $r.L) * ($r.B - $r.T)
    if ($a -gt $state.area) { $state.area = $a; $state.hwnd = $h }
    return $true
}
[void][Series]::EnumWindows([Series+EnumProc]$cb, [IntPtr]::Zero)
if ($state.hwnd -eq [IntPtr]::Zero) { Write-Output 'no visible window'; exit 1 }

[void][Series]::SetWindowPos($state.hwnd, [IntPtr](-1), 80, 80, $Width, $Height, 0x0040)
Start-Sleep -Seconds 4

for ($i = 1; $i -le $Frames; $i++) {
    $out = Join-Path $Dir ("frame{0:d2}.png" -f $i)
    & python 'C:\Users\jky72\par-term\galaxy-work\work\cap_pid.py' "$($proc.Id)" $out | Out-Null
    Write-Output "frame $i -> $out"
    if ($i -lt $Frames) { Start-Sleep -Seconds $Interval }
}

Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
Write-Output 'series done'
