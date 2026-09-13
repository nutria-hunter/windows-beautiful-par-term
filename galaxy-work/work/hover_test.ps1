# Decide whether the tab bar's window controls receive pointer input at all.
#
# The drag region and the buttons are mutually exclusive: `WM_NCHITTEST` answering
# HTCAPTION over a button means Windows routes the click to the non-client area, so
# egui never sees a hover either. The controls therefore brighten and reveal their
# glyph on hover - so hovering is the discriminator between "occluded by the drag
# region" and "egui got the input but the click did nothing".
#
# Reports the pixel at each control centre, with the pointer parked away and then
# parked on the control.

$ErrorActionPreference = 'Continue'
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class HV {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
}
"@
[void][HV]::SetProcessDPIAware()

$root = 'C:\Users\jky72\par-term'
$work = "$root\galaxy-work\work"
$outs = "$root\galaxy-work\outputs"

$proc = Get-Process par-term -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $proc) { Write-Output 'no par-term process'; exit 1 }

$state = @{ area = 0; hwnd = [IntPtr]::Zero }
$cb = {
  param($h, $l)
  $q = 0; [void][HV]::GetWindowThreadProcessId($h, [ref]$q)
  if ($q -ne $proc.Id) { return $true }
  if (-not [HV]::IsWindowVisible($h)) { return $true }
  $r = New-Object HV+RECT; [void][HV]::GetWindowRect($h, [ref]$r)
  $a = ($r.R - $r.L) * ($r.B - $r.T)
  if ($a -gt $state.area) { $state.area = $a; $state.hwnd = $h }
  return $true
}
$del = [HV+EnumProc]$cb
[void][HV]::EnumWindows($del, [IntPtr]::Zero)
$hwnd = $state.hwnd
if ($hwnd -eq [IntPtr]::Zero) { Write-Output 'no par-term window'; exit 1 }

function Capture($path) {
  $r = New-Object HV+RECT
  [void][HV]::GetWindowRect($hwnd, [ref]$r)
  $w = $r.R - $r.L; $h2 = $r.B - $r.T
  $bmp = New-Object System.Drawing.Bitmap $w, $h2
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen($r.L, $r.T, 0, 0, [System.Drawing.Size]::new($w, $h2))
  $g.Dispose()
  $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
  $bmp.Dispose()
  return @{ L = $r.L; T = $r.T; W = $w; H = $h2 }
}

[void][HV]::SetWindowPos($hwnd, [IntPtr](-1), 120, 120, 1100, 700, 0x0040)
[void][HV]::SetForegroundWindow($hwnd)
Start-Sleep -Seconds 2

# Park the pointer away from the strip, then capture the resting state.
[void][HV]::SetCursorPos(640, 700)
Start-Sleep -Milliseconds 900
$geo = Capture "$outs\hover_off.png"
Write-Output "window rect $($geo.L),$($geo.T) $($geo.W)x$($geo.H)"

$centers = & python "$work\find_buttons.py" "$outs\hover_off.png"
Write-Output '=== controls (resting) ==='
$centers | ForEach-Object { Write-Output $_ }

# Park the pointer on the maximize control (the middle one) and capture again.
$max = $centers | Where-Object { $_ -like 'maximize *' }
if (-not $max) { Write-Output 'RESULT: INCONCLUSIVE - maximize not found'; exit 1 }
$parts = $max -split '\s+'
$mx = [int]([double]$parts[1] + $geo.L)
$my = [int]([double]$parts[2] + $geo.T)
[void][HV]::SetCursorPos($mx, $my)
Start-Sleep -Milliseconds 900
Capture "$outs\hover_on.png" | Out-Null
Write-Output "pointer parked on maximize at screen ($mx,$my)"

Write-Output ''
Write-Output '=== pixel at each control centre: resting -> hovered ==='
$offBmp = New-Object System.Drawing.Bitmap "$outs\hover_off.png"
$onBmp = New-Object System.Drawing.Bitmap "$outs\hover_on.png"
foreach ($line in $centers) {
  $p = $line -split '\s+'
  if ($p.Count -lt 3 -or $p[1] -notmatch '^[0-9.]+$') { continue }
  $x = [int][double]$p[1]
  $y = [int][double]$p[2]
  $off = $offBmp.GetPixel($x, $y)
  $on = $onBmp.GetPixel($x, $y)
  Write-Output ("{0,-9} resting=({1},{2},{3})  hovered=({4},{5},{6})" -f $p[0], $off.R, $off.G, $off.B, $on.R, $on.G, $on.B)
}
$offBmp.Dispose()
$onBmp.Dispose()
Write-Output ''
Write-Output 'A darker hovered centre means the glyph was drawn; a brighter fill means the button highlighted.'
