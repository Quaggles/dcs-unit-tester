# Iterates through all .base.trk files in -TrackDirectory and creates variants of them according to the payloads.lua files
param (
    [Parameter(Mandatory=$true)]
    [string] $TrackDirectory
)
$dcsPath = (.$PSScriptRoot/../dcs-find.ps1)
if (-not (Test-Path $PSScriptRoot/dcs-lua-bin/luarun.exe)){
    Write-Error "Could not find $PSScriptRoot/dcs-lua-bin/luarun.exe make sure you cloned the repository with submodules enabled or grab it manually from https://github.com/Quaggles/dcs-lua-bin"
}
if (-not (Test-Path $TrackDirectory)){
    Write-Error "Provided Track path `"$TrackDirectory`" does not exist"
}
.$PSScriptRoot/dcs-lua-bin/luarun.exe "$PSScriptRoot/PlayerPayloadSetter.lua" "$dcsPath/" "$TrackDirectory"