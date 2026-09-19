# Resize a window to an exact client-ish size so GPU behaviour can be measured at 4K.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File resize_window.ps1 -ProcessName par-term-vulkan -Width 3840 -Height 2160
param(
  [Parameter(Mandatory = $true)][string]$ProcessName,
  [int]$Width = 3840,
  [int]$Height = 2160,
  [int]$TimeoutSeconds = 20
)

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class RW {
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
}
"@
[void][RW]::SetProcessDPIAware()

$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
$proc = $null
while (-not $proc -and (Get-Date) -lt $deadline) {
  $proc = Get-Process $ProcessName -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
  if (-not $proc) { Start-Sleep -Milliseconds 400 }
}
if (-not $proc) { Write-Output "no window for '$ProcessName'"; exit 1 }

# SWP_NOZORDER(4) | SWP_NOACTIVATE(16) keeps focus where it is.
[void][RW]::SetWindowPos($proc.MainWindowHandle, [IntPtr]::Zero, 0, 0, $Width, $Height, 4 -bor 16)
Start-Sleep -Milliseconds 800
$r = New-Object RW+RECT
[void][RW]::GetWindowRect($proc.MainWindowHandle, [ref]$r)
Write-Output ("pid {0}: window now {1}x{2}" -f $proc.Id, ($r.R - $r.L), ($r.B - $r.T))
