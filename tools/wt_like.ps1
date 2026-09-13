param(
  [string]$Shot = '',
  [int]$Wait = 7,
  [switch]$KeepMenu
)
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
  [DllImport("user32.dll")] public static extern IntPtr GetMenu(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetMenu(IntPtr h, IntPtr m);
  [DllImport("user32.dll")] public static extern bool DrawMenuBar(IntPtr h);
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
$p = Start-Process 'C:\Users\jky72\par-term\par-term.exe' -PassThru -ArgumentList @('--exit-after', '40', '--log-level', 'warn')
Start-Sleep -Seconds $Wait

$target = [IntPtr]::Zero
foreach ($h in [W]::ForPid([uint32]$p.Id)) {
  if (-not [W]::IsWindowVisible($h)) { continue }
  $r = New-Object W+RECT
  [void][W]::GetWindowRect($h, [ref]$r)
  if (($r.R - $r.L) -gt 400 -and ($r.B - $r.T) -gt 300) { $target = $h; break }
}
if ($target -eq [IntPtr]::Zero) { Write-Output 'no window'; exit 1 }

$menu = [W]::GetMenu($target)
Write-Output "hwnd=$target  GetMenu=$menu  (0 means no menu attached)"

if (-not $KeepMenu) {
  [void][W]::SetMenu($target, [IntPtr]::Zero)
  [void][W]::DrawMenuBar($target)
  Start-Sleep -Milliseconds 700
  Write-Output "after SetMenu(NULL): GetMenu=$([W]::GetMenu($target))"
}

[void][W]::SetForegroundWindow($target)
Start-Sleep -Milliseconds 900

if ($Shot -ne '') {
  $r = New-Object W+RECT
  [void][W]::GetWindowRect($target, [ref]$r)
  $pad = 30
  $cw = ($r.R - $r.L) + 2 * $pad
  $ch = ($r.B - $r.T) + 2 * $pad
  $bmp = New-Object System.Drawing.Bitmap $cw, $ch
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen([Math]::Max(0, $r.L - $pad), [Math]::Max(0, $r.T - $pad), 0, 0,
    (New-Object System.Drawing.Size $cw, $ch))
  $g.Dispose()
  $bmp.Save($Shot, [System.Drawing.Imaging.ImageFormat]::Png)
  $bmp.Dispose()
  Write-Output "saved $Shot  (window $($r.R - $r.L)x$($r.B - $r.T) at $($r.L),$($r.T))"
}
Get-Process par-term -ErrorAction SilentlyContinue | Stop-Process -Force
