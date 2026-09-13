$ErrorActionPreference='Continue'
Add-Type -AssemblyName System.Windows.Forms
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class VK {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
}
"@
[void][VK]::SetProcessDPIAware()
$root='C:\Users\jky72\par-term'; $work="$root\galaxy-work\work"; $outs="$root\galaxy-work\outputs"
Get-Process par-term -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 900
$cmd = "python $work\vtinput_probe.py 20"
$p = Start-Process "$root\par-term.exe" -PassThru -ArgumentList @('--command-to-send', ('"' + $cmd + '"'))
Write-Output "launched pid=$($p.Id) with the VT-input probe"
Start-Sleep -Seconds 5
$state = @{ hwnd=[IntPtr]::Zero }
$cb = { param($h,$l)
  $q=0; [void][VK]::GetWindowThreadProcessId($h,[ref]$q)
  if ($q -ne $p.Id) { return $true }
  if (-not [VK]::IsWindowVisible($h)) { return $true }
  $state.hwnd = $h; return $true }
$d=[VK+EnumProc]$cb
[void][VK]::EnumWindows($d,[IntPtr]::Zero)
[void][VK]::SetForegroundWindow($state.hwnd)
Start-Sleep -Milliseconds 600
[System.Windows.Forms.SendKeys]::SendWait('abc')
Write-Output "typed 'abc'"
Start-Sleep -Seconds 3
[System.Windows.Forms.SendKeys]::SendWait('{ENTER}')
Write-Output "sent Enter"
Start-Sleep -Seconds 6
Get-Process par-term -ErrorAction SilentlyContinue | Stop-Process -Force
Write-Output '=== vtinput.log ==='
if (Test-Path "$outs\vtinput.log") { Get-Content "$outs\vtinput.log" } else { 'no log' }
