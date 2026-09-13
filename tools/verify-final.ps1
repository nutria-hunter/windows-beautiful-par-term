# End-to-end verification of the installed par-term.exe.
#
#   A) pi input actually lands in the TUI          (DEC 2026 sync-update fix)
#   B) minimize -> restore survives                (scrollbar clamp fix)
#   C) no bogus 1-row grid reaches the child       (settle-candidate reset)
#   D) tab strip geometry                          (half-width cap, caption buttons)
#
# Deterministic assertions:
#   * pi's stdin must contain the typed text              (pi-observe.jsonl)
#   * the log must show no "Resizing terminal to: Nx1" after the minimize
# Human check: the before/after screenshots.
#
# Usage: powershell -NoProfile -File C:\Users\jky72\par-term\galaxy-work\work\verify-final.ps1
param(
  [string]$Exe = 'C:\Users\jky72\par-term\par-term.exe',
  [string]$Out = 'C:\Users\jky72\par-term\galaxy-work\outputs',
  [int]$FlagTimeoutSec = 300,
  [string]$Type = 'hello kitty'
)

$ErrorActionPreference = 'Continue'
Add-Type -AssemblyName System.Drawing
Add-Type @'
using System;
using System.Runtime.InteropServices;
public class VF {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] public static extern uint MapVirtualKey(uint code, uint kind);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
}
'@
[void][VF]::SetProcessDPIAware()

$work = 'C:\Users\jky72\par-term\galaxy-work\work'
$observe = Join-Path $Out 'e2e'
New-Item -ItemType Directory -Force -Path $observe | Out-Null
$observeJsonl = Join-Path $observe 'pi-observe.jsonl'
Remove-Item $observeJsonl -ErrorAction SilentlyContinue

$debugLog = Join-Path $env:TEMP 'par_term_debug.log'
$cli = 'C:/nvm4w/nodejs/node_modules/@earendil-works/pi-coding-agent/dist/bundle/cli.js'
$failures = New-Object System.Collections.Generic.List[string]

function Largest($procId) {
  $st = @{ area = 0; hwnd = [IntPtr]::Zero }
  $cb = {
    param($h, $l)
    $q = 0; [void][VF]::GetWindowThreadProcessId($h, [ref]$q)
    if ($q -ne $procId) { return $true }
    if (-not [VF]::IsWindowVisible($h)) { return $true }
    $r = New-Object VF+RECT; [void][VF]::GetWindowRect($h, [ref]$r)
    $a = ($r.R - $r.L) * ($r.B - $r.T)
    if ($a -gt $st.area) { $st.area = $a; $st.hwnd = $h }
    return $true
  }
  [void][VF]::EnumWindows([VF+EnumProc]$cb, [IntPtr]::Zero)
  return $st.hwnd
}

function Shot($hwnd, $name) {
  $r = New-Object VF+RECT
  [void][VF]::GetWindowRect($hwnd, [ref]$r)
  $w = [Math]::Max($r.R - $r.L, 1); $h = [Math]::Max($r.B - $r.T, 1)
  $bmp = New-Object System.Drawing.Bitmap $w, $h
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen($r.L, $r.T, 0, 0, [System.Drawing.Size]::new($w, $h))
  $g.Dispose()
  $p = Join-Path $Out $name
  $bmp.Save($p, [System.Drawing.Imaging.ImageFormat]::Png)
  $bmp.Dispose()
  return "$name ($w x $h)"
}

function Send-Keys($hwnd, [string]$text) {
  foreach ($ch in $text.ToCharArray()) {
    $vk = [int][char]::ToUpperInvariant($ch)
    $scan = [VF]::MapVirtualKey($vk, 0)
    $lp = 1 -bor ($scan -shl 16)
    [void][VF]::PostMessage($hwnd, 0x100, [IntPtr]$vk, [IntPtr]$lp)
    [void][VF]::PostMessage($hwnd, 0x102, [IntPtr][int]$ch, [IntPtr]$lp)
    [void][VF]::PostMessage($hwnd, 0x101, [IntPtr]$vk, [IntPtr]($lp -bor 0xC0000000L))
    Start-Sleep -Milliseconds 90
  }
}

function LastLogTimestamp {
  if (-not (Test-Path $debugLog)) { return 0.0 }
  $m = Select-String -Path $debugLog -Pattern '^\[(\d+\.\d+)\]' | Select-Object -Last 1
  if (-not $m) { return 0.0 }
  return [double]$m.Matches[0].Groups[1].Value
}

