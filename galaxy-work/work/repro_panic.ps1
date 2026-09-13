# Reproduce the layout panic with a backtrace.
#
# The panic hook installed by par-term writes to %TEMP%\par_term_debug.log, and
# honours RUST_BACKTRACE. Resizing is the trigger, so the window is walked through
# several sizes.

$ErrorActionPreference = 'Continue'
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class RP {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
}
"@
[void][RP]::SetProcessDPIAware()

$logPath = Join-Path $env:TEMP 'par_term_debug.log'
Remove-Item $logPath -ErrorAction SilentlyContinue

Get-Process par-term -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 800

$env:RUST_BACKTRACE = '1'
$p = Start-Process 'C:\Users\jky72\par-term\par-term.exe' -PassThru
Write-Output "launched pid=$($p.Id) with RUST_BACKTRACE=1"
Start-Sleep -Seconds 6

$state = @{ area = 0; hwnd = [IntPtr]::Zero }
$cb = {
  param($h, $l)
  $q = 0; [void][RP]::GetWindowThreadProcessId($h, [ref]$q)
  if ($q -ne $p.Id) { return $true }
  if (-not [RP]::IsWindowVisible($h)) { return $true }
  $r = New-Object RP+RECT; [void][RP]::GetWindowRect($h, [ref]$r)
  $a = ($r.R - $r.L) * ($r.B - $r.T)
  if ($a -gt $state.area) { $state.area = $a; $state.hwnd = $h }
  return $true
}
$del = [RP+EnumProc]$cb
[void][RP]::EnumWindows($del, [IntPtr]::Zero)
$hwnd = $state.hwnd

foreach ($size in @(@(1100, 700), @(900, 560), @(1240, 780), @(700, 460))) {
  if ($hwnd -eq [IntPtr]::Zero) { break }
  [void][RP]::SetWindowPos($hwnd, [IntPtr]::Zero, 90, 90, $size[0], $size[1], 0x0040)
  Start-Sleep -Milliseconds 1400
  $alive = Get-Process -Id $p.Id -ErrorAction SilentlyContinue
  if (-not $alive) { Write-Output "process died after resize to $($size[0])x$($size[1])"; break }
}

Start-Sleep -Seconds 1
Get-Process -Id $p.Id -ErrorAction SilentlyContinue | Stop-Process -Force

Write-Output ''
Write-Output '=== log ==='
if (Test-Path $logPath) {
  Get-Content $logPath | Select-String -Pattern 'PANIC|panicked|min > max|at src|at /rustc|par-term::|tab_bar' |
    ForEach-Object { $_.Line } | Select-Object -First 40
} else {
  Write-Output 'no log file'
}
