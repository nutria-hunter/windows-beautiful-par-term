param([string]$Out = 'C:\Users\jky72\par-term\galaxy-work\outputs\window-shot.png', [int]$Wait = 7)
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public class W {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  public static List<IntPtr> ForPid(uint want) {
    var list = new List<IntPtr>();
    EnumWindows((h, l) => {
      uint pid; GetWindowThreadProcessId(h, out pid);
      if (pid == want) list.Add(h);
      return true;
    }, IntPtr.Zero);
    return list;
  }
}
"@

Get-Process par-term -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 900
$p = Start-Process 'C:\Users\jky72\par-term\par-term.exe' -PassThru -ArgumentList @('--exit-after', '25', '--log-level', 'warn')
Start-Sleep -Seconds $Wait

$target = [IntPtr]::Zero
foreach ($h in [W]::ForPid([uint32]$p.Id)) {
  if (-not [W]::IsWindowVisible($h)) { continue }
  $r = New-Object W+RECT
  [void][W]::GetWindowRect($h, [ref]$r)
  if (($r.R - $r.L) -gt 400 -and ($r.B - $r.T) -gt 300) { $target = $h; break }
}
if ($target -eq [IntPtr]::Zero) { Write-Output 'no window'; exit 1 }

[void][W]::SetForegroundWindow($target)
Start-Sleep -Milliseconds 900

$r = New-Object W+RECT
[void][W]::GetWindowRect($target, [ref]$r)
$w = $r.R - $r.L
$h2 = $r.B - $r.T
Write-Output "capturing window rect ($($r.L),$($r.T)) ${w}x${h2}"

# include a margin above/around so any title bar or shadow is visible
$pad = 40
$x0 = [Math]::Max(0, $r.L - $pad)
$y0 = [Math]::Max(0, $r.T - $pad)
$cw = $w + 2 * $pad
$ch = $h2 + 2 * $pad
$bmp = New-Object System.Drawing.Bitmap $cw, $ch
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($x0, $y0, 0, 0, (New-Object System.Drawing.Size $cw, $ch))
$g.Dispose()
$bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
Write-Output "saved $Out"
Get-Process par-term -ErrorAction SilentlyContinue | Stop-Process -Force
