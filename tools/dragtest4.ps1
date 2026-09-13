param([int]$Dx = -300, [int]$Dy = 180)
Add-Type @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public class M {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr GetMenu(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetMenu(IntPtr h, IntPtr m);
  [DllImport("user32.dll")] public static extern bool DrawMenuBar(IntPtr h);
  [DllImport("user32.dll")] public static extern short GetAsyncKeyState(int vk);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
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

Get-Process par-term -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 900

$helperPath = Join-Path (Split-Path -Parent $PSScriptRoot) '..\par-term-drag.ps1'
$helperPath = 'C:\Users\jky72\par-term\par-term-drag.ps1'
$log = 'C:\Users\jky72\par-term\galaxy-work\outputs\drag-helper.log'
if (Test-Path $log) { Remove-Item $log -Force }
$helper = Start-Process powershell -PassThru -WindowStyle Hidden -RedirectStandardOutput $log -ArgumentList @(
  '-NoProfile','-ExecutionPolicy','Bypass','-File',$helperPath)
Start-Sleep -Milliseconds 900

$p = Start-Process 'C:\Users\jky72\par-term\par-term.exe' -PassThru -ArgumentList @('--exit-after','40','--log-level','warn')
Start-Sleep -Seconds 6

$t = [IntPtr]::Zero
foreach ($h in [M]::ForPid([uint32]$p.Id)) {
  if (-not [M]::IsWindowVisible($h)) { continue }
  $r = New-Object M+RECT; [void][M]::GetWindowRect($h, [ref]$r)
  if (($r.R-$r.L) -gt 400 -and ($r.B-$r.T) -gt 300) { $t = $h; break }
}
if ($t -eq [IntPtr]::Zero) { Write-Output 'no window'; exit 1 }
[void][M]::SetMenu($t, [IntPtr]::Zero); [void][M]::DrawMenuBar($t)
[void][M]::SetForegroundWindow($t)
Start-Sleep -Seconds 3

$r0 = New-Object M+RECT; [void][M]::GetWindowRect($t, [ref]$r0)
$w = $r0.R - $r0.L
Write-Output "window ${w}x$($r0.B-$r0.T) at L=$($r0.L) T=$($r0.T)"

# grab the empty part of the tab strip (local x = 450), not a tab and not the buttons
$gx = $r0.L + 450
$gy = $r0.T + 12
[void][M]::SetCursorPos($gx, $gy)
Start-Sleep -Milliseconds 500
[M]::LDown()
Start-Sleep -Milliseconds 150

$iters = 0
while ([M]::Down() -and $iters -lt 60) {
  [void][M]::SetCursorPos($gx + [int]($Dx * $iters / 50), $gy + [int]($Dy * $iters / 50))
  $iters++
  Start-Sleep -Milliseconds 20
}
Start-Sleep -Milliseconds 200
[M]::LUp()
Start-Sleep -Seconds 1

$r1 = New-Object M+RECT; [void][M]::GetWindowRect($t, [ref]$r1)
$dx = $r1.L - $r0.L
$dy = $r1.T - $r0.T
Write-Output "after  L=$($r1.L) T=$($r1.T)   delta=($dx, $dy)"
if ([Math]::Abs($dx) -gt 40) { Write-Output 'RESULT: helper drag WORKS' } else { Write-Output 'RESULT: no movement' }

Write-Output '--- helper log ---'
if (Test-Path $log) { Get-Content $log | Select-Object -First 12 } else { Write-Output '(none)' }

Get-Process par-term -ErrorAction SilentlyContinue | Stop-Process -Force
Stop-Process -Id $helper.Id -Force -ErrorAction SilentlyContinue
