$ErrorActionPreference = "Stop"
$dcs = .$PSScriptRoot/dcs-find.ps1 -GetExecutable
if ($dcs) { Start-Process $dcs -ArgumentList "-w","DCS.unittest","--force_disable_VR" } else { exit 1 }