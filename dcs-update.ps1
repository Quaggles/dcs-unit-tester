[CmdletBinding()]
param (
    $DcsPath,
    $Version = "latest",
    [int] $Timeout = 3600,
    [int] $RetryAttempts = 10
)
$ErrorActionPreference = 'Stop'
function Get-AutoUpdaterJson() {
  $autoupdateJson = Get-Content -Raw $autoupdatePath | ConvertFrom-Json
  if ($null -eq $autoupdateJson) {
      throw "Could not read $autoupdatePath json"
  }
  return $autoupdateJson
}
function Start-Updater([String[]] $ArgumentList) {
    $ArgumentList += "--quiet"
    Write-Host "Running $updaterPath $($ArgumentList | Join-String -Separator " ")"
    $process = Start-Process $updaterPath -ArgumentList $ArgumentList -PassThru
    $timeouted = $null # reset any previously set timeout
    $process | Wait-Process -Timeout $Timeout -ErrorAction SilentlyContinue -ErrorVariable timeouted
    if ($timeouted) {
        Write-Host "Timeout breached, killing updater"
        # terminate the process
        $process | Stop-Process
    }
}
function Get-FormedVersion($json) {
    return "$($json.version)@$($json.branch)"
}
function Get-ProcessRunning {
    $process = Get-Process "DCS" -ErrorAction SilentlyContinue
    $process | % {
        $parent = Get-Item $DcsPath
        $child = Get-Item $_.Path
        # Make sure we are checking only the DCS process from this game directory
        if ($child.FullName.Contains($parent.FullName)) {
            return $_
        }
    }
}
if ([string]::IsNullOrWhiteSpace($Version)) {
    $Version = "none"
}
if (-not (Test-Path $DcsPath)) {
    throw "No DCS Path provided"
}
$autoupdatePath = Join-Path $DcsPath "autoupdate.cfg"
if (-not (Test-Path $autoupdatePath)) {
    throw "Could not find $autoupdatePath"
}
$updaterPath = Join-Path $DcsPath "bin/DCS_Updater.exe"
if (-not (Test-Path $DcsPath)) {
    throw "Could not find $DcsPath"
}

# Ensure DCS isn't running
$process = Get-ProcessRunning
if ($process) {
	Write-Host "DCS Running, closing it"
	$process | Stop-Process
    sleep 5
}
$currentJson = Get-AutoUpdaterJson
Write-Host "Requested DCS version: $Version, Current: $(Get-FormedVersion $currentJson)"

# Remove temp files
Remove-Item -Path "$DcsPath\_downloads\" -Recurse -Force -Confirm:$false -ErrorAction SilentlyContinue
Remove-Item -Path "$DcsPath\_backup.*\" -Recurse -Force -Confirm:$false -ErrorAction SilentlyContinue
$attemptNumber = 0
$correctVersionFound = $true
if ($Version -eq "latest") {
    if ($env:TEAMCITY_VERSION) {
        Write-Host "##teamcity[progressMessage 'Updating to latest DCS version']"
    }
    Start-Updater "update"
    $currentJson = Get-AutoUpdaterJson
} elseif ($Version -match '([0-9.]*)@([a-z_.]+)') {
    if ($env:TEAMCITY_VERSION) {
        Write-Host "##teamcity[progressMessage 'Updating to $Version']"
    }
    $requestedVersion = $Matches[1]
    $requestedBranch = $Matches[2]
    $correctVersionFound = $false
    do {
        try {
            $attemptNumber = $attemptNumber + 1
            Write-Host "Attempt $attemptNumber/$RetryAttempts to update to $Version"
            if ($env:TEAMCITY_VERSION) {
                Write-Host "##teamcity[progressMessage 'Updating to $Version, attempt ($attemptNumber/$RetryAttempts)']"
            }
            Start-Updater "update","$Version" 
            $currentJson = Get-AutoUpdaterJson
            # Check version
            if (-not ([string]::IsNullOrWhiteSpace($requestedVersion))) {
                if ($currentJson.version -eq $requestedVersion) {
                    $correctVersionFound = $true
                    break
                }
            } else { # Check branch
                if ($currentJson.branch -eq $requestedBranch) {
                    $correctVersionFound = $true
                    break
                }
            }
            throw "Matching version not found"
        } catch {
            # Wait a minute before retry
            sleep 60
        }
    } while ($attemptNumber -lt $RetryAttempts -or $RetryAttempts -lt 0)
    if ($correctVersionFound -eq $false) {
        if ($env:TEAMCITY_VERSION) {
            Write-Host "##teamcity[progressMessage 'Updating to version $Version failed after $attemptNumber attempts)']"
        }
        throw "Could not update to requested version"
    }
} elseif ($Version -eq "none") {
    $currentJson = Get-AutoUpdaterJson
    # Ignore
} else {
    throw "Invalid version requested"
}
return $currentJson