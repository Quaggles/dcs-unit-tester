[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [string]
    $Path
)
$ErrorActionPreference = "Stop"
Get-ChildItem -Path $Path -Include "*.trk" -Recurse | % {
    $path = Get-Item $_
    .$PSScriptRoot/Set-ArchiveEntry.ps1 -Archive $path -SourceFile "$PSScriptRoot\MissionScripts\OnMissionEnd.lua" -Destination "l10n/DEFAULT/OnMissionEnd.lua" -CheckContent
    .$PSScriptRoot/Set-ArchiveEntry.ps1 -Archive $path -SourceFile "$PSScriptRoot\MissionScripts\InitialiseNetworking.lua" -Destination "l10n/DEFAULT/InitialiseNetworking.lua" -CheckContent
}