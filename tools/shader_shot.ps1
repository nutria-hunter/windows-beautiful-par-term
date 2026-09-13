# Launch par-term with a shader, capture the live window (not the --screenshot path), then kill it.
#
# The `--screenshot` route renders a frame on its own terms and came out with a different
# background than the running terminal (corners read as the theme background there). What the
# user is complaining about is the live window, so sample that: make the window topmost, grab
# the screen region, and measure the corners.
#
# Usage: powershell -NoProfile -File shader_shot.ps1 -Out shot.png [-WaitSeconds 8]
param(
    [Parameter(Mandatory)][string]$Out,
    [int]$WaitSeconds = 8,
    [int]$Width = 1300,
    [int]$Height = 900,
    [string]$Exe = 'C:\Users\jky72\par-term\par-term.exe'
)

$ErrorActionPreference = 'Continue'
Add-Type @'
using System;
using System.Runtime.InteropServices;
public class Shot {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
}
'@
[void][Shot]::SetProcessDPIAware()

$proc = Start-Process $Exe -PassThru
Start-Sleep -Seconds 3

$state = @{ area = 0; hwnd = [IntPtr]::Zero }
$cb = {
    param($h, $l)
    $owner = 0; [void][Shot]::GetWindowThreadProcessId($h, [ref]$owner)
    if ($owner -ne $proc.Id -or -not [Shot]::IsWindowVisible($h)) { return $true }
    $r = New-Object Shot+RECT; [void][Shot]::GetWindowRect($h, [ref]$r)
    $a = ($r.R - $r.L) * ($r.B - $r.T)
    if ($a -gt $state.area) { $state.area = $a; $state.hwnd = $h }
    return $true
}
[void][Shot]::EnumWindows([Shot+EnumProc]$cb, [IntPtr]::Zero)
if ($state.hwnd -eq [IntPtr]::Zero) { Write-Output 'no visible window'; exit 1 }

# Topmost + explicit size so the capture cannot come from another window on top.
[void][Shot]::SetWindowPos($state.hwnd, [IntPtr](-1), 80, 80, $Width, $Height, 0x0040)
Start-Sleep -Seconds $WaitSeconds

& python 'C:\Users\jky72\par-term\galaxy-work\work\cap_pid.py' "$($proc.Id)" $Out
Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
Write-Output "captured $Out"
