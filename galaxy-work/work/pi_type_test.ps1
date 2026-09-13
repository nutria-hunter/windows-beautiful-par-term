# End-to-end input test: type into pi's chat bar and see whether the text appears.
#
# The chat bar being visible only proves the layout fits; it says nothing about key
# delivery. This types real keystrokes through the OS (so they travel the same path
# as the user's) and captures what the window shows afterwards.

$ErrorActionPreference = 'Continue'
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class TY {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
}
"@
[void][TY]::SetProcessDPIAware()

$root = 'C:\Users\jky72\par-term'
$outs = "$root\galaxy-work\outputs"
$typed = 'hello par-term'

Get-Process par-term -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 900

$p = Start-Process "$root\par-term.exe" -PassThru -ArgumentList @('--command-to-send', '"pi"')
Write-Output "launched par-term pid=$($p.Id) running pi"
Start-Sleep -Seconds 3

$state = @{ area = 0; hwnd = [IntPtr]::Zero }
$cb = {
  param($h, $l)
  $q = 0; [void][TY]::GetWindowThreadProcessId($h, [ref]$q)
  if ($q -ne $p.Id) { return $true }
  if (-not [TY]::IsWindowVisible($h)) { return $true }
  $r = New-Object TY+RECT; [void][TY]::GetWindowRect($h, [ref]$r)
  $a = ($r.R - $r.L) * ($r.B - $r.T)
  if ($a -gt $state.area) { $state.area = $a; $state.hwnd = $h }
  return $true
}
$del = [TY+EnumProc]$cb
[void][TY]::EnumWindows($del, [IntPtr]::Zero)
$hwnd = $state.hwnd
if ($hwnd -eq [IntPtr]::Zero) { Write-Output 'no window'; exit 1 }

# Raise without resizing: the size must stay untouched so this tests input only.
$r0 = New-Object TY+RECT
[void][TY]::GetWindowRect($hwnd, [ref]$r0)
[void][TY]::SetWindowPos($hwnd, [IntPtr](-1), $r0.L, $r0.T, ($r0.R - $r0.L), ($r0.B - $r0.T), 0x0010)
[void][TY]::SetForegroundWindow($hwnd)
Write-Output "window raised, size untouched ($($r0.R - $r0.L)x$($r0.B - $r0.T))"

# Give pi time to finish starting so its chat bar exists before typing. Startup is
# slow: backfill plus an extension update check, and the chat bar only appears once
# the startup report has finished printing.
Start-Sleep -Seconds 60

function Shot([string]$path) {
  $r = New-Object TY+RECT
  [void][TY]::GetWindowRect($hwnd, [ref]$r)
  $w = $r.R - $r.L; $h2 = $r.B - $r.T
  $bmp = New-Object System.Drawing.Bitmap $w, $h2
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen($r.L, $r.T, 0, 0, [System.Drawing.Size]::new($w, $h2))
  $g.Dispose()
  $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
  $bmp.Dispose()
  return "$w x $h2"
}

Write-Output "before typing: $(Shot "$outs\type-before.png")"

[void][TY]::SetForegroundWindow($hwnd)
Start-Sleep -Milliseconds 400
[System.Windows.Forms.SendKeys]::SendWait($typed)
Write-Output "typed: '$typed'"
Start-Sleep -Seconds 3
Write-Output "after typing:  $(Shot "$outs\type-after.png")"

Get-Process par-term -ErrorAction SilentlyContinue | Stop-Process -Force
