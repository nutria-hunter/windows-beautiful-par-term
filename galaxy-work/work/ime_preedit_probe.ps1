# Capture what par-term draws while a Korean composition is *in progress* (no commit).
#
# The earlier ime_probe.ps1 proved the composed bytes reach the child on commit, but it never
# looked at the screen during composition, and Windows refuses SetForegroundWindow from a
# background process - so ImmGetContext returned 0 and the probe could not run at all.
#
# This variant (a) nudges the foreground lock with a synthetic Alt tap, the standard trick, and
# (b) screenshots *before* the composition, *during* it, and after cancelling it, so the diff
# isolates exactly what the preedit overlay painted. It never completes the composition and
# kills the test window instead, so nothing is typed into a shell.
#
# Usage: powershell -NoProfile -File C:\Users\jky72\par-term\galaxy-work\work\ime_preedit_probe.ps1
param(
  [string]$Exe = 'C:\Users\jky72\par-term\par-term.exe',
  [string]$Out = 'C:\Users\jky72\par-term\galaxy-work\outputs\ime-preedit',
  [string]$Text = '한',
  [string]$Tag = 'before'
)

$ErrorActionPreference = 'Continue'
Add-Type -AssemblyName System.Drawing
Add-Type @'
using System;
using System.Runtime.InteropServices;
public class ImmProbe {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetFocus(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
  [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint attach, uint attachTo, bool fAttach);
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
  [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }

  [DllImport("imm32.dll")] public static extern IntPtr ImmGetContext(IntPtr hwnd);
  [DllImport("imm32.dll")] public static extern bool ImmReleaseContext(IntPtr hwnd, IntPtr himc);
  [DllImport("imm32.dll", CharSet = CharSet.Unicode)]
  public static extern bool ImmSetCompositionString(IntPtr himc, uint index, string comp, int compLen, IntPtr read, int readLen);
  [DllImport("imm32.dll")] public static extern bool ImmNotifyIME(IntPtr himc, uint action, uint index, uint value);
  [DllImport("imm32.dll")] public static extern bool ImmSetOpenStatus(IntPtr himc, bool open);
  [DllImport("imm32.dll")] public static extern bool ImmGetOpenStatus(IntPtr himc);
}
'@
[void][ImmProbe]::SetProcessDPIAware()

$work = 'C:\Users\jky72\par-term\galaxy-work\work'
New-Item -ItemType Directory -Force -Path $Out | Out-Null
$capture = Join-Path $Out "ime-capture-$Tag.txt"
Remove-Item $capture -ErrorAction SilentlyContinue

function Largest($procId) {
  $st = @{ area = 0; hwnd = [IntPtr]::Zero }
  $cb = {
    param($h, $l)
    $q = 0; [void][ImmProbe]::GetWindowThreadProcessId($h, [ref]$q)
    if ($q -ne $procId -or -not [ImmProbe]::IsWindowVisible($h)) { return $true }
    $r = New-Object ImmProbe+RECT; [void][ImmProbe]::GetWindowRect($h, [ref]$r)
    $a = ($r.R - $r.L) * ($r.B - $r.T)
    if ($a -gt $st.area) { $st.area = $a; $st.hwnd = $h }
    return $true
  }
  [void][ImmProbe]::EnumWindows([ImmProbe+EnumProc]$cb, [IntPtr]::Zero)
  return $st.hwnd
}

function Shot($hwnd, $name) {
  $r = New-Object ImmProbe+RECT
  [void][ImmProbe]::GetWindowRect($hwnd, [ref]$r)
  $w = [Math]::Max($r.R - $r.L, 1); $h = [Math]::Max($r.B - $r.T, 1)
  $bmp = New-Object System.Drawing.Bitmap $w, $h
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen($r.L, $r.T, 0, 0, [System.Drawing.Size]::new($w, $h))
  $g.Dispose()
  $bmp.Save((Join-Path $Out $name), [System.Drawing.Imaging.ImageFormat]::Png)
  $bmp.Dispose()
  Write-Output "  saved $name ($w x $h)"
}

# A par-term instance of its own: the user's window must not be typed into.
$env:IME_CAPTURE_OUT = $capture
Write-Output "=== launching $Exe (tag=$Tag) ==="
$p = Start-Process $Exe -PassThru -ArgumentList @(
  '--log-level', 'debug', '--command-to-send', "`"node $($work -replace '\\','/')/ime-capture.mjs`""
)
Write-Output "pid=$($p.Id)"
Start-Sleep -Seconds 5

$hwnd = Largest $p.Id
if ($hwnd -eq [IntPtr]::Zero) { Write-Output 'FAIL: no visible window'; exit 1 }
[void][ImmProbe]::ShowWindow($hwnd, 9)   # SW_RESTORE
[void][ImmProbe]::SetWindowPos($hwnd, [IntPtr](-1), 60, 60, 1300, 900, 0x0040)
Start-Sleep -Seconds 1

# Windows only hands out an input context for the *active* window, and a background process may
# not raise one. AttachThreadInput plus a synthetic Alt tap is what gets past that refusal.
$targetThread = 0
[void][ImmProbe]::GetWindowThreadProcessId($hwnd, [ref]$targetThread)
$currentThread = [ImmProbe]::GetCurrentThreadId()
[void][ImmProbe]::AttachThreadInput($currentThread, $targetThread, $true)
[void][ImmProbe]::BringWindowToTop($hwnd)
[void][ImmProbe]::keybd_event(0x12, 0, 0, [UIntPtr]::Zero)                     # VK_MENU down
[void][ImmProbe]::SetForegroundWindow($hwnd)
[void][ImmProbe]::keybd_event(0x12, 0, 2, [UIntPtr]::Zero)                     # VK_MENU up
[void][ImmProbe]::SetFocus($hwnd)
[void][ImmProbe]::AttachThreadInput($currentThread, $targetThread, $false)
Start-Sleep -Seconds 2
$fg = [ImmProbe]::GetForegroundWindow()
Write-Output "window $hwnd ready (foreground=$fg, activated=$($fg -eq $hwnd))"

Write-Output ''
Write-Output '=== baseline screenshot (no composition) ==='
Shot $hwnd "preedit-$Tag-baseline.png"

$himc = [ImmProbe]::ImmGetContext($hwnd)
Write-Output "ImmGetContext -> $himc"
if ($himc -eq [IntPtr]::Zero) {
  Write-Output 'FAIL: no IME context for the window (window not active) - killing test instance'
  Stop-Process -Id $p.Id -Force
  exit 2
}
[void][ImmProbe]::ImmSetOpenStatus($himc, $true)
Write-Output "open status -> $([ImmProbe]::ImmGetOpenStatus($himc))"

Write-Output ''
Write-Output '=== composition in progress (preedit only, never committed) ==='
# SCS_SETSTR = 0x0001; the Unicode entry point takes a byte length.
$ok = [ImmProbe]::ImmSetCompositionString($himc, 0x0001, $Text, $Text.Length * 2, [IntPtr]::Zero, 0)
Write-Output "ImmSetCompositionString('$Text') -> $ok"
Start-Sleep -Seconds 2
Shot $hwnd "preedit-$Tag-composing.png"

Write-Output ''
Write-Output '=== cancelling the composition and tearing the test instance down ==='
# NI_COMPOSITIONSTR = 0x0015, CPS_CANCEL = 0x0004 (drops the composition, emits no commit).
[void][ImmProbe]::ImmNotifyIME($himc, 0x0015, 0x0004, 0)
[void][ImmProbe]::ImmReleaseContext($hwnd, $himc)
Start-Sleep -Seconds 1
Shot $hwnd "preedit-$Tag-cancelled.png"
Stop-Process -Id $p.Id -Force
Write-Output "killed pid=$($p.Id)"

$debugLog = Join-Path $env:TEMP 'par_term_debug.log'
if (Test-Path $debugLog) {
  Write-Output ''
  Write-Output '=== IME log lines (last 10) ==='
  Get-Content $debugLog | Select-String -Pattern 'IME' | Select-Object -Last 10 |
    ForEach-Object { Write-Output ("  " + $_.Line) }
}

Write-Output ''
Write-Output "=== capture file (proof nothing was committed) ==="
if (Test-Path $capture) {
  $got = (Get-Content $capture -Raw).Trim()
  Write-Output "  $(if ($got) { $got } else { '<empty> (expected)' })"
} else {
  Write-Output '  <never created>'
}
