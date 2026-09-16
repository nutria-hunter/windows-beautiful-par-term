# Prove that par-term's shader hot reload reaches a window that is already open.
#
# Launch par-term, capture the live window, change the installed shader, capture again, restore,
# capture a third time. If the middle capture differs from the first and the last matches it
# again, the running window picked the file up on its own — no restart, no shader re-select.
#
# Usage: powershell -NoProfile -File hotreload_probe.ps1 [-Exe PATH] [-Tag hotreload]
param(
    [string]$Exe = 'C:\Users\jky72\par-term\par-term.exe',
    [string]$Tag = 'hotreload',
    [string]$Out = 'C:\Users\jky72\par-term\galaxy-work\outputs',
    [string]$Canonical = 'C:\Users\jky72\par-term\galaxy-work\shaders\kanagawa-starbound.glsl',
    [string]$Installed = "$env:APPDATA\par-term\shaders\kanagawa-starbound.glsl",
    [int]$Width = 1300,
    [int]$Height = 900
)

$ErrorActionPreference = 'Continue'
Add-Type @'
using System;
using System.Runtime.InteropServices;
public class Hr {
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
[void][Hr]::SetProcessDPIAware()

function GrabByPid($pid_, $path) {
    & python 'C:\Users\jky72\par-term\galaxy-work\work\cap_pid.py' "$pid_" $path | Write-Output
}

$proc = Start-Process $Exe -PassThru
Start-Sleep -Seconds 4

$state = @{ area = 0; hwnd = [IntPtr]::Zero }
$cb = {
    param($h, $l)
    $owner = 0; [void][Hr]::GetWindowThreadProcessId($h, [ref]$owner)
    if ($owner -ne $proc.Id -or -not [Hr]::IsWindowVisible($h)) { return $true }
    $r = New-Object Hr+RECT; [void][Hr]::GetWindowRect($h, [ref]$r)
    $a = ($r.R - $r.L) * ($r.B - $r.T)
    if ($a -gt $state.area) { $state.area = $a; $state.hwnd = $h }
    return $true
}
[void][Hr]::EnumWindows([Hr+EnumProc]$cb, [IntPtr]::Zero)
if ($state.hwnd -eq [IntPtr]::Zero) { Write-Output 'FAIL: no visible window'; exit 1 }
# Topmost, so the capture cannot come from another window sitting on top of it.
[void][Hr]::SetWindowPos($state.hwnd, [IntPtr](-1), 80, 80, $Width, $Height, 0x0040)

Start-Sleep -Seconds 5
GrabByPid $proc.Id "$Out\hotreload-$Tag-before.png"

& python 'C:\Users\jky72\par-term\galaxy-work\work\hotreload_edit.py' $Installed $Canonical break
Start-Sleep -Seconds 3   # watcher debounce is 100 ms; 3 s is generous
GrabByPid $proc.Id "$Out\hotreload-$Tag-after.png"

& python 'C:\Users\jky72\par-term\galaxy-work\work\hotreload_edit.py' $Installed $Canonical restore
Start-Sleep -Seconds 3
GrabByPid $proc.Id "$Out\hotreload-$Tag-restored.png"

Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
Write-Output "done: $Out\hotreload-$Tag-{before,after,restored}.png"
