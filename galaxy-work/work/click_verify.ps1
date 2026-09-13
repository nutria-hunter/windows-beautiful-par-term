# Verify the tab bar's window-control buttons really receive clicks.
#
# The buttons are drawn in the strip, which also doubles as the window drag handle
# (`WM_NCHITTEST` answers HTCAPTION over its empty part). If the reserved width were
# not excluded from that drag region, a click would start a window move instead of
# reaching the button - so a synthetic click on Minimize is the end-to-end proof.
#
# The button centres are detected from the capture rather than computed, so the test
# does not depend on the machine's DPI scale.

$ErrorActionPreference = 'Continue'
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class CC {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint flags, uint dx, uint dy, uint data, UIntPtr extra);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
}
"@
[void][CC]::SetProcessDPIAware()

$LEFTDOWN = 0x0002
$LEFTUP   = 0x0004
$SW_RESTORE = 9

$root = 'C:\Users\jky72\par-term'
$work = "$root\galaxy-work\work"
$shot = "$root\galaxy-work\outputs\clicktest.png"

$proc = Get-Process par-term -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $proc) { Write-Output 'no par-term process'; exit 1 }

$state = @{ area = 0; hwnd = [IntPtr]::Zero }
$cb = {
  param($h, $l)
  $q = 0; [void][CC]::GetWindowThreadProcessId($h, [ref]$q)
  if ($q -ne $proc.Id) { return $true }
  if (-not [CC]::IsWindowVisible($h)) { return $true }
  $r = New-Object CC+RECT; [void][CC]::GetWindowRect($h, [ref]$r)
  $a = ($r.R - $r.L) * ($r.B - $r.T)
  if ($a -gt $state.area) { $state.area = $a; $state.hwnd = $h }
  return $true
}
$del = [CC+EnumProc]$cb
[void][CC]::EnumWindows($del, [IntPtr]::Zero)
$hwnd = $state.hwnd
if ($hwnd -eq [IntPtr]::Zero) { Write-Output 'no par-term window'; exit 1 }

$TOPMOST = [IntPtr](-1)
$NOTOPMOST = [IntPtr](-2)
[void][CC]::SetWindowPos($hwnd, $TOPMOST, 120, 120, 1100, 700, 0x0040)
[void][CC]::SetForegroundWindow($hwnd)
Start-Sleep -Seconds 2

$r = New-Object CC+RECT
[void][CC]::GetWindowRect($hwnd, [ref]$r)
$w = $r.R - $r.L; $h2 = $r.B - $r.T

$bmp = New-Object System.Drawing.Bitmap $w, $h2
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($r.L, $r.T, 0, 0, [System.Drawing.Size]::new($w, $h2))
$g.Dispose()
$bmp.Save($shot, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()

Write-Output "window rect $($r.L),$($r.T) ${w}x${h2}"
Write-Output '=== detected controls ==='
$lines = & python "$work\find_buttons.py" $shot
$lines | ForEach-Object { Write-Output $_ }

$minimize = $lines | Where-Object { $_ -like 'minimize *' }
if (-not $minimize) {
  Write-Output 'RESULT: FAIL - minimize button not found in capture'
  [void][CC]::SetWindowPos($hwnd, $NOTOPMOST, 0, 0, 0, 0, 0x0003)
  exit 1
}
$parts = $minimize -split '\s+'
# image coords -> screen coords (the capture starts at the window origin)
$cx = [int]([double]$parts[1] + $r.L)
$cy = [int]([double]$parts[2] + $r.T)

Write-Output "clicking minimize at screen ($cx,$cy)"
[void][CC]::SetCursorPos($cx, $cy)
Start-Sleep -Milliseconds 400
[CC]::mouse_event($LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero)
Start-Sleep -Milliseconds 90
[CC]::mouse_event($LEFTUP, 0, 0, 0, [UIntPtr]::Zero)
Start-Sleep -Milliseconds 1200

$minimized = [CC]::IsIconic($hwnd)
Write-Output "IsIconic after click = $minimized"
if ($minimized) {
  Write-Output 'RESULT: PASS - the click reached the button instead of starting a window drag'
  [void][CC]::ShowWindow($hwnd, $SW_RESTORE)
  Start-Sleep -Milliseconds 600
} else {
  Write-Output 'RESULT: FAIL - click did not minimize (likely swallowed by the HTCAPTION drag region)'
}
[void][CC]::SetWindowPos($hwnd, $NOTOPMOST, 0, 0, 0, 0, 0x0003)
