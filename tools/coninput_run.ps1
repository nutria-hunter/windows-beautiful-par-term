# Does the child actually receive console size events in par-term?
#
# Runs coninput_probe.py inside par-term, then resizes the window mid-run so the log
# shows whether ConPTY delivers WINDOW_BUFFER_SIZE_EVENT records at all. If it does
# not, no amount of same-size "pulse" can wake a TUI that waits for one.

$ErrorActionPreference = 'Continue'
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class CI {
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
[void][CI]::SetProcessDPIAware()

$root = 'C:\Users\jky72\par-term'
$work = "$root\galaxy-work\work"
$outs = "$root\galaxy-work\outputs"
$log = "$outs\coninput.log"

Get-Process par-term -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 900
Remove-Item $log -ErrorAction SilentlyContinue

$cmd = "python $work\coninput_probe.py run 30"
$p = Start-Process "$root\par-term.exe" -PassThru -ArgumentList @(
  '--log-level', 'info', '--command-to-send', ('"' + $cmd + '"')
)
Write-Output "launched par-term pid=$($p.Id) running the console-input probe"
Start-Sleep -Seconds 4

$state = @{ area = 0; hwnd = [IntPtr]::Zero }
$cb = {
  param($h, $l)
  $q = 0; [void][CI]::GetWindowThreadProcessId($h, [ref]$q)
  if ($q -ne $p.Id) { return $true }
  if (-not [CI]::IsWindowVisible($h)) { return $true }
  $r = New-Object CI+RECT; [void][CI]::GetWindowRect($h, [ref]$r)
  $a = ($r.R - $r.L) * ($r.B - $r.T)
  if ($a -gt $state.area) { $state.area = $a; $state.hwnd = $h }
  return $true
}
$del = [CI+EnumProc]$cb
[void][CI]::EnumWindows($del, [IntPtr]::Zero)
$hwnd = $state.hwnd
if ($hwnd -eq [IntPtr]::Zero) { Write-Output 'no window'; exit 1 }

$r = New-Object CI+RECT
[void][CI]::GetWindowRect($hwnd, [ref]$r)
$w = $r.R - $r.L; $h2 = $r.B - $r.T

Write-Output "growing window ${w}x${h2} -> $($w + 60)x$($h2 + 40)"
[void][CI]::SetWindowPos($hwnd, [IntPtr]::Zero, 80, 80, ($w + 60), ($h2 + 40), 0x0040)
Start-Sleep -Seconds 6

Write-Output 'shrinking back'
[void][CI]::SetWindowPos($hwnd, [IntPtr]::Zero, 80, 80, $w, $h2, 0x0040)
Start-Sleep -Seconds 24

Get-Process par-term -ErrorAction SilentlyContinue | Stop-Process -Force

Write-Output ''
Write-Output '=== coninput.log ==='
if (Test-Path $log) { Get-Content $log } else { Write-Output 'coninput.log MISSING (probe never ran)' }
