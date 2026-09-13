# Does pi's TUI appear when the window only moves (no resize)?
#
# A resize both changes the child's grid and forces par-term to repaint. Moving the
# window keeps the grid identical but still makes par-term redraw, so this separates:
#   * box appears after a move  -> par-term was not repainting (render bug)
#   * box still absent          -> pi is waiting for a child-side size event

$ErrorActionPreference = 'Continue'
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class MV {
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
[void][MV]::SetProcessDPIAware()

$root = 'C:\Users\jky72\par-term'
$outs = "$root\galaxy-work\outputs"

Get-Process par-term -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 900

$p = Start-Process "$root\par-term.exe" -PassThru -ArgumentList @('--log-level', 'info', '--command-to-send', '"pi"')
Write-Output "launched par-term pid=$($p.Id) running pi"
Start-Sleep -Seconds 3

$state = @{ area = 0; hwnd = [IntPtr]::Zero }
$cb = {
  param($h, $l)
  $q = 0; [void][MV]::GetWindowThreadProcessId($h, [ref]$q)
  if ($q -ne $p.Id) { return $true }
  if (-not [MV]::IsWindowVisible($h)) { return $true }
  $r = New-Object MV+RECT; [void][MV]::GetWindowRect($h, [ref]$r)
  $a = ($r.R - $r.L) * ($r.B - $r.T)
  if ($a -gt $state.area) { $state.area = $a; $state.hwnd = $h }
  return $true
}
$del = [MV+EnumProc]$cb
[void][MV]::EnumWindows($del, [IntPtr]::Zero)
$hwnd = $state.hwnd
if ($hwnd -eq [IntPtr]::Zero) { Write-Output 'no window'; exit 1 }

function Shot([string]$path) {
  $r = New-Object MV+RECT
  [void][MV]::GetWindowRect($hwnd, [ref]$r)
  $w = $r.R - $r.L; $h2 = $r.B - $r.T
  $bmp = New-Object System.Drawing.Bitmap $w, $h2
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen($r.L, $r.T, 0, 0, [System.Drawing.Size]::new($w, $h2))
  $g.Dispose()
  $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
  $bmp.Dispose()
  return "$w x $h2"
}

$r = New-Object MV+RECT
[void][MV]::GetWindowRect($hwnd, [ref]$r)
$w = $r.R - $r.L; $h2 = $r.B - $r.T
$SWP = 0x0010  # SWP_NOACTIVATE, no size change: position only
[void][MV]::SetWindowPos($hwnd, [IntPtr](-1), $r.L, $r.T, $w, $h2, $SWP)
[void][MV]::SetForegroundWindow($hwnd)

Start-Sleep -Seconds 14
Write-Output "before move: $(Shot "$outs\pi-move-before.png")"

# Move only: identical size, so the grid (and any child-side size event) is unchanged.
[void][MV]::SetWindowPos($hwnd, [IntPtr](-1), ($r.L + 40), ($r.T + 30), $w, $h2, $SWP)
Write-Output 'window moved 40x30 (size unchanged)'
Start-Sleep -Seconds 4
Write-Output "after move:  $(Shot "$outs\pi-move-after.png")"

Get-Process par-term -ErrorAction SilentlyContinue | Stop-Process -Force
