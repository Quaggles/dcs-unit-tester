param(
    [switch] $GetExecutable
)
$ErrorActionPreference = "Stop"
try {
    $regPath = "Registry::HKEY_CURRENT_USER\SOFTWARE\Eagle Dynamics\DCS World"
    $dcsPath = Get-ItemPropertyValue -Path $regPath -Name path
    if ($GetExecutable) {
        $dcsPath = Join-Path $dcsPath "bin/DCS.exe"
    }
    if (Test-Path -LiteralPath $dcsPath) {
        return $dcsPath
    } else {
        throw
    }
} catch {
    Write-Error "Could not find DCS World path at $regPath"
    exit 1
}