# Report which visible top-level windows have an IME context.
#
# Needed because ImmGetContext on par-term's window returned 0, which could mean either "the
# window was not active" or "this session has no IME at all". If no window anywhere has a
# context, driving composition through Imm32 is impossible and the probe has to be replaced.
Add-Type @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public class ImeEnv {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern int GetWindowTextW(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("imm32.dll")] public static extern IntPtr ImmGetContext(IntPtr h);
  [DllImport("imm32.dll")] public static extern bool ImmReleaseContext(IntPtr h, IntPtr c);
  [DllImport("imm32.dll")] public static extern bool ImmGetOpenStatus(IntPtr c);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
}
'@

$rows = New-Object System.Collections.ArrayList
$cb = [ImeEnv+EnumProc] {
  param($h, $l)
  if ([ImeEnv]::IsWindowVisible($h)) {
    $sb = New-Object System.Text.StringBuilder 256
    [void][ImeEnv]::GetWindowTextW($h, $sb, 256)
    $title = $sb.ToString()
    if ($title.Length -gt 0) {
      $rect = New-Object ImeEnv+RECT
      [void][ImeEnv]::GetWindowRect($h, [ref]$rect)
      $ownerPid = 0; [void][ImeEnv]::GetWindowThreadProcessId($h, [ref]$ownerPid)
      $ctx = [ImeEnv]::ImmGetContext($h)
      $open = if ($ctx -ne 0) { [ImeEnv]::ImmGetOpenStatus($ctx) } else { $null }
      [void][ImeEnv]::ImmReleaseContext($h, $ctx)
      [void]$rows.Add([pscustomobject]@{
        Title   = $title.Substring(0, [Math]::Min(34, $title.Length))
        Pid     = $ownerPid
        Width   = $rect.R - $rect.L
        ImeCtx  = $ctx
        ImeOpen = $open
      })
    }
  }
  return $true
}
[void][ImeEnv]::EnumWindows($cb, [IntPtr]::Zero)

Write-Output "visible titled windows: $($rows.Count)"
Write-Output "with an IME context:    $(@($rows | Where-Object { $_.ImeCtx -ne 0 }).Count)"
Write-Output ''
$rows | Sort-Object -Property Width -Descending | Select-Object -First 15 | Format-Table -AutoSize
