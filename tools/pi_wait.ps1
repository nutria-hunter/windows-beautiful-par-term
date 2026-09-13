# Give pi time to finish starting up, then look for its input box.
#
# The earlier captures were taken ~21s in, right as pi printed "Session backfill
# complete" - so they may have caught pi mid-startup rather than its settled TUI.
# This waits much longer and captures the live window instead of relying on
# par-term's own screenshot timer.

$ErrorActionPreference = 'Continue'
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class PW {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
}
"@
[void][PW]::SetProcessDPIAware()

$root = 'C:\Users\jky72\par-term'
$outs = "$root\galaxy-work\outputs"

Get-Process par-term -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 900

$pargs = @('--log-level', 'info', '--command-to-send', '"pi"')
$p = Start-Process "$root\par-term.exe" -PassThru -ArgumentList $pargs
Write-Output "launched par-term pid=$($p.Id) running pi"
Start-Sleep -Seconds 3

$state = @{ area = 0; hwnd = [IntPtr]::Zero }
$cb = {
  param($h, $l)
  $q = 0; [void][PW]::GetWindowThreadProcessId($h, [ref]$q)
  if ($q -ne $p.Id) { return $true }
  if (-not [PW]::IsWindowVisible($h)) { return $true }
  $r = New-Object PW+RECT; [void][PW]::GetWindowRect($h, [ref]$r)
  $a = ($r.R - $r.L) * ($r.B - $r.T)
  if ($a -gt $state.area) { $state.area = $a; $state.hwnd = $h }
  return $true
}
$del = [PW+EnumProc]$cb
[void][PW]::EnumWindows($del, [IntPtr]::Zero)
$hwnd = $state.hwnd
if ($hwnd -eq [IntPtr]::Zero) { Write-Output 'no window'; exit 1 }

[void][PW]::SetForegroundWindow($hwnd)

# Deliberately no resize: the earlier run that DID show the input box also resized
# the window, which forces pi to repaint. Opening at the configured size and leaving
# it alone isolates "pi never gets there" from "pi repaints when nudged".
$r0 = New-Object PW+RECT
[void][PW]::GetWindowRect($hwnd, [ref]$r0)
[void][PW]::SetWindowPos($hwnd, [IntPtr](-1), $r0.L, $r0.T, ($r0.R - $r0.L), ($r0.B - $r0.T), 0x0010)
Write-Output "window left at its natural size $($r0.R - $r0.L)x$($r0.B - $r0.T)"

foreach ($wait in @(15, 35, 60)) {
  Start-Sleep -Seconds 15
  $r = New-Object PW+RECT
  [void][PW]::GetWindowRect($hwnd, [ref]$r)
  $w = $r.R - $r.L; $h2 = $r.B - $r.T
  $bmp = New-Object System.Drawing.Bitmap $w, $h2
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen($r.L, $r.T, 0, 0, [System.Drawing.Size]::new($w, $h2))
  $g.Dispose()
  $path = "$outs\pi-wait-$wait.png"
  $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
  $bmp.Dispose()
  $p.Refresh()
  Write-Output "t=${wait}s saved pi-wait-$wait.png (${w}x${h2}, alive=$(-not $p.HasExited))"
}

Get-Process par-term -ErrorAction SilentlyContinue | Stop-Process -Force
