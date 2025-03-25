param(
    [switch] $GetExecutable,
    [string] $ExecutableSubpath = "bin/DCS.exe"
)
$ErrorActionPreference = "Stop"
try {
    if (![string]::IsNullOrWhiteSpace($env:DUT_DCS_Path)) {
        $dcsPath = $env:DUT_DCS_Path
    } else {
        $regPath = "Registry::HKEY_CURRENT_USER\SOFTWARE\Eagle Dynamics\DCS World"
        $dcsPath = Get-ItemPropertyValue -Path $regPath -Name path
    }
    if ($GetExecutable) {
        $dcsPath = Join-Path $dcsPath $ExecutableSubpath
    }
    if (Test-Path -LiteralPath $dcsPath) {
        return $dcsPath
    } else {
        if ($GetExecutable) {
            throw [System.IO.FileNotFoundException] "File not found at: ""$dcsPath"""
        } else {
            throw [System.IO.DirectoryNotFoundException] "Directory not found at: ""$dcsPath"""
        }
    }
} catch {
    Write-Error "Could not find DCS World path, $_"
    exit 1
}