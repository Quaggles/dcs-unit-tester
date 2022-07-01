using namespace System
using namespace System.IO
using namespace System.Diagnostics
using namespace System.Text.Json
param (
	[string] $GamePath, # Path to the game executable e.g. C:/DCS World/bin/dcs.exe
	[string] $TrackDirectory, # Filter for the tracks
	[switch] $QuitDcsOnFinish,
	[switch] $InvertAssersion, # Used for testing false negatives, will end the tests after 1 second and fail them if they report true
	[switch] $UpdateTracks, # Update scripts in the track file with those from MissionScripts/
	[switch] $Reseed, # Regenerate the track seed before playing
	[switch] $Headless, # Output TeamCity service messages
	[float] $DCSStartTimeout = 360,
	[float] $TrackLoadTimeout = 240,
	[float] $TrackPingTimeout = 30,
	[int] $RetryLimit = 2,
	[int] $RerunCount = 1
)
$ErrorActionPreference = "Stop"
Add-Type -Path "$PSScriptRoot\DCS.Lua.Connector.dll"
$connector = New-Object -TypeName DCS.Lua.Connector.LuaConnector -ArgumentList "127.0.0.1","5000"
$connector.Timeout = [TimeSpan]::FromSeconds(5)
try {
	if (-Not $GamePath) {
		Write-Host "No Game Path provided, attempting to retrieve from registry" -ForegroundColor Yellow -BackgroundColor Black
		$dcsExe = .$PSScriptRoot/dcs-find.ps1 -GetExecutable
		if (Test-Path -LiteralPath $dcsExe) {
			$GamePath = $dcsExe
			Write-Host "`tFound Game Path at $dcsExe" -ForegroundColor Green -BackgroundColor Black
		}
	else {
			Write-Host "`tRegistry points to $dcsExe but file does not exist" -ForegroundColor Red -BackgroundColor Black
		}
	}
	if (-Not $GamePath) {
		Write-Host "`tDCS path not found in registry" -ForegroundColor Red -BackgroundColor Black
		exit 1
	}

	if (-Not $TrackDirectory) {
		choice /c yn /m "Search for tracks in current directory ($PWD)?"
		if ($LASTEXITCODE -eq 1) {
			$TrackDirectory = $PWD
		}
	}
	if (-Not $TrackDirectory) {
		$trackDirectoryInput = Read-Host "Enter track directory path"
		$trackDirectoryInput = $trackDirectoryInput -replace '"', ""
		if (Test-Path $trackDirectoryInput) {
			$TrackDirectory = $trackDirectoryInput
		} else {
			Write-Host "Track Directory $TrackDirectory does not exist" -ForegroundColor Red -BackgroundColor Black
		}
	}
	if (-Not $TrackDirectory) {
		Write-Host "No track directory path set" -ForegroundColor Red -BackgroundColor Black
		exit 1
	}

	function GetProcessFromPath {
		param($Path)
		return [Path]::GetFileNameWithoutExtension($Path)
	}

	function GetProcessRunning {
		param($Path)
		return Get-Process (GetProcessFromPath $Path) -ErrorAction SilentlyContinue
	}

	function GetDCSRunning {
		return (GetProcessRunning -Path $GamePath)
	}

	function Wait-Until {
		param (
			[scriptblock] $Predicate,
			[scriptblock] $CancelIf,
			[string] $Message,
			[string] $Prefix,
			[float] $Timeout = 0,
			[scriptblock] $MessageFunction,
			[switch] $NoWaitSpinner
		)
		function ElapsedString {
			return (([DateTime]::Now - $startTime).ToString('hh\:mm\:ss'))
		}
		try {
			$startTime = ([DateTime]::Now)
			if ($Timeout -gt 0) { $waitUntil = $startTime.AddSeconds($Timeout) }
			Overwrite "$Prefix🕑 $Message - Starting" -ForegroundColor White
			while ((& $Predicate) -ne $true) {
				if ($CancelIf -and ((& $CancelIf) -eq $true)) {
					Overwrite "$Prefix❌ $Message - Cancelled ($(ElapsedString))" -ForegroundColor Red
					return $false
				}
				if ($Timeout -gt 0 -and [DateTime]::Now -gt $waitUntil) {
					Overwrite "$Prefix❌ $Message - Breached $Timeout second timeout)" -ForegroundColor Red
					return $false
				}
				if (-not $NoWaitSpinner -and $Message) {
					Overwrite "$Prefix🕑 $(Spinner) $Message - Waiting ($(ElapsedString))" -ForegroundColor Yellow
				}
			}
			if ($Message) {
				Overwrite "$Prefix✅ $Message - Complete ($(ElapsedString))" -ForegroundColor Green
			}
			return $true
		} catch [Exception] {
			if ($Message) {
				Overwrite "$Prefix❌ $Message - Failed ($(ElapsedString))" -ForegroundColor Red
			}
			throw
		}
	}

	function LoadTrack {
		param([string] $TrackPath)
		try {
			$lua = "local function ends_with(str, ending)
			return ending == '' or str:sub(-#ending) == ending
		end
		
		function DCS.startMission(filename)
		local command = 'mission'
		if ends_with(filename, '.trk') then
				command = 'track'
			end
			return _G.module_mission.play({ file = filename, command = command}, '', filename)
		end
		
		return DCS.startMission('{missionPath}')"
			$TrackPath = $TrackPath.Trim("`'").Trim("`"").Replace("`\", "/");
			return $connector.SendReceiveCommandAsync($lua.Replace('{missionPath}', $TrackPath)).GetAwaiter().GetResult()
		} catch [TimeoutException] {
			return $false;
		}
	}

	function OnMenu {
		try {
			$lua = "return DCS.getModelTime()"
			return ($connector.SendReceiveCommandAsync($lua).GetAwaiter().GetResult().Result -eq 0)
		} catch [TimeoutException] {
			return $null;
		}
	}
	function KillDCS {
		Stop-Process -Name (GetProcessFromPath($GamePath)) -Force -ErrorAction SilentlyContinue
		sleep 10
	}

	function IsTrackPlaying {
		try {
			$lua = "return DCS.isTrackPlaying()"
			return ($connector.SendReceiveCommandAsync($lua).GetAwaiter().GetResult().Result -eq 'true')
		} catch [TimeoutException] {
			return $null;
		}
	}

	function GetModelTime {
		try {
			$lua = "return DCS.getModelTime()"
			return [float]($connector.SendReceiveCommandAsync($lua).GetAwaiter().GetResult().Result)
		} catch [TimeoutException] {
			return [float]-1;
		}
	}

	function GetTrackEntry([FileInfo] $Path, $EntryPath) {
		return .$PSScriptRoot/Get-ArchiveEntry.ps1 -Path $Path -EntryPath $EntryPath
	}
	function GetSeed([FileInfo] $Path) {
		return ((.$PSScriptRoot/Get-ArchiveEntry.ps1 -Path $Path -EntryPath "track_data/seed") -replace "`n","" -replace "`r","")
	}

	function GetTrackDuration([FileInfo] $Path) {
		$regex0 = "(?m)^absoluteTime0\s*=\s*(\d+(?:\.\d+)?)"
		$regex1 = "(?m)^absoluteTime1\s*=\s*(\d+(?:\.\d+)?)"
		$data = (GetTrackEntry -Path $Path -EntryPath "track_data/times")
		if ($data -match $regex0) {
			$absoluteTime0 = $Matches[1]
		} else {
			Write-Error "Regex didn't match $data"
		}
		if ($data -match $regex1) {
			$absoluteTime1 = $Matches[1]
		} else {
			Write-Error "Regex didn't match $data"
		}
		return ($absoluteTime1 - $absoluteTime0)
	}

	function Ping {
		return ($connector.PingAsync().GetAwaiter().GetResult())
	}
	function Spinner {
		$symbols = @("/","-","\","|")
		return ($symbols[$global:spinIndex++ % $symbols.Length])
	}
	function Overwrite() {
		param(
			[string] $Text,
			[switch] $NewLine,
			$ForegroundColor = 'white',
			$BackgroundColor = 'black'
		)
		Write-Host "`r$text$(' '*(PadTextLength($text)))" -NoNewline:(!$NewLine) -ForegroundColor $ForegroundColor -BackgroundColor $BackgroundColor
	}
	function PadTextLength {
		param([string] $text)
		$textLen = 0
		for ($i=0; $i -lt $text.Length; $i++) {
			# Tab = 8 spaces
			if ($text[$i] -eq [char]9) {
				$textLen += 8
			} else {
				$textLen += 1
			}
		}
		return ($Host.UI.RawUI.WindowSize.Width - $textLen)
	}
	# Gets all the tracks in the track directory that do not start with a .
	$tracks = Get-ChildItem -Path $TrackDirectory -File -Recurse | Where-Object { $_.extension -eq ".trk" -and (-not $_.Name.StartsWith('.'))}
	$trackCount = ($tracks | Measure-Object).Count
	Write-Host "Found $($trackCount) tracks in $TrackDirectory"
	$trackProgress = 1
	$successCount = 0
	$stopwatch =  [stopwatch]::StartNew()
	$globalStopwatch =  [stopwatch]::StartNew()

	# Stack representing the subdirectory we are in, used for reporting correct nested test suites to TeamCity
	$testSuiteStack = New-Object Collections.Generic.List[string]

	# Run the tracks
	$tracks | ForEach-Object {
		# Get track information
		$relativeTestPath = $([Path]::GetRelativePath($pwd, $_.FullName))
		$testSuites = (Split-Path $relativeTestPath -Parent) -split "\\" -split "/"
		$testName = $(split-path $_.FullName -leafBase)
		$trackDuration = [float](GetTrackDuration -Path (Get-Item $_.FullName))

		# Headless client reporting
		if ($Headless) {
			# Finish any test suites we were in if they aren't in the new path
			$index = $testSuiteStack.Count - 1

			$testSuiteStack | Sort-Object -Descending {(++$script:i)} | % { # <= Reverse Loop
				if ($testSuites.Count -gt $index) {
					$peek = $testSuites[$index]
				} else {
					$peek = $null
				}
				if ($peek -ne $_) {
					$testSuiteStack.RemoveAt($index)
					Write-Host "##teamcity[testSuiteFinished name='$_']"
				}
				$index = $index - 1
			}

			# Start suites to match the new subdirectories
			$index = 0
			$testSuites | % {
				if ($testSuiteStack.Count -ge $index + 1) {
					$peek = $testSuiteStack[$index]
					if ($peek -ne $_) {
						$testSuiteStack.Add($_)
						Write-Host "##teamcity[testSuiteStarted name='$_']"
					}
				} else {
					$testSuiteStack.Add($_)
					Write-Host "##teamcity[testSuiteStarted name='$_']"
				}
				$index = $index + 1
			}
		}

		# Report Test Start
		if ($Headless) { Write-Host "##teamcity[testStarted name='$testName' captureStandardOutput='true']" }
		$stopwatch.Reset();
		$stopwatch.Start();
		$runCount = 1
		$failureCount = 0
		# Track retry loop
		while (($runCount -le $RerunCount) -and ($failureCount -le $RetryLimit)) {
			try {
				$progressMessage = "`tTrack ($trackProgress/$trackCount)"
				if ($RerunCount -gt 1) {
					$progressMessage += ", Run ($runCount/$RerunCount)"
				}
				$progressMessage += " `"$relativeTestPath`""
				if ($RetryLimit -gt 0 -and $failureCount -gt 0) {
					$progressMessage += ", failed attempts ($failureCount/$RetryLimit)"
				}
				# Progress report
				if ($Headless) {
					Write-Host "##teamcity[progressMessage '$progressMessage']"
				} else {
					Write-Host $progressMessage
				}

				# Ensure DCS is started and ready to go
				if (-not (GetDCSRunning)) {
					Write-Host "`t`t✅ Starting DCS" -F Green
					Start-Process -FilePath $GamePath -ArgumentList "-w","DCS.unittest"
					sleep 5
				}
				$started = (Wait-Until -Predicate { OnMenu -eq $true } -CancelIf { -not (GetDCSRunning) } -Prefix "`t`t" -Message "Waiting for DCS to reach main menu" -Timeout $DCSStartTimeout -NoWaitSpinner:$Headless)
				if ($started -eq $false) {
					throw [TimeoutException] "DCS did not start within $DCSStartTimeout seconds"
				}
				if ($UpdateTracks) {
					# Update scripts in the mission incase the source scripts updated
					if (!$Headless) { Write-Host "`t`tℹ️ " -NoNewline }
					.$PSScriptRoot/Set-ArchiveEntry.ps1 -Archive $_.FullName -SourceFile "$PSScriptRoot\MissionScripts\OnMissionEnd.lua" -Destination "l10n/DEFAULT/OnMissionEnd.lua"
					if (!$Headless) { Write-Host "`t`tℹ️ " -NoNewline }
					.$PSScriptRoot/Set-ArchiveEntry.ps1 -Archive $_.FullName -SourceFile "$PSScriptRoot\MissionScripts\InitialiseNetworking.lua" -Destination "l10n/DEFAULT/InitialiseNetworking.lua"
				}
				if ($Reseed) {
					# Update track seed in the mission to make it random
					$temp = New-TemporaryFile
					try {
						$oldSeed = (GetSeed -Path $_.FullName)
						$randomSeed = Get-Random -Minimum 0 -Maximum 1000000
						Set-Content -Path $temp -Value $randomSeed
						Write-Host "`t`tℹ️ Randomising track seed, Old: $oldSeed, New: $randomSeed"
						if (!$Headless) { Write-Host "`t`tℹ️ " -NoNewline }
						.$PSScriptRoot/Set-ArchiveEntry.ps1 -Archive $_.FullName -SourceFile $temp -Destination "track_data/seed"
					} finally {
						Remove-Item -Path $temp
					}
				}

				Write-Host "`t`t✅ Commanding DCS to load track" -F Green
				LoadTrack -TrackPath $_.FullName | out-null
				$output = New-Object -TypeName "System.Collections.Generic.List``1[[System.String]]";
				try {

					# Set up endpoint and start listening
					$endpoint = new-object System.Net.IPEndPoint([ipaddress]::any,1337) 
					$listener = new-object System.Net.Sockets.TcpListener $EndPoint
					$listener.start()
				
					# Wait for an incoming connection, if no connection occurs throw an exception
					$task = $listener.AcceptTcpClientAsync()
					$trackStartedPredicate = { $Task.AsyncWaitHandle.WaitOne(100) -eq $true -and (IsTrackPlaying) -and (GetModelTime -gt 0) }
					if (-not (Wait-Until -Predicate $trackStartedPredicate -CancelIf { -not (GetDCSRunning) } -Prefix "`t`t" -Message "Waiting for track to start" -Timeout $TrackLoadTimeout -NoWaitSpinner:$Headless)) {
						throw [TimeoutException] "Track did not start within timeout of $TrackLoadTimeout seconds"
					}
					$data = $task.GetAwaiter().GetResult()
					$stream = $data.GetStream() 

					# If we're doing false negative testing end the mission after 1 second to see if it returns false
					if ($InvertAssersion) {
						sleep 1
						try {
							$connector.SendReceiveCommandAsync("DCS.stopMission()").GetAwaiter().GetResult() | out-null
						} catch {
							#Ignore errors
						}
					}

					$tcpListenScriptBlock = {
						param ($Stream, $OutputList)
						$bytes = New-Object System.Byte[] 1024
						# Read data from stream and write it to host
						$EncodedText = New-Object System.Text.ASCIIEncoding
						while (($i = $Stream.Read($bytes, 0, $bytes.Length)) -ne 0) {
							$EncodedText.GetString($bytes,0, $i).Split(';') | % {
								if ($_) {
									$OutputList.Add($_)
								}
							}
						}
					}
					$job = Start-ThreadJob -ScriptBlock $tcpListenScriptBlock -ArgumentList $stream,$output -StreamingHost $Host

					# Wait for track to end loop
					$lastUpdate = [DateTime]::Now
					while ((!$job.Finished) -or (IsTrackPlaying -eq $true)) {
						$modelTime = [float](GetModelTime)
						if ($modelTime -gt $lastModelTime) {
							$lastUpdate = [DateTime]::Now
						}
						$lastUpdateDelta = (([DateTime]::Now - $lastUpdate).TotalSeconds)
						if (!$Headless) {
							$string = "`t`t🕑 $(Spinner) Waiting for track to finish {0:P0} Real: {3:N1} DCS: {1:N1}/{2:N1} seconds" -f ($modelTime/$trackDuration),$modelTime,$trackDuration,($stopwatch.Elapsed.TotalSeconds)
							Overwrite $string -ForegroundColor Yellow
						}
						if ($modelTime -gt ($trackDuration * 2)){
							throw ("DCS Track has ran for {0:N1} seconds, 2x longer than reported duration of {1:N1} seconds, aborting..." -f $modelTime,$trackDuration)
						}
						if ($lastUpdateDelta -gt $TrackPingTimeout) {
							throw [TimeoutException] ("DCS Track Unresponsive, last heard from {0:N1} seconds ago, breached {1}s timeout" -f $lastUpdateDelta,$TrackPingTimeout)
						}
						$lastModelTime = $modelTime
						# Throttle so DCS isn't checked too often
						sleep 1
					}
					if (!$Headless) {Overwrite "`t`t✅ Track Finished" -ForegroundColor Green}		
				} finally {
					# Close TCP connection and stop listening
					if ($stream) { $stream.close() }
					if ($listener) { $listener.stop() }
					if ($job) {
						$job | Stop-Job -ErrorAction SilentlyContinue
						$job | Remove-Job -ErrorAction SilentlyContinue
					}
				}
				$resultSet = $false
				# Attempt to find the unit test assersion output line
				Write-Host "`t`t📄 Output:"
				$output | % {
					if ($_ -match '^DUT_ASSERSION=(true|false)$') {
						$result = [Boolean]::Parse($Matches[1])
						$resultSet = $true
					} elseif ($_ -match '^DUT_OUTPUT=(.+)$'){
						Write-Output $Matches[1]
					} 
					Write-Host "`t`t    $_"
				}
				if ($resultSet -eq $false) {
					throw "Track did not send an assersion result, maybe crash?, assuming failed"
				}
				$runCount = $runCount + 1
			} catch {
				$resultSet = $false
				$result = $false
				Write-Host "`n`t`t❌ Error on attempt ($failureCount/$RetryLimit): $($_.ToString()), Restarting DCS`n$($_.ScriptStackTrace)" -ForegroundColor Red
				KillDCS
				$failureCount = $failureCount + 1
			}
			if ($output) { $output.Clear() }
		}
		
		if ($InvertAssersion) {
			Write-Host "`t📄 Inverting Result was $result now $(!$result)"
			$result = (!$result)
		}
		# Export result
		if ($resultSet -eq $true -and $result -eq $TRUE) {
			Write-Host "`t✅ Test ($trackProgress/$trackCount) Passed after $($stopwatch.Elapsed.ToString('hh\:mm\:ss'))" -ForegroundColor Green -BackgroundColor Black
			$successCount = $successCount + 1
		} else {
			Write-Host "`t❌ Test ($trackProgress/$trackCount) Failed after $($stopwatch.Elapsed.ToString('hh\:mm\:ss'))" -ForegroundColor Red -BackgroundColor Black
			if ($Headless) { Write-Host "##teamcity[testFailed name='$testName' duration='$($stopwatch.Elapsed.TotalMilliseconds)']" }
		}
		if ($Headless) { Write-Host "##teamcity[testFinished name='$testName' duration='$($stopwatch.Elapsed.TotalMilliseconds)']" }

		# Record tacview artifact
		$tacviewDirectory = "~\Documents\Tacview"
		if ($Headless -and (Test-Path $tacviewDirectory)) {
			$tacviewPath = gci "$tacviewDirectory\*DCS-$testName*.acmi" | sort -Descending LastWriteTime | Select -First 1
			if (-not [string]::IsNullOrWhiteSpace($tacviewPath)) {
				Write-Host "Tacview found for $testName at $tacviewPath"
				Write-Host "##teamcity[publishArtifacts '$tacviewPath']"
				$artifactPath = split-path $tacviewPath -leaf
				Write-Host "##teamcity[testMetadata testName='$testName' type='artifact' value='$artifactPath']"
			} else {
				Write-Host "Tacview not found for $testName"
			}
		}

		$trackProgress = $trackProgress + 1
	}

	# We're finished so finish the test suites
	if ($Headless) {
		$testSuiteStack | Sort-Object -Descending {(++$script:i)} | % {
			Write-Host "##teamcity[testSuiteFinished name='$_']"
		}
	}
	if ($QuitDcsOnFinish){
		sleep 2
		try {
			$connector.SendReceiveCommandAsync("return DCS.exitProcess()").GetAwaiter().GetResult() | out-null
		} catch {
			#Ignore errors
		}
	}
	Write-Host "Finished, passed tests: " -NoNewline
	if ($successCount -eq $trackCount){
		Write-Host "✅ [$successCount/$trackCount]" -F Green -B Black -NoNewline
	} else {
		Write-Host "❌ [$successCount/$trackCount]" -F Red -B Black -NoNewline
	}
	Write-Host " in $($globalStopwatch.Elapsed.ToString('hh\:mm\:ss'))";
	if (-not $Headless -and (Get-ExecutionPolicy -Scope Process) -eq 'Bypass'){
		Read-Host "Press enter to exit"
	}
} finally {
	if ($connector) { $connector.Dispose() }
}