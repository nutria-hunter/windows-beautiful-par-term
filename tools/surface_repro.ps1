# Track the real window size while pi runs, alongside par-term's surface resizes.
#
# If the window rect stays put while the surface jumps to 3840x2088, nothing asked
# the window to resize and the bug is inside par-term's own size computation. If the
# window really grows, something requested a resize and the caller is the culprit.

$ErrorActionPreference = 'Continue'
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class TW {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
}
"@
[void][TW]::SetProcessDPIAware()

$root = 'C:\Users\jky72\par-term'
$debugLog = Join-Path $env:TEMP 'par_term_debug.log'

Get-Process par-term -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 900
Remove-Item $debugLog -ErrorAction SilentlyContinue

$p = Start-Process "$root\par-term.exe" -PassThru -ArgumentList @('--log-level', 'info', '--command-to-send', '"pi"')
Write-Output "launched par-term pid=$($p.Id); NO window interaction from this script"
Start-Sleep -Seconds 3

$state = @{ area = 0; hwnd = [IntPtr]::Zero }
$cb = {
  param($h, $l)
  $q = 0; [void][TW]::GetWindowThreadProcessId($h, [ref]$q)
  if ($q -ne $p.Id) { return $true }
  if (-not [TW]::IsWindowVisible($h)) { return $true }
  $r = New-Object TW+RECT; [void][TW]::GetWindowRect($h, [ref]$r)
  $a = ($r.R - $r.L) * ($r.B - $r.T)
  if ($a -gt $state.area) { $state.area = $a; $state.hwnd = $h }
  return $true
}
$del = [TW+EnumProc]$cb
[void][TW]::EnumWindows($del, [IntPtr]::Zero)
$hwnd = $state.hwnd
if ($hwnd -eq [IntPtr]::Zero) { Write-Output 'no window'; exit 1 }

$timeline = @()
for ($i = 0; $i -lt 21; $i++) {
  $r = New-Object TW+RECT
  $c = New-Object TW+RECT
  [void][TW]::GetWindowRect($hwnd, [ref]$r)
  [void][TW]::GetClientRect($hwnd, [ref]$c)
  $timeline += ("{0,5}s  window={1}x{2}  client={3}x{4}" -f ($i * 2), ($r.R - $r.L), ($r.B - $r.T), ($c.R - $c.L), ($c.B - $c.T))
  Start-Sleep -Seconds 2
}
Get-Process par-term -ErrorAction SilentlyContinue | Stop-Process -Force

Write-Output ''
Write-Output '=== window size over time (no script interaction) ==='
$prev = ''
foreach ($t in $timeline) {
  if ($t.Substring(5) -ne $prev) { Write-Output $t; $prev = $t.Substring(5) }
}

Write-Output ''
Write-Output '=== surface / resize / source lines ==='
if (Test-Path $debugLog) {
  Get-Content $debugLog |
    Select-String -Pattern 'SURFACE_RESIZE|SURFACE_SRC|Configuring surface|Resizing terminal to|ScaleFactor' |
    Select-Object -First 30 | ForEach-Object { $_.Line }
} else {
  Write-Output 'no debug log'
}
