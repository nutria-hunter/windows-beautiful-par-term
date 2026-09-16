# Screenshot the IME preedit overlay that the running par-term draws.
#
# The platform IME only hands an input context to the *active* window, and Windows refuses to let a
# background process raise one, so a real composition cannot be driven from a script (documented in
# galaxy-work/outputs/OPEN-ISSUES-HANDOFF.md, section 5). The binary instead accepts
# PAR_TERM_IME_PREEDIT, which seeds the same ImeState that `Ime::Preedit` feeds, so the overlay can
# be photographed with no IME and no human.
#
# Two captures are taken from one window: one with no seed (baseline) and one with the seed, so the
# difference is exactly the overlay's ink.
#
# OR the Imm32-side reader (ime_composition) with -Imm, which seeds the string the window
# procedure reads out of the input context. Both sources draw the same overlay, so both need
# coverage: the built-in path is what a real IME feeds.
#
# Usage:
#   powershell -NoProfile -File .\preedit_shot.ps1 -Text ([char]0xD55C)     # composes U+D55C
#   powershell -NoProfile -File .\preedit_shot.ps1 -Imm -Tag imm            # Imm32 reader
#
# This file is deliberately ASCII-only: PowerShell 5.1 decodes a script that has no BOM using the
# system codepage, and a literal Hangul default here silently swallows the closing quote, which
# turns the whole file into a parse error.
#
# NOTE: pi-lens flags the param() block below as parse errors; the real PowerShell parser
# (System.Management.Automation.Language.Parser::ParseFile) accepts the file — verified twice.
# Ground truth is the parser, not the linter.

param(
  [string]$Exe = 'C:\Users\jky72\par-term\par-term.exe',
  [string]$Out = 'C:\Users\jky72\par-term\galaxy-work\outputs\ime-preedit',
  [string]$Text = '',
  [string]$Tag = 'after',
  [switch]$Imm,
  [string]$Child = '',
  [string]$Dy = '',
  [int]$Width = 1300,
  [int]$Height = 900
)

if (-not $Text) { $Text = ([char]0xD55C).ToString() }

$ErrorActionPreference = 'Continue'
Add-Type -AssemblyName System.Drawing
Add-Type @'
using System;
using System.Runtime.InteropServices;
public class SeedProbe {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
}
'@
[void][SeedProbe]::SetProcessDPIAware()

New-Item -ItemType Directory -Force -Path $Out | Out-Null

function Largest($procId) {
  $st = @{ area = 0; hwnd = [IntPtr]::Zero }
  $cb = {
    param($h, $l)
    $q = 0; [void][SeedProbe]::GetWindowThreadProcessId($h, [ref]$q)
    if ($q -ne $procId -or -not [SeedProbe]::IsWindowVisible($h)) { return $true }
    $r = New-Object SeedProbe+RECT; [void][SeedProbe]::GetWindowRect($h, [ref]$r)
    $a = ($r.R - $r.L) * ($r.B - $r.T)
    if ($a -gt $st.area) { $st.area = $a; $st.hwnd = $h }
    return $true
  }
  [void][SeedProbe]::EnumWindows([SeedProbe+EnumProc]$cb, [IntPtr]::Zero)
  return $st.hwnd
}

function Shot($hwnd, $name) {
  $r = New-Object SeedProbe+RECT
  [void][SeedProbe]::GetWindowRect($hwnd, [ref]$r)
  $w = [Math]::Max($r.R - $r.L, 1); $h = [Math]::Max($r.B - $r.T, 1)
  $bmp = New-Object System.Drawing.Bitmap $w, $h
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen($r.L, $r.T, 0, 0, [System.Drawing.Size]::new($w, $h))
  $g.Dispose()
  $bmp.Save((Join-Path $Out $name), [System.Drawing.Imaging.ImageFormat]::Png)
  $bmp.Dispose()
  Write-Output "  saved $name ($w x $h)"
}

# A quiet grid: the child writes one line and then goes quiet, so the only ink near the cursor is
# the overlay itself. `-Child` swaps in another script (e.g. one that hides the terminal cursor, to
# mirror a TUI that draws its own caret).
$child = if ($Child) { $Child } else { 'C:\Users\jky72\par-term\galaxy-work\work\blank-child.mjs' }

function Capture($seedText, $name) {
  $var = if ($Imm) { 'PAR_TERM_IME_IMM_PREEDIT' } else { 'PAR_TERM_IME_PREEDIT' }
  if ($seedText) { Set-Item -Path "Env:$var" -Value $seedText } else { Remove-Item "Env:$var" -ErrorAction SilentlyContinue }
  # Calibration hook: the overlay's vertical offset, in points. Empty means the built-in default.
  if ($Dy) { Set-Item -Path 'Env:PAR_TERM_IME_PREEDIT_DY' -Value $Dy } else { Remove-Item Env:\PAR_TERM_IME_PREEDIT_DY -ErrorAction SilentlyContinue }
  $p = Start-Process $Exe -PassThru -ArgumentList @(
    '--log-level', 'debug', '--command-to-send', "`"node $($child -replace '\\','/' )`""
  )
  Start-Sleep -Seconds 5
  $hwnd = Largest $p.Id
  if ($hwnd -eq [IntPtr]::Zero) { Write-Output 'FAIL: no visible window'; exit 1 }
  [void][SeedProbe]::ShowWindow($hwnd, 9)
  [void][SeedProbe]::SetWindowPos($hwnd, [IntPtr](-1), 40, 40, $Width, $Height, 0x0040)
  Start-Sleep -Seconds 3
  Shot $hwnd $name
  Stop-Process -Id $p.Id -Force
  Write-Output "  closed pid=$($p.Id)"
}

Remove-Item Env:\PAR_TERM_IME_PREEDIT -ErrorAction SilentlyContinue
Remove-Item Env:\PAR_TERM_IME_IMM_PREEDIT -ErrorAction SilentlyContinue
Write-Output "=== baseline (no composition) ==="
Capture $null "preedit-$Tag-baseline.png"

Write-Output "=== composing '$Text' (seeded) ==="
Capture $Text "preedit-$Tag-seeded.png"

Write-Output ''
Write-Output 'Now run:  python analyze_preedit_shot.py ' + $Tag
