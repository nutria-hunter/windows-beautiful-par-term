# Does pi's input box appear once the grid is bigger?
#
# Same binary, same command, only the window size differs. If a larger grid reveals
# the input box, pi's layout is simply being pushed off a 24-row screen and the
# missing input is about space, not about key delivery. If the box is still absent,
# the problem is in the drawing/input path instead.

$ErrorActionPreference = 'Continue'
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class BW {
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
[void][BW]::SetProcessDPIAware()

$root = 'C:\Users\jky72\par-term'
$outs = "$root\galaxy-work\outputs"

Get-Process par-term -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 900

$pargs = @('--log-level', 'info', '--command-to-send', '"pi"')
$p = Start-Process "$root\par-term.exe" -PassThru -ArgumentList $pargs
Write-Output "launched par-term pid=$($p.Id) running pi"
Start-Sleep -Seconds 4

$state = @{ area = 0; hwnd = [IntPtr]::Zero }
$cb = {
  param($h, $l)
  $q = 0; [void][BW]::GetWindowThreadProcessId($h, [ref]$q)
  if ($q -ne $p.Id) { return $true }
  if (-not [BW]::IsWindowVisible($h)) { return $true }
  $r = New-Object BW+RECT; [void][BW]::GetWindowRect($h, [ref]$r)
  $a = ($r.R - $r.L) * ($r.B - $r.T)
  if ($a -gt $state.area) { $state.area = $a; $state.hwnd = $h }
  return $true
}
$del = [BW+EnumProc]$cb
[void][BW]::EnumWindows($del, [IntPtr]::Zero)
$hwnd = $state.hwnd
if ($hwnd -eq [IntPtr]::Zero) { Write-Output 'no window'; exit 1 }

# Grow the window so the grid gets far more rows than the 24 it starts with.
[void][BW]::SetWindowPos($hwnd, [IntPtr](-1), 60, 60, 1500, 950, 0x0040)
[void][BW]::SetForegroundWindow($hwnd)
Write-Output 'resized window to 1500x950 and raised it'
Start-Sleep -Seconds 5

$r = New-Object BW+RECT
[void][BW]::GetWindowRect($hwnd, [ref]$r)
$w = $r.R - $r.L; $h2 = $r.B - $r.T
$bmp = New-Object System.Drawing.Bitmap $w, $h2
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($r.L, $r.T, 0, 0, [System.Drawing.Size]::new($w, $h2))
$g.Dispose()
$bmp.Save("$outs\pi-big.png", [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
Write-Output "saved pi-big.png ${w}x${h2}"

Get-Process par-term -ErrorAction SilentlyContinue | Stop-Process -Force
