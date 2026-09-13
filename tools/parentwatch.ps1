param([int]$Seconds = 12, [string]$Label = 'parent-watch')
Get-Process par-term -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 800
Start-Process 'C:\Users\jky72\par-term\par-term.exe' -ArgumentList @('--exit-after', "$($Seconds + 4)", '--log-level', 'warn') | Out-Null
Start-Sleep -Seconds 2

$names = @{}
$chains = @{}
$deadline = (Get-Date).AddSeconds($Seconds)
while ((Get-Date) -lt $deadline) {
  # one CIM sweep so parent ids are consistent with the snapshot
  $all = @{}
  foreach ($q in Get-CimInstance Win32_Process -ErrorAction SilentlyContinue) { $all[[int]$q.ProcessId] = $q }
  foreach ($q in $all.Values) {
    $n = "$($q.Name)"
    if ($n -notmatch '^(git|cmd|conhost|OpenConsole|powershell|pwsh|sh|bash)') { continue }
    if ($n -match '^git' -or $n -eq 'cmd.exe') {
      $key = "$n"
      if (-not $names.ContainsKey($key)) { $names[$key] = 0 }
      $names[$key]++
      # walk up to 4 levels of parents
      $chain = @()
      $cur = [int]$q.ParentProcessId
      for ($i = 0; $i -lt 4 -and $all.ContainsKey($cur) -and $cur -ne 0; $i++) {
        $par = $all[$cur]
        $chain += "$($par.Name)($($par.ProcessId))"
        $cur = [int]$par.ParentProcessId
      }
      $ck = "$n <- " + ($chain -join ' <- ')
      if (-not $chains.ContainsKey($ck)) { $chains[$ck] = 0 }
      $chains[$ck]++
    }
  }
  Start-Sleep -Milliseconds 300
}

Write-Output "[$Label] parent chains for git/cmd ($Seconds s)"
foreach ($k in ($chains.Keys | Sort-Object { -$chains[$_] })) {
  Write-Output ("   x{0,-3} {1}" -f $chains[$k], $k)
}
Get-Process par-term -ErrorAction SilentlyContinue | Stop-Process -Force