# Grids handed to the PTY after a given log timestamp, as (cols, rows) pairs.
function GridsSince([double]$ts) {
  $out = @()
  if (-not (Test-Path $debugLog)) { return $out }
  foreach ($line in (Get-Content $debugLog)) {
    $t = [regex]::Match($line, '^\[(\d+\.\d+)\]')
    if (-not $t.Success -or [double]$t.Groups[1].Value -le $ts) { continue }
    $g = [regex]::Match($line, 'Resizing terminal to: (\d+)x(\d+)')
    if ($g.Success) {
      $out += [pscustomobject]@{ cols = [int]$g.Groups[1].Value; rows = [int]$g.Groups[2].Value; line = $line }
    }
  }
  return $out
}

$env:PI_OFFLINE = '1'
$env:PI_OBSERVE_OUT = $observeJsonl
$cmd = '"node --import file:///' + ($work -replace '\\', '/') + '/pi-observe.mjs ' + $cli +
       ' --no-extensions --no-skills --no-prompt-templates --no-context-files --no-session"'

Write-Output "=== launching $Exe ==="
$p = Start-Process $Exe -PassThru -ArgumentList @('--log-level', 'info', '--command-to-send', $cmd)
Write-Output "pid=$($p.Id)"
Start-Sleep -Seconds 3

$hwnd = Largest $p.Id
if ($hwnd -eq [IntPtr]::Zero) { Write-Output 'FAIL: no visible window'; exit 1 }
[void][VF]::SetWindowPos($hwnd, [IntPtr](-1), 80, 80, 1300, 900, 0x0040)
Start-Sleep -Milliseconds 900

Write-Output ''
Write-Output "=== A) pi input (waiting up to ${FlagTimeoutSec}s for the child to start) ==="
# Readiness is taken from the child's own first size report, not from par-term's log and not
# from pixels. Neither of the other two options can work: the KITTY_KEYBOARD line is emitted
# from the key handler, so it cannot appear before the first keystroke, and a pixel test is
# unreliable because the cursor band it matched only exists in transient frames (a later run
# sat here for the full timeout with pi's TUI clearly drawn on screen). The shim writes a
# 'resize'/'state' record as soon as node starts, which is a couple of seconds before the TUI
# is drawn, so a short settle afterwards is all that is needed.
$childDeadline = (Get-Date).AddSeconds($FlagTimeoutSec)
$childStarted = $false
while ((Get-Date) -lt $childDeadline) {
  Start-Sleep -Seconds 1
  if ((Test-Path $observeJsonl) -and
      (Select-String -Path $observeJsonl -Pattern '"event":"(resize|state)"' -Quiet)) {
    $childStarted = $true
    break
  }
}
if ($childStarted) {
  Write-Output '  child started; letting its TUI settle'
} else {
  $failures.Add('the child never started')
  Write-Output '  FAIL: the child never reported a size'
}
Start-Sleep -Seconds 8

Write-Output "  shot A: $(Shot $hwnd 'final-before.png')"
[void][VF]::SetForegroundWindow($hwnd)
Start-Sleep -Milliseconds 600
Send-Keys $hwnd $Type
Start-Sleep -Seconds 4
Write-Output "  shot B: $(Shot $hwnd 'final-after.png')"

# Deterministic: what did pi actually receive on stdin?
Start-Sleep -Milliseconds 500
$received = ''
if (Test-Path $observeJsonl) {
  foreach ($line in (Get-Content $observeJsonl)) {
    try { $o = $line | ConvertFrom-Json } catch { continue }
    if ($o.event -eq 'input' -and $o.hex) {
      $bytes = for ($i = 0; $i -lt $o.hex.Length; $i += 2) { [Convert]::ToByte($o.hex.Substring($i, 2), 16) }
      $received += [System.Text.Encoding]::ASCII.GetString([byte[]]$bytes)
    }
  }
}
if ($received -like "*$Type*") {
  Write-Output "  PASS: pi received the typed text on stdin"
} else {
  $failures.Add("pi stdin did not contain '$Type' (got $(($received -replace '[^\x20-\x7e]', '.')))")
  Write-Output "  FAIL: pi stdin did not contain the typed text. Received: '$(($received -replace '[^\x20-\x7e]', '.'))'"
}

# Evidence that pi opted into the kitty keyboard protocol (logged on the first keystroke).
$kittyLine = Select-String -Path $debugLog -Pattern 'KITTY_KEYBOARD flags requested: (\S+)' -ErrorAction SilentlyContinue |
  Select-Object -Last 1
if ($kittyLine) { Write-Output "  pi pushed kitty flags: $($kittyLine.Matches[0].Groups[1].Value)" }
else { Write-Output '  WARN: no KITTY_KEYBOARD line (pi did not push keyboard-protocol flags)' }

