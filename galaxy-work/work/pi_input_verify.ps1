# Verify pi input end to end, avoiding the two ways the earlier attempts misled us:
#   1. typing too early, before pi's TUI exists
#   2. pi showing its "Package Updates Available" notice, which occupies the input area
#
# It waits for the KITTY_KEYBOARD line (proof pi pushed protocol flags) before typing,
# captures before/after, and reports the par-term log lines that matter.

$ErrorActionPreference = 'Continue'
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class IV {
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
[void][IV]::SetProcessDPIAware()

$root = 'C:\Users\jky72\par-term'
$outs = "$root\galaxy-work\outputs"
$debugLog = Join-Path $env:TEMP 'par_term_debug.log'
$typed = 'hello kitty'

Get-Process par-term -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 900
Remove-Item $debugLog, "$outs\input-before.png", "$outs\input-after.png" -ErrorAction SilentlyContinue

$p = Start-Process "$root\par-term.exe" -PassThru -ArgumentList @(
  '--log-level', 'info', '--command-to-send', '"pi"'
)
Write-Output "launched par-term pid=$($p.Id) running pi"
Start-Sleep -Seconds 3

# par-term owns more than one top-level window (a large one plus a tiny helper), so
# pick the largest visible one. Taking the last match selected the 22x22 helper, which
# is why an earlier run reported "window raised at natural size (22x22)".
$state = @{ area = 0; hwnd = [IntPtr]::Zero }
$cb = {
  param($h, $l)
  $q = 0; [void][IV]::GetWindowThreadProcessId($h, [ref]$q)
  if ($q -ne $p.Id) { return $true }
  if (-not [IV]::IsWindowVisible($h)) { return $true }
  $r = New-Object IV+RECT; [void][IV]::GetWindowRect($h, [ref]$r)
  $a = ($r.R - $r.L) * ($r.B - $r.T)
  if ($a -gt $state.area) { $state.area = $a; $state.hwnd = $h }
  return $true
}
$del = [IV+EnumProc]$cb
[void][IV]::EnumWindows($del, [IntPtr]::Zero)
$hwnd = $state.hwnd
if ($hwnd -eq [IntPtr]::Zero) { Write-Output 'no window'; exit 1 }

# Set an explicit size and show the window: reusing whatever rect is read here can
# hand back an unusable size, and a minimized window reports icon dimensions.
[void][IV]::SetWindowPos($hwnd, [IntPtr](-1), 100, 100, 1300, 900, 0x0040)
Start-Sleep -Milliseconds 900
$r1 = New-Object IV+RECT
[void][IV]::GetWindowRect($hwnd, [ref]$r1)
Write-Output "window shown at ($($r1.L),$($r1.T)) $($r1.R - $r1.L)x$($r1.B - $r1.T)"

# Wait for pi to push keyboard-protocol flags: that is the point where its TUI is up.
$deadline = (Get-Date).AddSeconds(75)
$flagsSeen = $false
while ((Get-Date) -lt $deadline) {
  Start-Sleep -Seconds 3
  if ((Test-Path $debugLog) -and (Select-String -Path $debugLog -Pattern 'KITTY_KEYBOARD' -Quiet)) {
    $flagsSeen = $true
    break
  }
}
if ($flagsSeen) {
  Write-Output 'pi pushed keyboard-protocol flags:'
  Select-String -Path $debugLog -Pattern 'KITTY_KEYBOARD' | Select-Object -First 5 |
    ForEach-Object { Write-Output ("  " + $_.Line) }
} else {
  Write-Output 'no KITTY_KEYBOARD line within 75s (pi may not use the protocol) - typing anyway'
}
Start-Sleep -Seconds 4

function Shot([string]$path) {
  $r = New-Object IV+RECT
  [void][IV]::GetWindowRect($hwnd, [ref]$r)
  $w = $r.R - $r.L; $h2 = $r.B - $r.T
  $bmp = New-Object System.Drawing.Bitmap $w, $h2
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen($r.L, $r.T, 0, 0, [System.Drawing.Size]::new($w, $h2))
  $g.Dispose()
  $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
  $bmp.Dispose()
}

Shot "$outs\input-before.png"
Write-Output 'captured input-before.png'
[void][IV]::SetForegroundWindow($hwnd)
Start-Sleep -Milliseconds 500
[System.Windows.Forms.SendKeys]::SendWait($typed)
Write-Output "typed '$typed'"
Start-Sleep -Seconds 3
Shot "$outs\input-after.png"
Write-Output 'captured input-after.png'

Get-Process par-term -ErrorAction SilentlyContinue | Stop-Process -Force
Write-Output ''
Write-Output '=== resize / surface lines (context) ==='
if (Test-Path $debugLog) {
  Get-Content $debugLog | Select-String -Pattern 'Resizing terminal to|Configuring surface' |
    Select-Object -First 12 | ForEach-Object { $_.Line }
}
