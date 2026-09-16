param([string]$Exe, [string]$Tag)
$log = "$env:TEMP\par_term_debug.log"
Remove-Item $log -ErrorAction SilentlyContinue
$sw=[System.Diagnostics.Stopwatch]::StartNew()
$p=Start-Process -FilePath $Exe -ArgumentList '--log-level info --shader kanagawa-starbound.glsl --exit-after 12' -WindowStyle Hidden -PassThru
$p.WaitForExit(120000)|Out-Null
$sw.Stop()
$rows=@()
if(Test-Path $log){
  Get-Content $log | ForEach-Object {
    if($_ -match '^\[(\d+\.\d+)\]'){ $rows += [pscustomobject]@{t=[double]$Matches[1]; line=$_} }
  }
}
$base = if($rows.Count){$rows[0].t}else{0}
$firstframe = ($rows | Where-Object { $_.line -match 'PERF: FPS=' } | Select-Object -First 1)
$shaderlive = ($rows | Where-Object { $_.line -match 'pipeline compiled in background' } | Select-Object -First 1)
$shaderloaded = ($rows | Where-Object { $_.line -match 'Loaded custom shader' } | Select-Object -First 1)
Write-Output ("[{0}] 프로세스 총 {1:N2}s" -f $Tag,$sw.Elapsed.TotalSeconds)
if($shaderloaded){ Write-Output ("   셰이더 파싱+WGSL생성 : +{0:N2}s" -f ($shaderloaded.t-$base)) }
if($firstframe){ Write-Output ("   ▶ 첫 프레임 표시    : +{0:N2}s" -f ($firstframe.t-$base)) } else { Write-Output "   ▶ 첫 프레임 로그 없음(12초 내 미표시?)" }
if($shaderlive){ Write-Output ("   ▶ 셰이더 화면 반영  : +{0:N2}s" -f ($shaderlive.t-$base)) } else { Write-Output "   ▶ 셰이더 반영 로그 없음" }