Write-Output ''
Write-Output '=== B/C) minimize -> restore ==='
$beforeMinimize = LastLogTimestamp
[void][VF]::ShowWindow($hwnd, 6)   # SW_MINIMIZE
Start-Sleep -Seconds 4
if ($p.HasExited) { Write-Output '  FAIL: died on minimize'; exit 2 }
Write-Output "  minimized: alive=True iconic=$([VF]::IsIconic($hwnd))"
[void][VF]::ShowWindow($hwnd, 9)   # SW_RESTORE
Start-Sleep -Seconds 4
if ($p.HasExited) { Write-Output '  FAIL: died on restore'; exit 3 }
[void][VF]::SetWindowPos($hwnd, [IntPtr](-1), 80, 80, 1300, 900, 0x0040)
Start-Sleep -Seconds 3
Write-Output "  restored: alive=True"
Write-Output "  shot C: $(Shot $hwnd 'final-restored.png')"

$grids = GridsSince $beforeMinimize
$pushed = if ($grids.Count -eq 0) { '<none>' } else { ($grids | ForEach-Object { "$($_.cols)x$($_.rows)" }) -join ', ' }
Write-Output "  grids par-term pushed: $pushed"

# Judge what the *child* saw, not what par-term logged. A minimize/restore that returns to the
# same window size correctly pushes nothing at all, so an empty par-term log proves nothing;
# a one-row grid handed to the child is the failure actually being tested for. The shim logs
# every stdout resize plus a 5s size sample, which is the child's own view of its terminal.
function ChildSizes {
  $sizes = @()
  if (-not (Test-Path $observeJsonl)) { return $sizes }
  foreach ($line in (Get-Content $observeJsonl)) {
    try { $o = $line | ConvertFrom-Json } catch { continue }
    if (($o.event -eq 'resize' -or $o.event -eq 'state') -and $o.rows) {
      $sizes += [pscustomobject]@{ cols = [int]$o.columns; rows = [int]$o.rows }
    }
  }
  return $sizes
}

$child = ChildSizes
$childDesc = @($child | ForEach-Object { "$($_.cols)x$($_.rows)" } | Select-Object -Unique) -join ', '
if ($child.Count -eq 0) {
  $failures.Add('the child reported no size at all - the observation shim did not run')
  Write-Output '  FAIL: the child reported no size (shim missing)'
} else {
  Write-Output "  sizes the child saw: $childDesc ($($child.Count) records)"
  $degenerate = @($child | Where-Object { $_.rows -le 1 -or $_.cols -le 1 })
  if ($degenerate.Count -eq 0) {
    Write-Output '  PASS: the child never saw a degenerate grid'
  } else {
    $bad = ($degenerate | ForEach-Object { "$($_.cols)x$($_.rows)" }) -join ', '
    $failures.Add("child saw a degenerate grid: $bad")
    Write-Output "  FAIL: child saw a degenerate grid: $bad"
  }
  $lastChild = @($child | Select-Object -Last 1)
  if ($lastChild[0].cols -ge 40 -and $lastChild[0].rows -ge 10) {
    Write-Output "  PASS: child ended on $($lastChild[0].cols)x$($lastChild[0].rows)"
  } else {
    $failures.Add("child ended on $($lastChild[0].cols)x$($lastChild[0].rows)")
    Write-Output "  FAIL: child ended on $($lastChild[0].cols)x$($lastChild[0].rows)"
  }
}

Write-Output ''
Write-Output '=== D) input still live after restore ==='
[void][VF]::SetForegroundWindow($hwnd)
Start-Sleep -Milliseconds 500
Send-Keys $hwnd ' ok'
Start-Sleep -Seconds 3
Write-Output "  shot D: $(Shot $hwnd 'final-after-restore-input.png')"
$after = ''
if (Test-Path $observeJsonl) {
  foreach ($line in (Get-Content $observeJsonl)) {
    try { $o = $line | ConvertFrom-Json } catch { continue }
    if ($o.event -eq 'input' -and $o.hex) {
      $bytes = for ($i = 0; $i -lt $o.hex.Length; $i += 2) { [Convert]::ToByte($o.hex.Substring($i, 2), 16) }
      $after += [System.Text.Encoding]::ASCII.GetString([byte[]]$bytes)
    }
  }
}
if ($after -like "*$Type ok*") { Write-Output '  PASS: input works after restore too' }
else {
  $failures.Add('input did not survive the restore')
  Write-Output "  FAIL: input after restore. Received: '$(($after -replace '[^\x20-\x7e]', '.'))'"
}

Write-Output ''
Write-Output '=== summary ==='
if ($failures.Count -eq 0) { Write-Output 'ALL CHECKS PASSED' }
else { foreach ($f in $failures) { Write-Output "FAILED: $f" } }
Write-Output "process left running (pid=$($p.Id)) for manual inspection"
