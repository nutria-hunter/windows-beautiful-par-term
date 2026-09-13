Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class W2 {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
}
"@
$proc = Get-Process par-term -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $proc) { Write-Output 'no par-term process'; exit 1 }
$pid1 = $proc.Id
$state = @{ area = 0; rect = $null; hwnd = [IntPtr]::Zero }
$cb = {
  param($h, $l)
  $p = 0; [void][W2]::GetWindowThreadProcessId($h, [ref]$p)
  if ($p -ne $pid1) { return $true }
  if (-not [W2]::IsWindowVisible($h)) { return $true }
  $r = New-Object W2+RECT; [void][W2]::GetWindowRect($h, [ref]$r)
  $a = ($r.R - $r.L) * ($r.B - $r.T)
  if ($a -gt $state.area) { $state.area = $a; $state.rect = $r; $state.hwnd = $h }
  return $true
}
$del = [W2+EnumProc]$cb
[void][W2]::EnumWindows($del, [IntPtr]::Zero)
if (-not $state.hwnd) { Write-Output 'no window'; exit 1 }

Add-Type -AssemblyName System.Windows.Forms
$b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
Write-Output "screen: $($b.Width)x$($b.Height)"

# move to a fully on-screen position
[void][W2]::SetWindowPos($state.hwnd, [IntPtr]::Zero, 60, 60, 900, 620, 0x0040)
[void][W2]::SetForegroundWindow($state.hwnd)
Start-Sleep -Seconds 3

$r = New-Object W2+RECT
[void][W2]::GetWindowRect($state.hwnd, [ref]$r)
$w = $r.R - $r.L; $h2 = $r.B - $r.T
Write-Output "rect $($r.L),$($r.T) ${w}x${h2}"
$bmp = New-Object System.Drawing.Bitmap $w, $h2
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($r.L, $r.T, 0, 0, (New-Object System.Drawing.Size $w, $h2))
$g.Dispose()
$bmp.Save('C:\Users\jky72\par-term\galaxy-work\outputs\check-now.png', [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
Write-Output 'saved check-now.png'
