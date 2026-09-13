# Verify Korean (IME-composed) input end to end, without a human at the keyboard.
#
# par-term enables the platform IME, so composed text arrives as WindowEvent::Ime rather than
# as key events. This drives that exact path: it sets a composition string on the real window
# through Imm32 (which makes Windows emit WM_IME_COMPOSITION, which winit turns into
# Ime::Preedit / Ime::Commit), and it runs a capture child instead of a shell so the bytes the
# terminal actually delivered are written to a file and can be checked byte for byte.
#
# Expected: "한글" is U+D55C U+AE00, i.e. UTF-8 ed 95 9c ea b0 80 -> hex ed959ceab080.
#
# Usage: powershell -NoProfile -File C:\Users\jky72\par-term\galaxy-work\work\ime_probe.ps1
param(
  [string]$Exe = 'C:\Users\jky72\par-term\par-term.exe',
  [string]$Out = 'C:\Users\jky72\par-term\galaxy-work\outputs\e2e',
  [string]$Text = '한글'
)

$ErrorActionPreference = 'Continue'
Add-Type -AssemblyName System.Drawing
Add-Type @'
using System;
using System.Runtime.InteropServices;
public class ImeProbe {
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
[void][ImeProbe]::SetProcessDPIAware()

$work = 'C:\Users\jky72\par-term\galaxy-work\work'
$capture = Join-Path $Out 'ime-capture.txt'
$debugLog = Join-Path $env:TEMP 'par_term_debug.log'
Remove-Item $capture -ErrorAction SilentlyContinue

function Largest($procId) {
  $st = @{ area = 0; hwnd = [IntPtr]::Zero }
  $cb = {
    param($h, $l)
    $q = 0; [void][ImeProbe]::GetWindowThreadProcessId($h, [ref]$q)
    if ($q -ne $procId -or -not [ImeProbe]::IsWindowVisible($h)) { return $true }
    $r = New-Object ImeProbe+RECT; [void][ImeProbe]::GetWindowRect($h, [ref]$r)
    $a = ($r.R - $r.L) * ($r.B - $r.T)
    if ($a -gt $st.area) { $st.area = $a; $st.hwnd = $h }
    return $true
  }
  [void][ImeProbe]::EnumWindows([ImeProbe+EnumProc]$cb, [IntPtr]::Zero)
  return $st.hwnd
}

function Shot($hwnd, $name) {
  $r = New-Object ImeProbe+RECT
  [void][ImeProbe]::GetWindowRect($hwnd, [ref]$r)
  $w = [Math]::Max($r.R - $r.L, 1); $h = [Math]::Max($r.B - $r.T, 1)
  $bmp = New-Object System.Drawing.Bitmap $w, $h
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen($r.L, $r.T, 0, 0, [System.Drawing.Size]::new($w, $h))
  $g.Dispose()
  $bmp.Save((Join-Path $Out $name), [System.Drawing.Imaging.ImageFormat]::Png)
  $bmp.Dispose()
  Write-Output "  saved $name ($w x $h)"
}

$env:IME_CAPTURE_OUT = $capture
Write-Output "=== launching $Exe with a byte-capture child ==="
# --log-level debug so the IME debug_info lines are recorded as evidence.
$p = Start-Process $Exe -PassThru -ArgumentList @(
  '--log-level', 'debug', '--command-to-send', "`"node $($work -replace '\\','/')/ime-capture.mjs`""
)
Write-Output "pid=$($p.Id)"
Start-Sleep -Seconds 4

$hwnd = Largest $p.Id
if ($hwnd -eq [IntPtr]::Zero) { Write-Output 'FAIL: no visible window'; exit 1 }
[void][ImeProbe]::ShowWindow($hwnd, 9)   # SW_RESTORE
[void][ImeProbe]::SetWindowPos($hwnd, [IntPtr](-1), 80, 80, 1300, 900, 0x0040)
Start-Sleep -Seconds 1

# Windows only associates an input context with the *active* window, and a background script's
# SetForegroundWindow is usually ignored. Attaching to the target's input queue first is what
# makes the call stick; without it ImmGetContext returns 0 and the probe cannot run at all.
$targetThread = 0
[void][ImeProbe]::GetWindowThreadProcessId($hwnd, [ref]$targetThread)
$currentThread = [ImeProbe]::GetCurrentThreadId()
[void][ImeProbe]::AttachThreadInput($currentThread, $targetThread, $true)
[void][ImeProbe]::BringWindowToTop($hwnd)
[void][ImeProbe]::SetForegroundWindow($hwnd)
[void][ImeProbe]::SetFocus($hwnd)
[void][ImeProbe]::AttachThreadInput($currentThread, $targetThread, $false)
Start-Sleep -Seconds 2
$fg = [ImeProbe]::GetForegroundWindow()
Write-Output "window $hwnd ready (foreground=$fg, activated=$($fg -eq $hwnd))"

Write-Output ''
Write-Output '=== 1) open the IME context and set a composition string ==='
$himc = [ImeProbe]::ImmGetContext($hwnd)
Write-Output "  ImmGetContext -> $himc"
if ($himc -eq [IntPtr]::Zero) { Write-Output 'FAIL: no IME context for the window'; exit 2 }
[void][ImeProbe]::ImmSetOpenStatus($himc, $true)
Write-Output "  open status -> $([ImeProbe]::ImmGetOpenStatus($himc))"

# SCS_SETSTR = 0x0001; length is in bytes for the Unicode entry point.
$setOk = [ImeProbe]::ImmSetCompositionString($himc, 0x0001, $Text, $Text.Length * 2, [IntPtr]::Zero, 0)
Write-Output "  ImmSetCompositionString('$Text') -> $setOk"
Start-Sleep -Seconds 2
Write-Output '  preedit screenshot (the composing text should be drawn at the cursor):'
Shot $hwnd 'ime-preedit.png'

Write-Output ''
Write-Output '=== 2) complete the composition (this is what emits Ime::Commit) ==='
# NI_COMPOSITIONSTR = 0x0015, CPS_COMPLETE = 0x0001
$done = [ImeProbe]::ImmNotifyIME($himc, 0x0015, 0x0001, 0)
Write-Output "  ImmNotifyIME(CPS_COMPLETE) -> $done"
[void][ImeProbe]::ImmReleaseContext($hwnd, $himc)
Start-Sleep -Seconds 3
Shot $hwnd 'ime-committed.png'

Write-Output ''
Write-Output '=== 3) what the child actually received ==='
$expected = -join ([System.Text.Encoding]::UTF8.GetBytes($Text) | ForEach-Object { $_.ToString('x2') })
Write-Output "  expected UTF-8 hex for '$Text': $expected"
if (Test-Path $capture) {
  $got = (Get-Content $capture -Raw).Trim()
  Write-Output "  capture file: $(if ($got) { $got } else { '<empty>' })"
  if ($got -match $expected) {
    Write-Output '  PASS: the composed text reached the child intact'
  } else {
    Write-Output '  FAIL: the capture does not contain the composed text'
  }
} else {
  Write-Output '  FAIL: capture file was never created (child did not start?)'
}

Write-Output ''
Write-Output '=== 4) IME log lines ==='
if (Test-Path $debugLog) {
  Get-Content $debugLog | Select-String -Pattern 'IME' | Select-Object -Last 12 |
    ForEach-Object { Write-Output ("  " + $_.Line) }
}
Write-Output ''
Write-Output "leaving par-term running (pid=$($p.Id)) for manual inspection"
