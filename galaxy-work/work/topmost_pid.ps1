# Raise (or restore) the largest visible window of a PID, so a screen-region capture cannot come
# from whatever happens to be sitting on top of it.
#
# Usage: powershell -NoProfile -File topmost_pid.ps1 -ProcessId 1234 -Mode set|clear
param(
    [Parameter(Mandatory)][int]$ProcessId,
    [Parameter(Mandatory)][string]$Mode
)

$ErrorActionPreference = 'Continue'
Add-Type @'
using System;
using System.Runtime.InteropServices;
public class Tm {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
}
'@

$state = @{ area = 0; hwnd = [IntPtr]::Zero }
$cb = {
    param($h, $l)
    $owner = 0; [void][Tm]::GetWindowThreadProcessId($h, [ref]$owner)
    if ($owner -ne $ProcessId -or -not [Tm]::IsWindowVisible($h)) { return $true }
    $r = New-Object Tm+RECT; [void][Tm]::GetWindowRect($h, [ref]$r)
    $a = ($r.R - $r.L) * ($r.B - $r.T)
    if ($a -gt $state.area) { $state.area = $a; $state.hwnd = $h }
    return $true
}
[void][Tm]::EnumWindows([Tm+EnumProc]$cb, [IntPtr]::Zero)
if ($state.hwnd -eq [IntPtr]::Zero) { Write-Output 'FAIL: no visible window for that pid'; exit 1 }

# HWND_TOPMOST / HWND_NOTOPMOST, without moving, resizing or activating the window.
$after = if ($Mode -eq 'set') { [IntPtr](-1) } else { [IntPtr](-2) }
[void][Tm]::SetWindowPos($state.hwnd, $after, 0, 0, 0, 0, 0x0013)
Write-Output "window $($state.hwnd) $Mode"
