$ErrorActionPreference='Continue'
Add-Type -AssemblyName System.Windows.Forms
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class KT {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
}
"@
[void][KT]::SetProcessDPIAware()
$root='C:\Users\jky72\par-term'; $work="$root\galaxy-work\work"; $outs="$root\galaxy-work\outputs"
Get-Process par-term -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 900
$cmd = "python $work\coninput_probe.py keys 25"
$p = Start-Process "$root\par-term.exe" -PassThru -ArgumentList @('--command-to-send', ('"' + $cmd + '"'))
Write-Output "launched pid=$($p.Id) with the key-logging probe"
Start-Sleep -Seconds 4
$state = @{ area=0; hwnd=[IntPtr]::Zero }
$cb = { param($h,$l)
  $q=0; [void][KT]::GetWindowThreadProcessId($h,[ref]$q)
  if ($q -ne $p.Id) { return $true }
  if (-not [KT]::IsWindowVisible($h)) { return $true }
  $state.hwnd = $h; return $true }
$d=[KT+EnumProc]$cb
[void][KT]::EnumWindows($d,[IntPtr]::Zero)
[void][KT]::SetForegroundWindow($state.hwnd)
Start-Sleep -Milliseconds 500
[System.Windows.Forms.SendKeys]::SendWait('abc')
Write-Output "typed 'abc' into the probe"
Start-Sleep -Seconds 6
Get-Process par-term -ErrorAction SilentlyContinue | Stop-Process -Force
Write-Output '=== coninput.log (key records) ==='
if (Test-Path "$outs\coninput.log") { Get-Content "$outs\coninput.log" } else { 'no log' }
