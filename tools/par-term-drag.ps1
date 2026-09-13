# par-term drag helper -- gives the borderless window a WezTerm-style drag handle.
#
# Why this exists
# ---------------
# WezTerm solves this inside its own window procedure: it handles WM_NCCALCSIZE and
# WM_NCHITTEST so the empty area of its tab bar behaves like a native title bar
# (wezterm PR #1675 / #1677), and its `window_decorations = "RESIZE"` mode drops
# the title bar while keeping the resizable border. par-term has none of that, so
# this helper does the equivalent from OUTSIDE the process.
#
# How it works
# ------------
# The obvious approach -- ReleaseCapture() + WM_NCLBUTTONDOWN/HTCAPTION to hand the
# window to the OS modal move loop -- was tried first and does NOT work here: winit
# never lets that message reach DefWindowProc, so no move loop starts (verified).
# Instead this helper moves the window directly with SetWindowPos, which is a plain
# API and works across process boundaries with no injection.
#
# Where you can grab
# ------------------
#   * the empty part of the tab strip (top strip, right of the tabs, left of the
#     + / v buttons)  -- like WezTerm's empty tab bar area
#   * Alt + left-drag anywhere in the window  -- always safe
#
# Usage: powershell -ExecutionPolicy Bypass -File par-term-drag.ps1

param(
  [int]$PollMs = 10,
  [int]$TopStripPx = 26,      # tab bar height (config: tab_bar_height)
  [int]$EmptyFromPx = 240,    # tabs occupy roughly this much from the left
  [int]$RightGuardPx = 110,   # + and v buttons live here
  [int]$MinWidth = 300,
  [int]$MinHeight = 200,
  [switch]$NoAlt
)

Add-Type @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public class Drag {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
  [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(POINT p);
  [DllImport("user32.dll")] public static extern IntPtr GetAncestor(IntPtr h, uint f);
  [DllImport("user32.dll")] public static extern short GetAsyncKeyState(int vk);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint f);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }

  public const int VK_LBUTTON = 0x01;
  public const int VK_MENU = 0x12;
  public const uint GA_ROOT = 2;
  public const uint SWP_NOSIZE = 0x0001;
  public const uint SWP_NOZORDER = 0x0004;
  public const uint SWP_NOACTIVATE = 0x0010;

  public static List<IntPtr> ForPid(uint want) {
    var l = new List<IntPtr>();
    EnumWindows((h, x) => { uint p; GetWindowThreadProcessId(h, out p); if (p == want) l.Add(h); return true; }, IntPtr.Zero);
    return l;
  }
  public static bool Down(int vk) { return (GetAsyncKeyState(vk) & 0x8000) != 0; }
  public static IntPtr RootUnderCursor() { POINT p; GetCursorPos(out p); return GetAncestor(WindowFromPoint(p), GA_ROOT); }
  public static void MoveTo(IntPtr h, int x, int y) {
    SetWindowPos(h, IntPtr.Zero, x, y, 0, 0, SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);
  }
}
"@

Write-Output ("par-term drag helper: grab the empty part of the tab strip" +
  $(if ($NoAlt) { '' } else { ', or Alt+drag anywhere' }) + ".")

$wasDown = $false
$moves = 0
while ($true) {
  $targets = @()
  foreach ($proc in @(Get-Process par-term -ErrorAction SilentlyContinue)) {
    foreach ($h in [Drag]::ForPid([uint32]$proc.Id)) {
      if ([Drag]::IsWindowVisible($h)) { $targets += $h }
    }
  }
  if ($targets.Count -eq 0) { Start-Sleep -Milliseconds 400; continue }

  $down = [Drag]::Down([Drag]::VK_LBUTTON)
  if ($down -and -not $wasDown) {
    $root = [Drag]::RootUnderCursor()
    if ($targets -contains $root) {
      $r = New-Object Drag+RECT
      [void][Drag]::GetWindowRect($root, [ref]$r)
      $w = $r.R - $r.L
      $hh = $r.B - $r.T
      $pt = New-Object Drag+POINT
      [void][Drag]::GetCursorPos([ref]$pt)
      $localX = $pt.X - $r.L
      $localY = $pt.Y - $r.T
      $inStrip = ($localY -ge 0 -and $localY -lt $TopStripPx -and
                  $localX -ge $EmptyFromPx -and $localX -lt ($w - $RightGuardPx))
      $altGrab = (-not $NoAlt) -and [Drag]::Down([Drag]::VK_MENU)
      if ($w -ge $MinWidth -and $hh -ge $MinHeight -and ($inStrip -or $altGrab)) {
        $startX = $pt.X
        $startY = $pt.Y
        $baseX = $r.L
        $baseY = $r.T
        # drag until the button is released
        while ([Drag]::Down([Drag]::VK_LBUTTON)) {
          $c = New-Object Drag+POINT
          [void][Drag]::GetCursorPos([ref]$c)
          [Drag]::MoveTo($root, $baseX + ($c.X - $startX), $baseY + ($c.Y - $startY))
          Start-Sleep -Milliseconds 8
        }
        $moves++
        Write-Output ("move #{0} ({1})" -f $moves, $(if ($inStrip) { 'tab strip' } else { 'alt' }))
      }
    }
  }
  $wasDown = $down
  Start-Sleep -Milliseconds $PollMs
}
