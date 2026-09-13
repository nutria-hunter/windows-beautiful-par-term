# Run the pi agent inside par-term and capture what it renders.
#
# The question this answers: when pi is running, is its input box visible (so the
# problem is key delivery) or is the layout off-screen (so the problem is the grid)?
# The resize log from the same run shows whether pi's startup triggers a size storm.

$ErrorActionPreference = 'Continue'
$root = 'C:\Users\jky72\par-term'
$outs = "$root\galaxy-work\outputs"
$shot = "$outs\pi-shot.png"
$debugLog = Join-Path $env:TEMP 'par_term_debug.log'

Get-Process par-term -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 900
Remove-Item $shot, "$outs\pi-parterm.err", $debugLog -ErrorAction SilentlyContinue

$cmd = 'pi'
$pargs = @(
  '--exit-after', '22',
  '--screenshot', $shot,
  '--log-level', 'info',
  '--command-to-send', ('"' + $cmd + '"')
)
$p = Start-Process "$root\par-term.exe" -PassThru -ArgumentList $pargs `
  -RedirectStandardError "$outs\pi-parterm.err"
Write-Output "launched par-term pid=$($p.Id) running '$cmd'"

# par-term takes its own screenshot one second before --exit-after, so let it exit
# naturally rather than killing the window early and losing the capture.
Wait-Process -Id $p.Id -Timeout 40 -ErrorAction SilentlyContinue
Get-Process par-term -ErrorAction SilentlyContinue | Stop-Process -Force

Write-Output ''
Write-Output '=== par-term log lines of interest ==='
if (Test-Path $debugLog) {
  Get-Content $debugLog |
    Select-String -Pattern 'Resizing terminal to|Calculated window size|grid size|ALT_SCREEN|resize pulse' |
    Select-Object -First 25 | ForEach-Object { $_.Line }
} else {
  Write-Output 'no debug log'
}

Write-Output ''
Write-Output '=== capture ==='
if (Test-Path $shot) {
  Add-Type -AssemblyName System.Drawing
  $img = [System.Drawing.Image]::FromFile($shot)
  Write-Output "pi-shot.png $($img.Width)x$($img.Height)"
  $img.Dispose()
} else {
  Write-Output 'pi-shot.png MISSING'
}
if (Test-Path "$outs\pi-parterm.err") {
  $err = Get-Content "$outs\pi-parterm.err" | Select-Object -First 8
  if ($err) { Write-Output "stderr: $($err -join ' | ')" }
}
