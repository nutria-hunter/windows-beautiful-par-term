Add-Type @"
using System;
using System.Runtime.InteropServices;
public class U {
  [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h, int i);
  [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr h, int x, int y, int w, int hh, bool r);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
}
"@

$p = Start-Process 'C:\Users\jky72\par-term\par-term.exe' -PassThru -ArgumentList @('--exit-after', '22', '--log-level', 'warn')
Start-Sleep -Seconds 6
$p.Refresh()
$h = $p.MainWindowHandle
Write-Output "pid=$($p.Id)  hwnd=$h"

$style = [U]::GetWindowLong($h, -16)
Write-Output ("style = 0x{0:X8}" -f $style)
Write-Output ("  WS_THICKFRAME  (drag-to-resize border) = {0}" -f ((($style -band 0x00040000) -ne 0)))
Write-Output ("  WS_CAPTION     (title bar)             = {0}" -f ((($style -band 0x00C00000) -ne 0)))
Write-Output ("  WS_MAXIMIZEBOX (maximize button)       = {0}" -f ((($style -band 0x00010000) -ne 0)))
Write-Output ("  WS_SIZEBOX == WS_THICKFRAME            = {0}" -f ((($style -band 0x00040000) -ne 0)))

$ex = [U]::GetWindowLong($h, -20)
Write-Output ("exstyle = 0x{0:X8}   WS_EX_LAYERED = {1}" -f $ex, (($ex -band 0x00080000) -ne 0))

$r = New-Object U+RECT
[void][U]::GetWindowRect($h, [ref]$r)
$w0 = $r.R - $r.L; $h0 = $r.B - $r.T
Write-Output "before: ${w0} x ${h0}"

[void][U]::MoveWindow($h, $r.L, $r.T, $w0 - 240, $h0 - 160, $true)
Start-Sleep -Milliseconds 1500
$r2 = New-Object U+RECT
[void][U]::GetWindowRect($h, [ref]$r2)
$w1 = $r2.R - $r2.L; $h1 = $r2.B - $r2.T
Write-Output "after MoveWindow(-240,-160): ${w1} x ${h1}   -> accepted=$($w1 -ne $w0)"
