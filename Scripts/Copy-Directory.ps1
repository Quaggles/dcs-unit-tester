[CmdletBinding()]
param (
    [string]$Source,
    [string]$Destination,
    [string[]]$Include
)
$ErrorActionPreference = 'Stop'

# Check if both source and destination folders exist
if (!(Test-Path $Source -PathType Container)) {
    Write-Error "Source folder doesn't exist."
    exit
}
$Source = (Get-Item $Source).FullName

if (!(Test-Path $Destination -PathType Container)) {
    New-Item -Path $Destination -ItemType Directory -Force | Out-Null
}
$Destination = (Get-Item $Destination).FullName

# Get all files and directories in the source folder
$sourceItems = Get-ChildItem $Source -Recurse -Include $Include

# Loop through each item
foreach ($item in $sourceItems) {
    # Determine the destination path for each item
    $destinationPath = $item.FullName -replace [regex]::Escape($Source), $Destination
    # If item is a file, copy it to the destination folder
    if ($item.PSIsContainer -eq $false) {        
        $containingFolder = $item.Directory -replace [regex]::Escape($Source), $Destination
        if (-not (Test-Path -LiteralPath $containingFolder -PathType Container)) {
            Write-Verbose  "Creating missing parent directory structure: $containingFolder"
            New-Item -Path $containingFolder -ItemType Directory
        }
        # Copy file
        Write-Verbose "Copying file '$destinationPath'"
        Copy-Item -Path $item.FullName -Destination $destinationPath -Force
    }
    # If item is a directory, create it in the destination folder
    elseif (-not (Test-Path $destinationPath -PathType Container)) {
        Write-Verbose "Creating directory '$destinationPath'"
        New-Item -Path $destinationPath -ItemType Directory -Force | Out-Null
    }
}
