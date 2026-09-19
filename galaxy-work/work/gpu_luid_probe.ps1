# Per-LUID 3D engine utilization for one process, repeated a few times.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File gpu_luid_probe.ps1 [-ProcessName par-term-vulkan] [-Samples 5] [-IntervalMs 2000]
# Prints the peak 3D utilization per adapter LUID, plus the total across all processes.
param(
  [string]$ProcessName = 'par-term-vulkan',
  [int]$Samples = 5,
  [int]$IntervalMs = 2000
)

$proc = Get-Process $ProcessName -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $proc) { Write-Output "process '$ProcessName' not found"; exit 1 }
Write-Output ("pid {0} ({1})" -f $proc.Id, $ProcessName)

$peak = @{}
$totalPeak = @{}
for ($i = 0; $i -lt $Samples; $i++) {
  $samples = (Get-Counter '\GPU Engine(*)\Utilization Percentage' -ErrorAction SilentlyContinue).CounterSamples
  foreach ($s in $samples) {
    if ($s.InstanceName -notlike '*engtype_3D*') { continue }
    $luid = ($s.InstanceName -split '_luid_')[1] -replace '_phys.*', ''
    if ($s.CookedValue -gt $totalPeak[$luid]) { $totalPeak[$luid] = $s.CookedValue }
    if ($s.InstanceName -like ('*pid_' + $proc.Id + '*')) {
      if ($s.CookedValue -gt $peak[$luid]) { $peak[$luid] = $s.CookedValue }
    }
  }
  Start-Sleep -Milliseconds $IntervalMs
}

Write-Output 'process 3D peak per adapter:'
if ($peak.Count -eq 0) { Write-Output '  (none)' }
$peak.GetEnumerator() | Sort-Object Value -Descending | ForEach-Object { Write-Output ("  {0,7:N1}%  luid_{1}" -f $_.Value, $_.Key) }
Write-Output 'system 3D peak per adapter:'
$totalPeak.GetEnumerator() | Sort-Object Value -Descending | ForEach-Object {
  if ($_.Value -gt 1) { Write-Output ("  {0,7:N1}%  luid_{1}" -f $_.Value, $_.Key) }
}
