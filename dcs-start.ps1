$ErrorActionPreference = "Stop"
$dcs = .$PSScriptRoot/dcs-find.ps1 -GetExecutable
if ($dcs) { Start-Process $dcs -ArgumentList "-w","DCS.unittest" } else { exit 1 }