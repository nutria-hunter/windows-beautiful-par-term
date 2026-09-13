# Does minimizing the window crash par-term?
#
# Run against a chosen binary so the same test can be pointed at the official build:
# that separates a bug this work introduced from a pre-existing one.

param(
  [string]$Exe = 'C:\Users\jky72\par-term\par-term.exe',
  [string]$Label = 'current'
)

$ErrorActionPreference = 'Continue'
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class MT {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
}
"@
[void][MT]::SetProcessDPIAware()

$SW_MINIMIZE = 6
$SW_RESTORE = 9
$logPath = Join-Path $env:TEMP 'par_term_debug.log'

Get-Process par-term -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 800
Remove-Item $logPath -ErrorAction SilentlyContinue

$p = Start-Process $Exe -PassThru
Start-Sleep -Seconds 6
Write-Output "[$Label] launched pid=$($p.Id)"

$state = @{ area = 0; hwnd = [IntPtr]::Zero }
$cb = {
  param($h, $l)
  $q = 0; [void][MT]::GetWindowThreadProcessId($h, [ref]$q)
  if ($q -ne $p.Id) { return $true }
  if (-not [MT]::IsWindowVisible($h)) { return $true }
  $r = New-Object MT+RECT; [void][MT]::GetWindowRect($h, [ref]$r)
  $a = ($r.R - $r.L) * ($r.B - $r.T)
  if ($a -gt $state.area) { $state.area = $a; $state.hwnd = $h }
  return $true
}
$del = [MT+EnumProc]$cb
[void][MT]::EnumWindows($del, [IntPtr]::Zero)
$hwnd = $state.hwnd
if ($hwnd -eq [IntPtr]::Zero) { Write-Output "[$Label] no window"; exit 1 }

[void][MT]::ShowWindow($hwnd, $SW_MINIMIZE)
Start-Sleep -Milliseconds 1500
$iconic = [MT]::IsIconic($hwnd)
$alive = [bool](Get-Process -Id $p.Id -ErrorAction SilentlyContinue)
Write-Output "[$Label] after minimize: IsIconic=$iconic processAlive=$alive"

if ($alive) {
  [void][MT]::ShowWindow($hwnd, $SW_RESTORE)
  Start-Sleep -Milliseconds 800
  $alive2 = [bool](Get-Process -Id $p.Id -ErrorAction SilentlyContinue)
  Write-Output "[$Label] after restore: processAlive=$alive2"
}

if (Test-Path $logPath) {
  $panics = Get-Content $logPath | Select-String -Pattern 'PANIC' | ForEach-Object { $_.Line }
  if ($panics) { $panics | ForEach-Object { Write-Output "  $_" } }
  else { Write-Output "[$Label] no panic logged" }
  Remove-Item $logPath -ErrorAction SilentlyContinue
}

Get-Process -Id $p.Id -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 500
