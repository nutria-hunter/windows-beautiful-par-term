param([int]$LocalX = 500, [int]$LocalY = 12, [int]$Dx = -200, [int]$Dy = 140)
Add-Type @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public class L {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern short GetAsyncKeyState(int vk);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  [StructLayout(LayoutKind.Sequential)] public struct MOUSEINPUT {
    public int dx; public int dy; public uint mouseData; public uint dwFlags; public uint time; public IntPtr dwExtraInfo; }
  [StructLayout(LayoutKind.Sequential)] public struct INPUT { public uint type; public MOUSEINPUT mi; }
  [DllImport("user32.dll")] public static extern uint SendInput(uint n, INPUT[] a, int s);
  public static List<IntPtr> ForPid(uint want) {
    var l = new List<IntPtr>();
    EnumWindows((h, x) => { uint p; GetWindowThreadProcessId(h, out p); if (p == want) l.Add(h); return true; }, IntPtr.Zero);
    return l;
  }
  public static bool Down() { return (GetAsyncKeyState(0x01) & 0x8000) != 0; }
  public static void LDown() { var a = new INPUT[1]; a[0].type = 0; a[0].mi.dwFlags = 0x0002; SendInput(1, a, Marshal.SizeOf(typeof(INPUT))); }
  public static void LUp()   { var a = new INPUT[1]; a[0].type = 0; a[0].mi.dwFlags = 0x0004; SendInput(1, a, Marshal.SizeOf(typeof(INPUT))); }
}
"@

$proc = @(Get-Process par-term -ErrorAction SilentlyContinue)
if ($proc.Count -eq 0) { Write-Output 'par-term not running'; exit 1 }

$t = [IntPtr]::Zero
foreach ($p in $proc) {
  foreach ($h in [L]::ForPid([uint32]$p.Id)) {
    if (-not [L]::IsWindowVisible($h)) { continue }
    $r = New-Object L+RECT; [void][L]::GetWindowRect($h, [ref]$r)
    if (($r.R-$r.L) -gt 300 -and ($r.B-$r.T) -gt 200) { $t = $h; break }
  }
  if ($t -ne [IntPtr]::Zero) { break }
}
if ($t -eq [IntPtr]::Zero) { Write-Output 'no visible par-term window'; exit 1 }

$r0 = New-Object L+RECT; [void][L]::GetWindowRect($t, [ref]$r0)
$w = $r0.R - $r0.L
Write-Output "target hwnd=$t  rect L=$($r0.L) T=$($r0.T) ${w}x$($r0.B-$r0.T)"
Write-Output "grabbing at local ($LocalX, $LocalY); helper region needs LocalX in [240, $($w-110))"

$gx = $r0.L + $LocalX
$gy = $r0.T + $LocalY
[void][L]::SetCursorPos($gx, $gy)
Start-Sleep -Milliseconds 500
[L]::LDown()
Start-Sleep -Milliseconds 150

$iters = 0
while ([L]::Down() -and $iters -lt 60) {
  [void][L]::SetCursorPos($gx + [int]($Dx * $iters / 50), $gy + [int]($Dy * $iters / 50))
  $iters++
  Start-Sleep -Milliseconds 20
}
Start-Sleep -Milliseconds 200
[L]::LUp()
Start-Sleep -Milliseconds 800

$r1 = New-Object L+RECT; [void][L]::GetWindowRect($t, [ref]$r1)
Write-Output "after  L=$($r1.L) T=$($r1.T)   delta=($($r1.L-$r0.L), $($r1.T-$r0.T))"
if ([Math]::Abs($r1.L - $r0.L) -gt 30) {
  Write-Output 'RESULT: live instance drag WORKED (helper is functioning)'
} else {
  Write-Output 'RESULT: live instance did NOT move'
}
