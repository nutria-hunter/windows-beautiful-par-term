Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class DT {
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
[void][DT]::SetProcessDPIAware()

$proc = Get-Process par-term -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $proc) { Write-Output 'no par-term process'; exit 1 }
$pid1 = $proc.Id
$state = @{ area = 0; hwnd = [IntPtr]::Zero }
$cb = {
  param($h, $l)
  $p = 0; [void][DT]::GetWindowThreadProcessId($h, [ref]$p)
  if ($p -ne $pid1) { return $true }
  if (-not [DT]::IsWindowVisible($h)) { return $true }
  $r = New-Object DT+RECT; [void][DT]::GetWindowRect($h, [ref]$r)
  $a = ($r.R - $r.L) * ($r.B - $r.T)
  if ($a -gt $state.area) { $state.area = $a; $state.hwnd = $h }
  return $true
}
$del = [DT+EnumProc]$cb
[void][DT]::EnumWindows($del, [IntPtr]::Zero)
if (-not $state.hwnd) { Write-Output 'no window'; exit 1 }

$TOPMOST = [IntPtr](-1)
$NOTOPMOST = [IntPtr](-2)
[void][DT]::SetWindowPos($state.hwnd, $TOPMOST, 120, 120, 1100, 700, 0x0040)
[void][DT]::SetForegroundWindow($state.hwnd)
Start-Sleep -Seconds 3

$r = New-Object DT+RECT
[void][DT]::GetWindowRect($state.hwnd, [ref]$r)
$w = $r.R - $r.L; $h2 = $r.B - $r.T
Write-Output "window rect (physical) $($r.L),$($r.T) ${w}x${h2}"

# clip to the primary screen so no off-screen black band is captured
$b = [System.Drawing.Bitmap]::new($w, $h2)
$g = [System.Drawing.Graphics]::FromImage($b)
$g.CopyFromScreen($r.L, $r.T, 0, 0, [System.Drawing.Size]::new($w, $h2))
$g.Dispose()
$b.Save('C:\Users\jky72\par-term\galaxy-work\outputs\tabshot.png', [System.Drawing.Imaging.ImageFormat]::Png)
$b.Dispose()
Write-Output 'saved tabshot.png'

[void][DT]::SetWindowPos($state.hwnd, $NOTOPMOST, 0, 0, 0, 0, 0x0003)
