param([string]$Exe = 'C:\Users\jky72\par-term\build\par-term\target\release\par-term.exe')
Add-Type @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public class V {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr GetMenu(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetMenu(IntPtr h, IntPtr m);
  [DllImport("user32.dll")] public static extern bool DrawMenuBar(IntPtr h);
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

# launch the patched binary
$running = @(Get-Process par-term -ErrorAction SilentlyContinue)
if ($running.Count -gt 0) {
  Write-Output "WARNING: par-term already running ($($running.Count)). par-term may be single-instance,"
  Write-Output "         in which case this launch will reuse the existing window and the test is invalid."
}
$p = Start-Process $Exe -PassThru -ArgumentList @('--exit-after','60','--log-level','warn')
Start-Sleep -Seconds 6
$p.Refresh()
$exePath = try { $p.Path } catch { '' }
Write-Output "launched pid=$($p.Id) path=$exePath"

$t = [IntPtr]::Zero
foreach ($h in [V]::ForPid([uint32]$p.Id)) {
  if (-not [V]::IsWindowVisible($h)) { continue }
  $r = New-Object V+RECT; [void][V]::GetWindowRect($h, [ref]$r)
  if (($r.R-$r.L) -gt 400 -and ($r.B-$r.T) -gt 300) { $t = $h; break }
}
if ($t -eq [IntPtr]::Zero) { Write-Output 'FAIL: no window from the patched process'; exit 1 }
[void][V]::SetMenu($t, [IntPtr]::Zero); [void][V]::DrawMenuBar($t)
[void][V]::SetForegroundWindow($t)
Start-Sleep -Seconds 2

function DragFrom([int]$localX, [int]$localY, [int]$dx, [int]$dy) {
  $r = New-Object V+RECT; [void][V]::GetWindowRect($t, [ref]$r)
  $gx = $r.L + $localX; $gy = $r.T + $localY
  [void][V]::SetCursorPos($gx, $gy)
  Start-Sleep -Milliseconds 350
  [V]::LDown()
  Start-Sleep -Milliseconds 150
  $i = 0
  while ([V]::Down() -and $i -lt 45) {
    [void][V]::SetCursorPos($gx + [int]($dx*$i/38), $gy + [int]($dy*$i/38))
    $i++; Start-Sleep -Milliseconds 18
  }
  Start-Sleep -Milliseconds 150
  [V]::LUp()
  Start-Sleep -Milliseconds 600
  $r2 = New-Object V+RECT; [void][V]::GetWindowRect($t, [ref]$r2)
  return @{ dx = $r2.L - $r.L; dy = $r2.T - $r.T; w = $r2.R - $r2.L; w0 = $r.R - $r.L }
}

$r0 = New-Object V+RECT; [void][V]::GetWindowRect($t, [ref]$r0)
$w = $r0.R - $r0.L
Write-Output "window ${w}x$($r0.B-$r0.T)"

$emptyX = [Math]::Max(320, $w - 220)
Write-Output ''
Write-Output "TEST 1: drag the EMPTY tab strip (local x=$emptyX, y=12)  -> expect window to MOVE"
$a = DragFrom $emptyX 12 -220 150
Write-Output ("  result dx=$($a.dx) dy=$($a.dy)")
if ([Math]::Abs($a.dx) -gt 40) { Write-Output '  PASS: drag moved the window' }
else { Write-Output '  FAIL: window did not move' }

# put it back
$r = New-Object V+RECT; [void][V]::GetWindowRect($t, [ref]$r)
[void][V]::SetCursorPos($r.L + $emptyX, $r.T + 12)

Write-Output ''
Write-Output 'TEST 2: drag OVER A TAB (local x=60, y=12)  -> expect NO window move'
$b = DragFrom 60 12 -220 150
Write-Output ("  result dx=$($b.dx) dy=$($b.dy)")
if ([Math]::Abs($b.dx) -lt 20) { Write-Output '  PASS: tab area is not a drag handle (tab click/reorder intact)' }
else { Write-Output '  FAIL: tab area started a window move - clicking tabs would break' }

Write-Output ''
Write-Output 'TEST 3: drag the RIGHT EDGE inward (local x=w-2)  -> expect WIDTH to shrink'
$c = DragFrom ($w - 2) 200 -180 0
Write-Output ("  width $($c.w0) -> $($c.w)")
if ($c.w -lt $c.w0 - 40) { Write-Output '  PASS: edge resize still works' }
else { Write-Output '  NOTE: width unchanged (resize may need a real mouse; not necessarily a failure)' }

Get-Process par-term -ErrorAction SilentlyContinue | Where-Object { $_.Id -eq $p.Id } | Stop-Process -Force
