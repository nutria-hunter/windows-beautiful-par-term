# Move the pointer away, then capture: separates an OS pointer in the grab from a real hole.
param([string]$Out = 'C:\Users\jky72\par-term\galaxy-work\outputs\pointer-test.png')
Add-Type -TypeDefinition 'using System; using System.Runtime.InteropServices; public class PT { [DllImport("user32.dll")] public static extern bool GetCursorPos(out int x, out int y); [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y); }'
Add-Type @'
using System;
using System.Runtime.InteropServices;
public class PTW {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint f);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
}
'@
[void][PTW]::SetProcessDPIAware()
$p = Start-Process 'C:\Users\jky72\par-term\par-term.exe' -PassThru
Start-Sleep -Seconds 3
$st = @{ area = 0; hwnd = [IntPtr]::Zero }
[void][PTW]::EnumWindows([PTW+EnumProc]{ param($h,$l)
  $o=0; [void][PTW]::GetWindowThreadProcessId($h,[ref]$o)
  if ($o -ne $p.Id -or -not [PTW]::IsWindowVisible($h)) { return $true }
  $r = New-Object PTW+RECT; [void][PTW]::GetWindowRect($h,[ref]$r)
  $a = ($r.R-$r.L)*($r.B-$r.T); if ($a -gt $st.area) { $st.area=$a; $st.hwnd=$h }
  return $true }, [IntPtr]::Zero)
[void][PTW]::SetWindowPos($st.hwnd, [IntPtr](-1), 80, 80, 1300, 900, 0x0040)
Start-Sleep -Seconds 4
# 포인터를 창 밖 구석으로 이동
[void][PT]::SetCursorPos(20, 1400)
Start-Sleep -Seconds 2
$x=0;$y=0; [void][PT]::GetCursorPos([ref]$x,[ref]$y)
Write-Output "pointer now at $x,$y"
& python 'C:\Users\jky72\par-term\galaxy-work\work\cap_pid.py' "$($p.Id)" $Out
Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
