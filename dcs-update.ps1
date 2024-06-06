[CmdletBinding()]
param (
    $DcsPath,
    $Version = "latest",
    [string[]] $Modules,
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
function EscapeTeamcity([string] $Message) {
    $Message = $Message.Replace("|","||");
    $Message = $Message.Replace("'","|'");
    $Message = $Message.Replace("`n","|n");
    $Message = $Message.Replace("`r","|r");
    $Message = $Message.Replace("[","|[");
    $Message = $Message.Replace("]","|]");
    return $Message;
}
function Start-ThreadJobHere([scriptblock]$ScriptBlock, [object[]]$ArgumentList) {
    Start-ThreadJob -Init ([ScriptBlock]::Create("Set-Location '$pwd'")) -Script $ScriptBlock -ArgumentList $ArgumentList -StreamingHost $Host
}
function Start-Updater([String[]] $ArgumentList) {
    $ArgumentList += "--quiet"
    if ($env:TEAMCITY_VERSION) {
        $logPath = "$env:temp/DCS/autoupdate_templog.txt"
        # Start a job to monitor the log file once it is created
        $logMonitorJob = Start-ThreadJobHere -ArgumentList $logPath -ScriptBlock {
            param([string] $File)
            ${function:EscapeTeamcity} = ${using:function:EscapeTeamcity}
            Write-host "##teamcity[compilationStarted compiler='DCS Updater Log']"
            try {
                Write-Host "##teamcity[message text='$(EscapeTeamcity -Message "Waiting for $File to exist and be modified")']"
                $startDate = Get-Date
                while (-not (Test-Path -LiteralPath $File) -or ((Get-Item -LiteralPath $File).LastWriteTime -lt $startDate)) {
                    sleep 10
                }
                Write-Host "##teamcity[message text='$(EscapeTeamcity -Message "Tailing $File")']"
                Get-Content $File -Wait | ForEach-Object { Write-Host "##teamcity[message text='$(EscapeTeamcity -Message $_)']" }
            } catch {
                Write-Host "Error during log monitoring:`n$_" -F Red
                throw
            } finally {
                Write-Host "##teamcity[compilationFinished compiler='DCS Updater Log']"
            }
        }
    }
    # Run the update when it finishes force the log monitor to stop
    try {
        Write-Host "Running $updaterPath $($ArgumentList | Join-String -Separator " ")"
        $process = Start-Process $updaterPath -ArgumentList $ArgumentList -PassThru
        $timeouted = $null # reset any previously set timeout
        $process | Wait-Process -Timeout $Timeout -ErrorAction SilentlyContinue -ErrorVariable timeouted
    } finally {
        if ($logMonitorJob) {
            # Allow 3 seconds for file to buffer before stopping
            sleep 3;
            $logMonitorJob | Stop-Job
            $logMonitorJob = $null
        }
    }

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
            Write-Host "Attempt $attemptNumber/$RetryAttempts failed, waiting 60 seconds before retry, reason:`n`n$_`n" -F Red
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
function Get-MissingModules() {
    $currentJson = Get-AutoUpdaterJson
    $missingModules = @()
    foreach ($module in $Modules) {
        if (-not $currentJson.modules.Contains("$module")) {
            $missingModules += $module
        }
    }
    return $missingModules
}
if ($null -ne $Modules) {
    $missingModules = Get-MissingModules
    if ($missingModules.Length -gt 0) {
        if ($env:TEAMCITY_VERSION) {
            Write-Host "##teamcity[progressMessage 'Installing modules: $($missingModules -join ", ")']"
        }
        Write-Host "Following modules are not installed: $($missingModules -join ", ")"
        Start-Updater "install",$($missingModules -join " ")
        $missingModules = Get-MissingModules
        if ($missingModules.Length -gt 0) {
            Write-Host "Following modules failed to be installed: $($missingModules -join ", ")" -F Red
        } else {
            Write-Host "Modules successfully installed: $($missingModules -join ", ")" -F Green
        }
    } else {
        Write-Host "All required modules were installed"
    }
}
return $currentJson