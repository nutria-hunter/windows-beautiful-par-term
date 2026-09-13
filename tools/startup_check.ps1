$ErrorActionPreference='Continue'
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class SC {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
}
"@
[void][SC]::SetProcessDPIAware()
Get-Process par-term -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 900
$p = Start-Process 'C:\Users\jky72\par-term\par-term.exe' -PassThru -ArgumentList @('--log-level','info')
foreach ($i in 1..6) {
  Start-Sleep -Seconds 2
  $found = @()
  $cb = { param($h,$l)
    $q=0; [void][SC]::GetWindowThreadProcessId($h,[ref]$q)
    if ($q -ne $p.Id) { return $true }
    $r = New-Object SC+RECT; [void][SC]::GetWindowRect($h,[ref]$r)
    $script:found += [pscustomobject]@{ vis=[SC]::IsWindowVisible($h); icon=[SC]::IsIconic($h); w=($r.R-$r.L); h=($r.B-$r.T) }
    return $true }
  $found = @()
  $d = [SC+EnumProc]$cb
  [void][SC]::EnumWindows($d, [IntPtr]::Zero)
  $p.Refresh()
  $alive = -not $p.HasExited
  Write-Output ("t=$($i*2)s alive=$alive windows=" + (($found | ForEach-Object { "$($_.w)x$($_.h) vis=$($_.vis) iconic=$($_.icon)" }) -join '; '))
}
Write-Output '--- startup log tail ---'
$dl = Join-Path $env:TEMP 'par_term_debug.log'
if (Test-Path $dl) { Get-Content $dl | Select-String -Pattern 'Calculated window size|Resizing terminal to|Tab bar init' | Select-Object -First 8 | ForEach-Object { $_.Line } }
Get-Process par-term -ErrorAction SilentlyContinue | Stop-Process -Force
