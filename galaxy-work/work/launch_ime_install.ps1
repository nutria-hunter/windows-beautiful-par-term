# Launch the par-term install script outside this process tree.
#
# The install has to survive par-term exiting: the running image holds a lock on par-term.exe, so
# the swap can only happen once the process is gone - and anything started from a shell inside
# par-term (this session included) is killed at the same moment. `Install` spawns through WMI, so
# the child's parent is WmiPrvSE rather than powershell/par-term, and it outlives the window.
#
# The script then waits for par-term to exit, backs up, swaps, verifies hashes, and writes its
# whole transcript to the log next to it.
#
# Usage: powershell -NoProfile -File .\launch_ime_install.ps1

[CmdletBinding()]
param(
  [string]$Script = 'C:\Users\jky72\par-term\galaxy-work\work\install_ime_build.ps1',
  [string]$Log = 'C:\Users\jky72\par-term\galaxy-work\work\install_ime_result.log'
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $Script)) {
  Write-Output "FAIL: install script not found: $Script"
  exit 1
}

Remove-Item $Log -ErrorAction SilentlyContinue

# -Command (not -File) so the transcript can be redirected into $Log from inside the child.
$inner = "& '$Script' *> '$Log'"
$created = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{
  CommandLine = "powershell.exe -NoProfile -ExecutionPolicy Bypass -Command `"$inner`""
}

if ($created.ReturnValue -ne 0) {
  Write-Output "FAIL: Win32_Process.Create returned $($created.ReturnValue)"
  exit 1
}

Write-Output "installer launched detached: pid=$($created.ProcessId)"
Write-Output "transcript: $Log"
Write-Output "It waits up to 600s for par-term to exit; close par-term now to let the swap happen."
