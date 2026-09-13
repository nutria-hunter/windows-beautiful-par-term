param([string]$Shot='', [int]$Wait=8)
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System; using System.Collections.Generic; using System.Runtime.InteropServices;
public class F {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr GetMenu(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetMenu(IntPtr h, IntPtr m);
  [DllImport("user32.dll")] public static extern bool DrawMenuBar(IntPtr h);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  public static List<IntPtr> ForPid(uint w) {
    var l = new List<IntPtr>();
    EnumWindows((h, x) => { uint p; GetWindowThreadProcessId(h, out p); if (p == w) l.Add(h); return true; }, IntPtr.Zero);
    return l;
  }
}
"@
Get-Process par-term -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 900
$p = Start-Process 'C:\Users\jky72\par-term\par-term.exe' -PassThru -ArgumentList @('--exit-after','30','--log-level','warn')
Start-Sleep -Seconds $Wait
$t = [IntPtr]::Zero
foreach ($h in [F]::ForPid([uint32]$p.Id)) {
  if (-not [F]::IsWindowVisible($h)) { continue }
  $r = New-Object F+RECT; [void][F]::GetWindowRect($h, [ref]$r)
  if (($r.R-$r.L) -gt 400 -and ($r.B-$r.T) -gt 300) { $t = $h; break }
}
if ($t -eq [IntPtr]::Zero) { Write-Output 'no window'; exit 1 }
[void][F]::SetMenu($t, [IntPtr]::Zero); [void][F]::DrawMenuBar($t)
[void][F]::SetForegroundWindow($t)
Start-Sleep -Seconds 4
$r = New-Object F+RECT; [void][F]::GetWindowRect($t, [ref]$r)
$w = $r.R-$r.L; $hh = $r.B-$r.T
$bmp = New-Object System.Drawing.Bitmap $w, $hh
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($r.L, $r.T, 0, 0, (New-Object System.Drawing.Size $w, $hh))
$g.Dispose(); $bmp.Save($Shot, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
Write-Output "saved $Shot window ${w}x${hh} menu=$([F]::GetMenu($t))"
Get-Process par-term -ErrorAction SilentlyContinue | Stop-Process -Force
