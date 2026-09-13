param([int]$Seconds = 10, [string]$Label = 'watch')
Get-Process par-term -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 800

$before = @{}
foreach ($p in Get-Process -ErrorAction SilentlyContinue) { $before[$p.Id] = $true }

Start-Process 'C:\Users\jky72\par-term\par-term.exe' -ArgumentList @('--exit-after', "$($Seconds + 4)", '--log-level', 'warn') | Out-Null
Start-Sleep -Seconds 2

$seen = @{}
$deadline = (Get-Date).AddSeconds($Seconds)
while ((Get-Date) -lt $deadline) {
  foreach ($p in Get-Process -ErrorAction SilentlyContinue) {
    if ($before.ContainsKey($p.Id)) { continue }
    $n = $p.ProcessName
    if (-not $seen.ContainsKey($n)) { $seen[$n] = 0 }
    $seen[$n]++
  }
  Start-Sleep -Milliseconds 120
}

$total = 0
foreach ($k in ($seen.Keys | Sort-Object)) { $total += $seen[$k] }
Write-Output "[$Label] new-process sightings in ${Seconds}s (poll 120ms): total=$total"
foreach ($k in ($seen.Keys | Sort-Object { -$seen[$_] })) {
  if ($seen[$k] -ge 2) { Write-Output ("    {0,-20} {1}" -f $k, $seen[$k]) }
}

Get-Process par-term -ErrorAction SilentlyContinue | Stop-Process -Force
