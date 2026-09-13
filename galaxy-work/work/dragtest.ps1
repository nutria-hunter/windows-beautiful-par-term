param([int]$Dx = -300, [int]$Dy = 180)
Add-Type @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public class T {
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
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  [StructLayout(LayoutKind.Sequential)] public struct MOUSEINPUT {
    public int dx; public int dy; public uint mouseData; public uint dwFlags; public uint time; public IntPtr dwExtraInfo; }
  [StructLayout(LayoutKind.Sequential)] public struct INPUT { public uint type; public MOUSEINPUT mi; }
  [DllImport("user32.dll")] public static extern uint SendInput(uint n, INPUT[] inputs, int size);
  public const uint MOUSEEVENTF_LEFTDOWN = 0x0002;
  public const uint MOUSEEVENTF_LEFTUP   = 0x0004;
  public static List<IntPtr> ForPid(uint want) {
    var l = new List<IntPtr>();
    EnumWindows((h, x) => { uint p; GetWindowThreadProcessId(h, out p); if (p == want) l.Add(h); return true; }, IntPtr.Zero);
    return l;
  }
  public static void LeftDown() { var a = new INPUT[1]; a[0].type = 0; a[0].mi.dwFlags = MOUSEEVENTF_LEFTDOWN; SendInput(1, a, Marshal.SizeOf(typeof(INPUT))); }
  public static void LeftUp()   { var a = new INPUT[1]; a[0].type = 0; a[0].mi.dwFlags = MOUSEEVENTF_LEFTUP;   SendInput(1, a, Marshal.SizeOf(typeof(INPUT))); }
}
"@

Get-Process par-term -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 800

$helper = Start-Process powershell -PassThru -WindowStyle Hidden -ArgumentList @(
  '-NoProfile','-ExecutionPolicy','Bypass','-File','C:\Users\jky72\par-term\par-term-drag.ps1')
Start-Sleep -Milliseconds 700

$p = Start-Process 'C:\Users\jky72\par-term\par-term.exe' -PassThru -ArgumentList @('--exit-after','30','--log-level','warn')
Start-Sleep -Seconds 6

$t = [IntPtr]::Zero
foreach ($h in [T]::ForPid([uint32]$p.Id)) {
  if (-not [T]::IsWindowVisible($h)) { continue }
  $r = New-Object T+RECT; [void][T]::GetWindowRect($h, [ref]$r)
  if (($r.R-$r.L) -gt 400 -and ($r.B-$r.T) -gt 300) { $t = $h; break }
}
if ($t -eq [IntPtr]::Zero) { Write-Output 'no window'; exit 1 }

[void][T]::SetMenu($t, [IntPtr]::Zero); [void][T]::DrawMenuBar($t)
[void][T]::SetForegroundWindow($t)
Start-Sleep -Seconds 3

$r0 = New-Object T+RECT; [void][T]::GetWindowRect($t, [ref]$r0)
Write-Output "before: L=$($r0.L) T=$($r0.T)  ($($r0.R-$r0.L)x$($r0.B-$r0.T))"

# grab inside the top 6 px band, then drag
$grabX = $r0.L + 120
$grabY = $r0.T + 3
[void][T]::SetCursorPos($grabX, $grabY)
Start-Sleep -Milliseconds 400
[T]::LeftDown()
Start-Sleep -Milliseconds 350
for ($i = 1; $i -le 6; $i++) {
  [void][T]::SetCursorPos($grabX + [int]($Dx * $i / 6), $grabY + [int]($Dy * $i / 6))
  Start-Sleep -Milliseconds 120
}
Start-Sleep -Milliseconds 250
[T]::LeftUp()
Start-Sleep -Seconds 1

$r1 = New-Object T+RECT; [void][T]::GetWindowRect($t, [ref]$r1)
Write-Output "after : L=$($r1.L) T=$($r1.T)"
$movedX = $r1.L - $r0.L
$movedY = $r1.T - $r0.T
Write-Output "delta : dx=$movedX dy=$movedY   (requested dx=$Dx dy=$Dy)"
if ([Math]::Abs($movedX) -gt 50) { Write-Output 'RESULT: DRAG WORKS' } else { Write-Output 'RESULT: window did not move' }

Get-Process par-term, powershell -ErrorAction SilentlyContinue |
  Where-Object { $_.Id -eq $helper.Id -or $_.ProcessName -eq 'par-term' } | Stop-Process -Force
