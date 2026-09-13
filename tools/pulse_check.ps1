# Did the inline-TUI size pulse actually fire when pi started?
#
# The pulse calls resize_with_pixels, which logs "Resizing terminal to: ..." through
# the `log` crate (always written to %TEMP%\par_term_debug.log). A resize line that
# appears seconds after startup - once the shell's `pi` command runs - proves the
# modifyOtherKeys trigger fired. No such line means the trigger never fired, and the
# question moves to why pi's mode change is not observed.

$ErrorActionPreference = 'Continue'
$root = 'C:\Users\jky72\par-term'
$outs = "$root\galaxy-work\outputs"
$debugLog = Join-Path $env:TEMP 'par_term_debug.log'

Get-Process par-term -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 900
Remove-Item $debugLog -ErrorAction SilentlyContinue

$p = Start-Process "$root\par-term.exe" -PassThru -ArgumentList @(
  '--log-level', 'info', '--command-to-send', '"pi"'
)
Write-Output "launched par-term pid=$($p.Id) running pi; waiting 45s with no resize"
Start-Sleep -Seconds 45
Get-Process par-term -ErrorAction SilentlyContinue | Stop-Process -Force

Write-Output ''
Write-Output '=== every resize line, with the seconds since the first one ==='
if (Test-Path $debugLog) {
  $lines = Get-Content $debugLog | Select-String -Pattern 'Resizing terminal to'
  if (-not $lines) { Write-Output 'no resize lines at all' }
  $first = $null
  foreach ($l in $lines) {
    if ($l.Line -match '^\[(\d+\.\d+)\]') {
      $ts = [double]$Matches[1]
      if ($null -eq $first) { $first = $ts }
      $delta = [math]::Round($ts - $first, 2)
      # mark anything that lands well after window startup
      $mark = if ($delta -gt 1.5) { '  <-- LATE (pulse?)' } else { '' }
      Write-Output ("t+{0,6}s  {1}{2}" -f $delta, $l.Line.Substring($l.Line.IndexOf('Resizing')), $mark)
    }
  }
} else {
  Write-Output 'no debug log'
}
