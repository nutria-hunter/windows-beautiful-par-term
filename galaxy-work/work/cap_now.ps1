Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class W {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
}
"@
$proc = Get-Process par-term -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $proc) { Write-Output 'no par-term process'; exit 1 }
$pid1 = $proc.Id
$state = @{ area = 0; rect = $null }
$cb = {
  param($h, $l)
  $p = 0; [void][W]::GetWindowThreadProcessId($h, [ref]$p)
  if ($p -ne $pid1) { return $true }
  if (-not [W]::IsWindowVisible($h)) { return $true }
  $r = New-Object W+RECT; [void][W]::GetWindowRect($h, [ref]$r)
  $a = ($r.R - $r.L) * ($r.B - $r.T)
  if ($a -gt $state.area) { $state.area = $a; $state.rect = $r }
  return $true
}
$del = [W+EnumProc]$cb
[void][W]::EnumWindows($del, [IntPtr]::Zero)
if (-not $state.rect) { Write-Output 'no window'; exit 1 }
$r = $state.rect
$w = $r.R - $r.L; $h2 = $r.B - $r.T
Write-Output "rect $($r.L),$($r.T) ${w}x${h2}"
$bmp = New-Object System.Drawing.Bitmap $w, $h2
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($r.L, $r.T, 0, 0, (New-Object System.Drawing.Size $w, $h2))
$g.Dispose()
$bmp.Save('C:\Users\jky72\par-term\galaxy-work\outputs\check-now.png', [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
Write-Output 'saved check-now.png'
