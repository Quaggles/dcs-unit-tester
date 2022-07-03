param (
    [Parameter(Mandatory=$true)]
    [string] $TrackPath
)
$dcsPath = (.$PSScriptRoot/../dcs-find.ps1)
if (-not (Test-Path $PSScriptRoot/dcs-lua-bin/luarun.exe)){
    Write-Error "Could not find $PSScriptRoot/dcs-lua-bin/luarun.exe make sure you cloned the repository with submodules enabled or grab it manually from https://github.com/Quaggles/dcs-lua-bin"
}
if (-not (Test-Path $TrackPath)){
    Write-Error "Provided Track path `"$TrackPath`" does not exist"
}
.$PSScriptRoot/dcs-lua-bin/luarun.exe "$PSScriptRoot/GetMissionDescription.lua" "$dcsPath/" "$TrackPath"