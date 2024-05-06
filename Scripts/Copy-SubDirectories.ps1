[CmdletBinding()]
param (
    [string]$Source,
    [string]$Destination,
    [string[]]$SubPaths
)
$ErrorActionPreference = 'Stop'
foreach ($item in $SubPaths) {    
    $sourceFullName = Join-Path $Source $item
    if (!(Test-Path $sourceFullName -PathType Container)) {
        Write-Host "Source folder '$sourceFullName' does not exist. Skipping it..." -F Red
        continue;
    }
    $destinationFullName = Join-Path $Destination $item
    if (!(Test-Path $destinationFullName -PathType Container)) {
        Write-Host "Source folder '$destinationFullName' does not exist. Creating it..."        
        New-Item -Path $destinationFullName -ItemType Directory -Force | Out-Null
    }
    .$PSScriptRoot/Copy-Directory.ps1 -Source $sourceFullName -Destination $destinationFullName
}