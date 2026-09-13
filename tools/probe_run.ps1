# Measure the size par-term gives the child, and compare it with par-term's own grid.
#
# Two independent records:
#   outputs\probe.log        - what the child sees (os.get_terminal_size, shutil, env)
#   %TEMP%\par_term_debug.log - par-term's own "Resizing terminal to: WxH" lines
#
# This only works now that `--command-to-send` submits on Windows; before the CR fix
# the command was typed into the prompt and never executed.

$ErrorActionPreference = 'Continue'
$root = 'C:\Users\jky72\par-term'
$work = "$root\galaxy-work\work"
$outs = "$root\galaxy-work\outputs"
$probe = "$work\winsize_probe.py"
$plog = "$outs\probe.log"
$shot = "$outs\pshot2.png"
$debugLog = Join-Path $env:TEMP 'par_term_debug.log'

Get-Process par-term -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 800
Remove-Item $plog, $shot, $debugLog -ErrorAction SilentlyContinue

$cmd = "python $probe run1"
# -ArgumentList joins the array with spaces and adds no quoting, so a value with
# spaces has to carry its own quotes or clap sees three separate arguments and the
# process exits with a usage error before writing anything.
$pargs = @(
  '--exit-after', '16',
  '--screenshot', $shot,
  '--log-level', 'info',
  '--command-to-send', ('"' + $cmd + '"')
)
$p = Start-Process "$root\par-term.exe" -PassThru -ArgumentList $pargs `
  -RedirectStandardOutput "$outs\probe-parterm.out" -RedirectStandardError "$outs\probe-parterm.err"
Write-Output "launched par-term pid=$($p.Id); args: $($pargs -join ' ')"
Start-Sleep -Milliseconds 600
if ($p.HasExited) {
  Write-Output "par-term EXITED immediately (code $($p.ExitCode)):"
  if (Test-Path "$outs\probe-parterm.err") { Get-Content "$outs\probe-parterm.err" | Select-Object -First 10 }
  if (Test-Path "$outs\probe-parterm.out") { Get-Content "$outs\probe-parterm.out" | Select-Object -First 10 }
  exit 1
}

Wait-Process -Id $p.Id -Timeout 40 -ErrorAction SilentlyContinue
Get-Process par-term -ErrorAction SilentlyContinue | Stop-Process -Force

Write-Output ''
Write-Output '=== child view (probe.log) ==='
if (Test-Path $plog) { Get-Content $plog } else { Write-Output 'probe.log MISSING (command still not running)' }

Write-Output ''
Write-Output "=== par-term grid ($debugLog) ==="
if (Test-Path $debugLog) {
  $hits = Get-Content $debugLog | Select-String -Pattern 'Resizing terminal to|Resized|Calculated window size|PTY_RESIZE|grid'
  if ($hits) { $hits | Select-Object -First 25 | ForEach-Object { $_.Line } }
  else { Write-Output "no resize lines; log has $((Get-Content $debugLog).Count) lines" }
} else {
  Write-Output 'no debug log'
}

Write-Output ''
Write-Output '=== screenshot ==='
if (Test-Path $shot) {
  Add-Type -AssemblyName System.Drawing
  $img = [System.Drawing.Image]::FromFile($shot)
  Write-Output "pshot2.png $($img.Width)x$($img.Height)"
  $img.Dispose()
} else {
  Write-Output 'screenshot MISSING'
}
