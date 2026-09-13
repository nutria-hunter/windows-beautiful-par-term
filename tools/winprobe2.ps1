param([string]$Label = 'probe', [int]$Wait = 6)
Add-Type @"
using System;
using System.Text;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public class W {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h, int i);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowTextW(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr h, int x, int y, int w, int hh, bool r);
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

Get-Process par-term -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 900
$p = Start-Process 'C:\Users\jky72\par-term\par-term.exe' -PassThru -ArgumentList @('--exit-after', '18', '--log-level', 'warn')
Start-Sleep -Seconds $Wait

$shown = 0
foreach ($h in [W]::ForPid([uint32]$p.Id)) {
  if (-not [W]::IsWindowVisible($h)) { continue }
  $sb = New-Object System.Text.StringBuilder 256
  [void][W]::GetWindowTextW($h, $sb, 256)
  $style = [W]::GetWindowLong($h, -16)
  $r = New-Object W+RECT
  [void][W]::GetWindowRect($h, [ref]$r)
  $w0 = $r.R - $r.L; $h0 = $r.B - $r.T
  if ($w0 -lt 200 -or $h0 -lt 200) { continue }
  $shown++
  Write-Output ("[$Label] hwnd={0} title='{1}'" -f $h, $sb.ToString())
  Write-Output ("[$Label]   style=0x{0:X8}  WS_CAPTION(titlebar)={1}  WS_THICKFRAME(resize)={2}  WS_MAXIMIZEBOX={3}" -f `
    $style, ((($style -band 0x00C00000) -ne 0)), ((($style -band 0x00040000) -ne 0)), ((($style -band 0x00010000) -ne 0)))
  [void][W]::MoveWindow($h, $r.L, $r.T, $w0 - 200, $h0 - 120, $true)
  Start-Sleep -Milliseconds 1200
  $r2 = New-Object W+RECT
  [void][W]::GetWindowRect($h, [ref]$r2)
  Write-Output ("[$Label]   size {0}x{1} -> {2}x{3}  resizeAccepted={4}" -f `
    $w0, $h0, ($r2.R - $r2.L), ($r2.B - $r2.T), ((($r2.R - $r2.L) -ne $w0)))
  break
}
if ($shown -eq 0) { Write-Output "[$Label] no visible top-level window found" }
Get-Process par-term -ErrorAction SilentlyContinue | Stop-Process -Force
