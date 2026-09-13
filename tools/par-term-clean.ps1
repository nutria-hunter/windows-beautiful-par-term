# par-term WT-like launcher.
#
# par-term always attaches a native Win32 menu bar on Windows (muda, no config
# toggle), which adds an extra row of chrome above the tab strip. This script
# starts par-term and then detaches ONLY that menu bar with SetMenu(hwnd, NULL),
# leaving the normal title bar (so the window can still be dragged and resized),
# the slim tab strip and the status bar intact.
#
# Usage:  powershell -ExecutionPolicy Bypass -File par-term-clean.ps1
# Point a shortcut / taskbar pin at this file to get it on every launch.

param(
  [string]$Exe = 'C:\Users\jky72\par-term\par-term.exe',
  [int]$PollMs = 700
)

Add-Type @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public class M {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr GetMenu(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetMenu(IntPtr h, IntPtr m);
  [DllImport("user32.dll")] public static extern bool DrawMenuBar(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
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

$already = @(Get-Process par-term -ErrorAction SilentlyContinue).Count
if ($already -eq 0) {
  Start-Process $Exe | Out-Null
  Write-Output 'par-term started'
} else {
  Write-Output "par-term already running ($already process(es)); only stripping menus"
}

$stripped = 0
while ($true) {
  $procs = @(Get-Process par-term -ErrorAction SilentlyContinue)
  if ($procs.Count -eq 0) { break }
  foreach ($p in $procs) {
    foreach ($h in [M]::ForPid([uint32]$p.Id)) {
      if (-not [M]::IsWindowVisible($h)) { continue }
      $r = New-Object M+RECT
      [void][M]::GetWindowRect($h, [ref]$r)
      # skip tiny/utility windows
      if (($r.R - $r.L) -lt 300 -or ($r.B - $r.T) -lt 200) { continue }
      if ([M]::GetMenu($h) -ne [IntPtr]::Zero) {
        [void][M]::SetMenu($h, [IntPtr]::Zero)
        [void][M]::DrawMenuBar($h)
        $stripped++
        Write-Output "stripped menu bar from hwnd $h (pid $($p.Id))"
      }
    }
  }
  Start-Sleep -Milliseconds $PollMs
}
Write-Output "par-term exited; menu bars stripped: $stripped"
