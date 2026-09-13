# Compare what the child is told about its terminal size against what par-term
# believes the grid is, and check whether the child follows window resizes.
#
# Evidence comes from two files rather than a screenshot:
#   outputs\probe.log        - sizes printed by the child itself
#   outputs\diag-parterm.log - par-term's own PTY resize lines at --log-level info

$ErrorActionPreference = 'Continue'
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class DW {
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
[void][DW]::SetProcessDPIAware()

$root   = 'C:\Users\jky72\par-term'
$work   = "$root\galaxy-work\work"
$outs   = "$root\galaxy-work\outputs"
$probe  = "$work\winsize_probe.py"
$cmd    = "$work\run_probe.cmd"
$plog   = "$outs\probe.log"
$plog2  = "$outs\diag-parterm.log"
$shot   = "$outs\diag-shot.png"

Remove-Item $plog, $plog2, $shot -ErrorAction SilentlyContinue

# --command-to-send takes one command string; a .cmd wrapper avoids nested quoting.
Set-Content -Path $cmd -Encoding ascii -Value "@echo off`r`npython `"$probe`" run1"

Get-Process par-term -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 800

$p = Start-Process "$root\par-term.exe" -PassThru `
  -RedirectStandardOutput $plog2 -RedirectStandardError "$plog2.err" `
  -ArgumentList @('--log-level', 'info', '--exit-after', '20', '--screenshot', $shot,
                  '--command-to-send', $cmd)
Write-Output "launched par-term pid=$($p.Id)"

# Let the probe reach the alternate screen, then move the window so the grid has to
# change while the child is on the alt screen - the case where a resize must not be lost.
Start-Sleep -Seconds 6
$hwnd = [IntPtr]::Zero
$state = @{ area = 0; hwnd = [IntPtr]::Zero }
$cb = {
  param($h, $l)
  $q = 0; [void][DW]::GetWindowThreadProcessId($h, [ref]$q)
  if ($q -ne $p.Id) { return $true }
  if (-not [DW]::IsWindowVisible($h)) { return $true }
  $r = New-Object DW+RECT; [void][DW]::GetWindowRect($h, [ref]$r)
  $a = ($r.R - $r.L) * ($r.B - $r.T)
  if ($a -gt $state.area) { $state.area = $a; $state.hwnd = $h }
  return $true
}
$del = [DW+EnumProc]$cb
[void][DW]::EnumWindows($del, [IntPtr]::Zero)
$hwnd = $state.hwnd

if ($hwnd -ne [IntPtr]::Zero) {
  foreach ($size in @(@(900, 560), @(1100, 700), @(820, 520))) {
    [void][DW]::SetWindowPos($hwnd, [IntPtr]::Zero, 90, 90, $size[0], $size[1], 0x0040)
    Start-Sleep -Milliseconds 1200
  }
  Write-Output 'resized window 3x while probe was on the alt screen'
} else {
  Write-Output 'WARNING: par-term window not found; resize test skipped'
}

$p | Wait-Process -Timeout 40 -ErrorAction SilentlyContinue
Get-Process par-term -ErrorAction SilentlyContinue | Stop-Process -Force

Write-Output ''
Write-Output '=== child view (probe.log) ==='
if (Test-Path $plog) { Get-Content $plog } else { Write-Output 'probe.log MISSING' }
Write-Output ''
Write-Output '=== par-term PTY resize lines ==='
if (Test-Path $plog2) {
  Get-Content $plog2 | Select-String -Pattern 'PTY_RESIZE|Resizing terminal to|ALT_SCREEN|resize pulse' |
    ForEach-Object { $_.Line }
} else {
  Write-Output 'diag-parterm.log MISSING'
}
