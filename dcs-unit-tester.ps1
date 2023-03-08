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
	[int] $ReseedSeed = [Environment]::TickCount, # Seed used for generating random seeds
	[switch] $Headless, # Output TeamCity service messages
	[float] $DCSStartTimeout = 360,
	[float] $TrackLoadTimeout = 240,
	[float] $TrackPingTimeout = 30,
	[float] $MissionPlayTimeout = 240, # Timeout for when a mission calls Assert()
	[int] $RetryLimit = 2,
	[int] $RerunCount = 1,
	[ValidateSet("All","Majority","Any","Last")]
	[string] $PassMode = "All",
	[Boolean] $PassModeShortCircuit = $false,
	[int] $TimeAcceleration,
	[int] $SetKeyDelay = 0
)

class SkipTestException : Exception { }

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

	function TeamCitySafeString([string] $Value) {
		$Value = $Value.Replace("|","||")
		$Value = $Value.Replace("'","|'")
		$Value = $Value.Replace("`n","|n")
		$Value = $Value.Replace("`r","|r")
		$Value = $Value.Replace("[","|[")
		$Value = $Value.Replace("]","|]")
		return $Value
	}

	function Wait-Until {
		param (
			[scriptblock] $Predicate,
			[scriptblock] $CancelIf,
			[string] $Message,
			[string] $Prefix,
			[float] $Timeout = 0,
			[scriptblock] $MessageFunction,
			[switch] $NoWaitSpinner,
			[scriptblock] $RunEach
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
				if ($RunEach) {
					(& $RunEach)
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
		param([string] $TrackPath, [switch]$Multiplayer)
		$TrackPath = $TrackPath.Trim("`'").Trim("`"").Replace("`\", "/");
		if ($Multiplayer) {
			$lua = Get-Content -Path "$PSScriptRoot/Scripts/DCS.startMissionMultiplayer.lua" -Raw
		} else {
			$lua = Get-Content -Path "$PSScriptRoot/Scripts/DCS.startMission.lua" -Raw
		}
		$result = ($connector.SendReceiveCommandAsync($lua.Replace('{missionPath}', $TrackPath)).GetAwaiter().GetResult())
		if ($result.Status -eq "RuntimeError"){
			throw [InvalidOperationException] "Error Loading ${testType}: $($result.Result)"
		}
	}

	function OnMenu {
		try {
			return ($connector.SendReceiveCommandAsync("return DCS.getSimulatorMode()").GetAwaiter().GetResult().Result -eq '1')
		} catch [TimeoutException] {
			return $null;
		}
	}
	function KillDCS {
		$dcsPid = $null
		Stop-Process -Name (GetProcessFromPath($GamePath)) -Force -ErrorAction SilentlyContinue
		sleep 10
	}

	function IsTrackPlaying {
		param([switch]$Mission)
		try {
			if ($Mission) {
				return ($connector.SendReceiveCommandAsync("return DCS.getSimulatorMode()").GetAwaiter().GetResult().Result -eq '4')
			} else {
				return ($connector.SendReceiveCommandAsync("return DCS.isTrackPlaying()").GetAwaiter().GetResult().Result -eq 'true')
			}
		} catch [TimeoutException] {
			return $null;
		}
	}

	function GetModelTime {
		try {
			return [float]($connector.SendReceiveCommandAsync("return DCS.getModelTime()").GetAwaiter().GetResult().Result)
		} catch [TimeoutException] {
			return [float]-1;
		}
	}

	function GetPause {
		try {
			$result = ($connector.SendReceiveCommandAsync("return DCS.getPause()").GetAwaiter().GetResult().Result)
			if ($result -eq "true") {
				return $true
			} elseif ($result -eq "false") {
				return $false
			} else {
				return $null;
			}
		} catch [TimeoutException] {
			return $null;
		}
	}

	function SetPause([Boolean] $Paused) {
		try {
			return ($connector.SendReceiveCommandAsync("return DCS.setPause($Paused)").GetAwaiter().GetResult().Result)
		} catch [TimeoutException] {
			return $false;
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
			return $null
		}
		if ($data -match $regex1) {
			$absoluteTime1 = $Matches[1]
		} else {
			return $null
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
	$tacviewDirectory = "~\Documents\Tacview"
	# Clear tacview folder
	if ($Headless -and (Test-Path $tacviewDirectory)) {
		Get-ChildItem -Path $tacviewDirectory | Remove-Item
	}
	$TrackDirectory = $TrackDirectory.Replace("\","/")
	# Gets all the tracks in the track directory that do not start with a .
	# Load Test tracks must be run first
	$loadTestTracks = @(Get-ChildItem -Path $TrackDirectory -File -Recurse | Where-Object { $_.extension -eq ".trk" -and ($_.Name.StartsWith('LoadTest.'))})
	# Regular tests are run last
	$normalTracks = @(Get-ChildItem -Path $TrackDirectory -File -Recurse | Where-Object { $_.extension -in ".trk",".miz" -and (-not $_.Name.StartsWith('.')) -and (-not $_.Name.StartsWith('LoadTest.'))})
	$tracks = $loadTestTracks + $normalTracks
	$trackCount = ($tracks | Measure-Object).Count
	Write-Host "Found $($trackCount) tracks in $TrackDirectory"
	# Stores which modules passed the load test
	$loadableModules = @{}
	$trackProgress = 1
	$trackSuccessCount = 0
	$stopwatch =  [stopwatch]::StartNew()
	$globalStopwatch =  [stopwatch]::StartNew()

	# Stack representing the subdirectory we are in, used for reporting correct nested test suites to TeamCity
	$testSuiteStack = New-Object Collections.Generic.List[string]

	# Initialise Seed
	if ($ReseedSeed) {
		Write-Host "Initialising seed to $ReseedSeed for any reseed operations"
		Get-Random -Minimum 0 -Maximum 1000000 -SetSeed $ReseedSeed | Out-Null
	}
	# Run the tracks
	$tracks | ForEach-Object {
		# Get track information
		$relativeTestPath = $([Path]::GetRelativePath($pwd, $_.FullName))
		$testSuites = (Split-Path $relativeTestPath -Parent) -split "\\" -split "/"
		$config = $null
		$configPathTemplate = Join-Path -Path (split-path $_.FullName -Parent) -ChildPath "/.base.json"
		$configPath = [System.IO.Path]::ChangeExtension($_.FullName, ".json")
		if (Test-Path -Path $configPath) {
			Write-Host "`tℹ️ Loading Config File: $([Path]::GetRelativePath($pwd, $configPath))"
			$config = ConvertFrom-Json (Get-Content -Path $configPath -Raw)
		} elseif (Test-Path -Path $configPathTemplate) {
			Write-Host "`tℹ️ Loading Config File: $([Path]::GetRelativePath($pwd, $configPathTemplate))"
			$config = ConvertFrom-Json (Get-Content -Path $configPathTemplate -Raw)
		}

		$isTrack = $($_.Extension -eq ".trk")
		$testType="Track"
		$isMultiplayer = $false
		if ($isTrack -eq $false) {
			$isMultiplayer = $($_.BaseName.EndsWith(".mp"))
			if ($isMultiplayer -eq $true){
				$testType="Mission (MP)"
			} else {
				$testType="Mission (SP)"
			}
		} 

		$testName = $(split-path $_.FullName -leafBase)
		if ($isTrack) {
			$trackDuration = [float](GetTrackDuration -Path (Get-Item $_.FullName))
		} else {
			$trackDuration = $null
		}
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
		if ($Headless) {
			Write-Host "##teamcity[testStarted name='$testName' captureStandardOutput='true']"
		}
		$stopwatch.Reset();
		$stopwatch.Start();
		$runCount = 1
		$failureCount = 0
		$successCount = 0

		function SetConfigVar([PSCustomObject] $Config, $OriginalValue, [string] $VariableName) {
			if (-not $Config.PSObject.Properties) { return $OriginalValue }
			$prop = $Config.PSObject.Properties[$VariableName]
			if ($prop -and $prop.Value) {
				Write-Host "`tℹ️ Config: $VariableName = $($prop.Value)"
				return $prop.Value
			} else {
				return $OriginalValue
			}
		}
		$localRerunCount = SetConfigVar $config $RerunCount "RerunCount"
		$localTimeAcceleration = SetConfigVar $config $TimeAcceleration "TimeAcceleration"
		$localRetryLimit = SetConfigVar $config $RetryLimit "RetryLimit"
		$localReseed = SetConfigVar $config $Reseed "Reseed"
		$localPassMode = SetConfigVar $config $PassMode "PassMode"
		# Track retry loop
		while (($runCount -le $localRerunCount) -and ($failureCount -le $localRetryLimit)) {
			try {
				$progressMessage = "`Test ($trackProgress/$trackCount)"
				if ($localRerunCount -gt 1) {
					$progressMessage += ", Run ($runCount/$localRerunCount)"
				}
				$progressMessage += " `"$relativeTestPath`""
				if ($localRetryLimit -gt 0 -and $failureCount -gt 0) {
					$progressMessage += ", failed attempts ($failureCount/$localRetryLimit)"
				}
				# Progress report
				if ($Headless) {
					Write-Host "##teamcity[progressMessage '$progressMessage']"
				} else {
					Write-Host $progressMessage
				}

				# Track Description
				$trackDescription = $null
				try {
					$trackDescription = (."$PSScriptRoot/Scripts/Get-MissionDescription.ps1" -TrackPath $_.FullName)
					if ([string]::IsNullOrWhiteSpace($trackDescription)) {
						throw "Description existed but was empty"
					}
					Write-Host "`t`t✅ $testType Description Retrieved: " -F Green
					Write-Host $trackDescription
				} catch {
					Write-Host "`t`t❌ Failed to get $testType description: $_" -F Red
				}
				if ($Headless -and -not [string]::IsNullOrWhiteSpace($trackDescription)) {
					Write-Host "##teamcity[testMetadata testName='$testName' name='Description' value='$(TeamCitySafeString -Value $trackDescription)']"
				}

				# Retrieve player aircraft from track
				$playerAircraftType = $null
				try {
					$playerAircraftType = (."$PSScriptRoot/Scripts/Get-PlayerAircraftType.ps1" -TrackPath $_.FullName)
					if ([string]::IsNullOrWhiteSpace($playerAircraftType) -or ($playerAircraftType -eq "nil")) {
						throw "Player aircraft type could not be retrieved"
					}
					Write-Host "`t`t✅ Player aircraft type Retrieved: $playerAircraftType" -F Green
				} catch {
					Write-Host "`t`t❌ Failed to get player aircraft type: $_" -F Red
				}
				if ($Headless -and -not [string]::IsNullOrWhiteSpace($playerAircraftType)) {
					Write-Host "##teamcity[testMetadata testName='$testName' name='PlayerAircraftType' value='$(TeamCitySafeString -Value $playerAircraftType)']"
				}

				# Determine if track is a LoadTest
				$isLoadTest = $_.Name.StartsWith("LoadTest.")

				# Ensure DCS is started and ready to go
				if (-not (GetDCSRunning)) {
					Write-Host "`t`t✅ Starting DCS" -F Green
					$dcsPid = (Start-Process -FilePath $GamePath -ArgumentList "-w","DCS.unittest" -PassThru).Id
					sleep 5
				} else { # Fallback if we didn't start the process
					$dcsPid = (GetDCSRunning).Id
				}
				$started = (Wait-Until -Predicate { OnMenu -eq $true } -CancelIf { -not (GetDCSRunning) } -Prefix "`t`t" -Message "Waiting for DCS to reach main menu" -Timeout $DCSStartTimeout -NoWaitSpinner:$Headless)
				if ($started -eq $false) {
					throw [TimeoutException] "DCS did not load to main menu"
				}
				if ($UpdateTracks) {
					# Update scripts in the mission incase the source scripts updated
					if (!$Headless) { Write-Host "`t`tℹ️ " -NoNewline }
					.$PSScriptRoot/Set-ArchiveEntry.ps1 -Archive $_.FullName -SourceFile "$PSScriptRoot\MissionScripts\OnMissionEnd.lua" -Destination "l10n/DEFAULT/OnMissionEnd.lua"
					if (!$Headless) { Write-Host "`t`tℹ️ " -NoNewline }
					.$PSScriptRoot/Set-ArchiveEntry.ps1 -Archive $_.FullName -SourceFile "$PSScriptRoot\MissionScripts\InitialiseNetworking.lua" -Destination "l10n/DEFAULT/InitialiseNetworking.lua"
				}
				if ($localReseed -and $isTrack) {
					# Update track seed in the mission to make it random
					$temp = New-TemporaryFile
					try {
						$oldSeed = (GetSeed -Path $_.FullName)
						$randomSeed = Get-Random -Minimum 0 -Maximum 1000000
						Set-Content -Path $temp -Value $randomSeed
						Write-Host "`t`tℹ️ Randomising $testType seed, Old: $oldSeed, New: $randomSeed"
						if (!$Headless) { Write-Host "`t`tℹ️ " -NoNewline }
						.$PSScriptRoot/Set-ArchiveEntry.ps1 -Archive $_.FullName -SourceFile $temp -Destination "track_data/seed"
					} finally {
						Remove-Item -Path $temp
					}
				}

				try {
					$output = New-Object -TypeName "System.Collections.Generic.List``1[[System.String]]";
					# Skip test if load test failed
					if (-not $isLoadTest -and $loadableModules[$playerAircraftType] -eq $false) {
						throw [SkipTestException]::new()
					}
					Write-Host "`t`t✅ Commanding DCS to load $testType" -F Green
					LoadTrack -TrackPath $_.FullName -Multiplayer:$isMultiplayer
					# Set up endpoint and start listening
					$endpoint = new-object System.Net.IPEndPoint([ipaddress]::any,1337) 
					$listener = new-object System.Net.Sockets.TcpListener $EndPoint
					$listener.start()
				
					# Wait for an incoming connection, if no connection occurs throw an exception
					$task = $listener.AcceptTcpClientAsync()
					if (-not (Wait-Until -Predicate {$task.AsyncWaitHandle.WaitOne(100) -eq $true} -CancelIf { -not (GetDCSRunning) } -Prefix "`t`t" -Message "Waiting for TCP Connection" -Timeout $TrackLoadTimeout -NoWaitSpinner:$Headless)) {
						throw [TimeoutException] "$testType did not establish a TCP Connection"
					}
					$trackStartedPredicate = { ((IsTrackPlaying -Mission:(-not $isTrack)) -eq $true) }
					if (-not (Wait-Until -Predicate $trackStartedPredicate -CancelIf { -not (GetDCSRunning) } -Prefix "`t`t" -Message "Waiting for $testType to load" -Timeout $TrackLoadTimeout -NoWaitSpinner:$Headless)) {
						throw [TimeoutException] "$testType did not finish loading"
					}
					if ($isMultiplayer -eq $false) { # Multiplayer starts playing and without a briefing so skip waiting for it to play
						$trackUnpausedPredicate = {
							$paused = (GetPause)
							return ($paused -ne $null -and $paused -eq $false -and (GetModelTime -gt 0))
						}
						if (-not (Wait-Until -Predicate $trackUnpausedPredicate -CancelIf { -not (GetDCSRunning) } -RunEach { SetPause -Paused $false } -Prefix "`t`t" -Message "Waiting for $testType to play" -Timeout $TrackLoadTimeout -NoWaitSpinner:$Headless)) {
							throw [TimeoutException] "$testType did not play"
						}
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
									# Tells the mission to stop since this isn't a track it won't end by itself
									if ((-not $using:isTrack) -and ($_ -match '^DUT_ASSERSION=(true|false)$')) {
										if ($using:isMultiplayer) {
											($using:connector).SendReceiveCommandAsync("return net.stop_game()").GetAwaiter().GetResult().Result
											($using:connector).SendReceiveCommandAsync("return net.stop_network()").GetAwaiter().GetResult().Result
											# sleep 1
											# # Backs out of the server browser
											# Start-Process -FilePath "$($using:PSScriptRoot)/SendKeys.exe" -ArgumentList "$($using:DcsPid)",0,"{Esc}"
										} else {
											($using:connector).SendReceiveCommandAsync("return DCS.stopMission()").GetAwaiter().GetResult().Result
										}
										return
									}
								}
							}
						}
					}
					$job = Start-ThreadJob -ScriptBlock $tcpListenScriptBlock -ArgumentList $stream,$output -StreamingHost $Host
					# Use AutoHotkey script to tell DCS to increase time acceleration
					if ($dcsPid -and $localTimeAcceleration -and -not $InvertAssersion) {
						Write-Host "`t`tℹ️ Setting Time Acceleration to $($localTimeAcceleration)x"
						# Argument 1 is PID, argument 2 is delay in ms
						$sendKeysArguments = @("$dcsPid",$SetKeyDelay)
						# ^z = Ctrl + Z
						for ($i = 0; $i -lt ($localTimeAcceleration - 1); $i++) {
							$sendKeysArguments += "^z"
						}
						Start-Process -FilePath "$PSScriptRoot/SendKeys.exe" -ArgumentList $sendKeysArguments
					}

					# Wait for track to end loop
					$lastUpdate = [DateTime]::Now
					$sleepTime = 1
					while ((!$job.Finished) -or ((IsTrackPlaying -Mission:(-not $isTrack)) -ne $false)) {
						$modelTime = [float](GetModelTime)
						if ($modelTime -gt $lastModelTime) {
							$lastUpdate = [DateTime]::Now
							$timeAccel = ([float]$modelTime - [float]$lastModelTime) / [float]$sleepTime
							if ($timeAccel -gt 0.75){
								$timeAccel = [math]::Round($timeAccel)
							}
						}
						$lastUpdateDelta = (([DateTime]::Now - $lastUpdate).TotalSeconds)
						if (!$Headless) {
							$string = "`t`t🕑 $(Spinner) Waiting for $testType to finish {0:P0} Real: {3:N1} DCS: {1:N1}/{2:N1} seconds, x{4:N2} acceleration" -f ($modelTime/$trackDuration),$modelTime,(($null -eq $trackDuration) ? "?" : $trackDuration),($stopwatch.Elapsed.TotalSeconds),$timeAccel
							Overwrite $string -ForegroundColor Yellow
						}
						if (($null -ne $trackDuration) -and $modelTime -gt ($trackDuration * 2)){
							throw [TimeoutException] ("DCS $testType has ran for {0:N1} seconds, 2x longer than reported duration of {1:N1} seconds, aborting..." -f $modelTime,$trackDuration)
						}
						if ($lastUpdateDelta -gt $TrackPingTimeout) {
							throw [TimeoutException] ("DCS $testType Unresponsive, last heard from {0:N1} seconds ago, breached {1}s timeout" -f $lastUpdateDelta,$TrackPingTimeout)
						}
						if ((-not $isTrack) -and ($modelTime -gt $MissionPlayTimeout)){
							throw [TimeoutException] ("DCS $testType has ran for {0:N1} seconds without reporting an assersion, this is longer than the MissionPlayTimeout of {1:N1} seconds, aborting..." -f $modelTime,$MissionPlayTimeout)
						}
						$lastModelTime = $modelTime
						# Throttle so DCS isn't checked too often
						sleep $sleepTime
					}
					if (!$Headless) {Overwrite "`t`t✅ $testType Finished ($($stopwatch.Elapsed.ToString('hh\:mm\:ss')))" -ForegroundColor Green}		
				} catch [SkipTestException] {
					$output.Add("Skipped test as aircraft load test failed")
					$output.Add("DUT_ASSERSION=false")
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
				$output | ForEach-Object {
					if ($_ -match '^DUT_ASSERSION=(true|false)$') {
						$result = [Boolean]::Parse($Matches[1])
						$resultSet = $true
					} elseif ($_ -match '^DUT_OUTPUT=(.+)$'){
						Write-Output $Matches[1]
					} 
					Write-Host "`t`t    $_"
				}
				if ($Headless) {
					Write-Host "##teamcity[testMetadata testName='$testName' name='DCS restarts required' type='number' value='$(TeamCitySafeString -Value $failureCount)']"
				}
				if ($resultSet -eq $false) {
					throw "$testType did not send an assersion result, maybe crash?, assuming failed"
				}
				$runCount = $runCount + 1
			} catch {
				$resultSet = $false
				$result = $false
				Write-Host "`n`t`t❌ Error on attempt ($failureCount/$localRetryLimit): $($_.ToString()), Restarting DCS`n$($_.ScriptStackTrace)" -ForegroundColor Red
				KillDCS
				$failureCount = $failureCount + 1
			}
			if ($InvertAssersion) {
				Write-Host "`t📄 Inverting Result was $result now $(!$result)"
				$result = (!$result)
			}
			if ($resultSet -eq $true) {
				if ($result -eq $TRUE){
					$successCount = $successCount + 1
					if ($PassModeShortCircuit -and $localPassMode -eq "Any" -or ($localPassMode -eq "Majority" -and $successCount -gt ($localRerunCount/2))) {
						Write-Host "`t`t Skipping remaining reruns because PassMode:$localPassMode has determined the final result via short circuit"
						break
					}
				} else {
					if ($PassModeShortCircuit -and $localPassMode -eq "All") {
						Write-Host "`t`t Skipping remaining reruns because PassMode:$localPassMode has determined the final result via short circuit"
						break
					}
				}
			}
			if ($output) { $output.Clear() }
		}

		# Export result
		if ($localPassMode -eq "All") {
			$result = ($successCount -eq $localRerunCount)
		} elseif ($localPassMode -eq "Majority") {
			$result = ($successCount -gt ($localRerunCount/2))
		} elseif ($localPassMode -eq "Any") {
			$result = ($successCount -gt 0)
		} else {
			$result = ($resultSet -eq $true -and $result -eq $TRUE)
		}
		$passMessage = "PassMode:$localPassMode [$successCount/$localRerunCount] {0:P0}" -f ($successCount/$localRerunCount)
		if ($result -eq $TRUE) {
			Write-Host "`t✅ Test ($trackProgress/$trackCount) Passed, $passMessage after ($($stopwatch.Elapsed.ToString('hh\:mm\:ss')))" -ForegroundColor Green -BackgroundColor Black
			$trackSuccessCount = $trackSuccessCount + 1
		} else {
			Write-Host "`t❌ Test ($trackProgress/$trackCount) Failed, $passMessage after ($($stopwatch.Elapsed.ToString('hh\:mm\:ss')))" -ForegroundColor Red -BackgroundColor Black
			if ($Headless) { Write-Host "##teamcity[testFailed name='$testName' duration='$($stopwatch.Elapsed.TotalMilliseconds)']" }
		}
		# Record the load test result in a dictionary
		if ($isLoadTest) {
			if ($result -eq $TRUE){
				Write-Host "`t✅ Load test for $playerAircraftType set to $result" -ForegroundColor Green
			} else {
				Write-Host "`t❌ Load test for $playerAircraftType set to $result" -ForegroundColor Red
			}
			$loadableModules[$playerAircraftType] = $result
		}
		if ($Headless) { Write-Host "##teamcity[testFinished name='$testName' duration='$($stopwatch.Elapsed.TotalMilliseconds)']" }

		if ($Headless) {
			# Record tacview artifact
			if (Test-Path $tacviewDirectory) {
				$tacviewPath = gci "$tacviewDirectory\Tacview-*$testName*.acmi" | sort -Descending LastWriteTime | Select -First 1
				if (-not [string]::IsNullOrWhiteSpace($tacviewPath)) {
					Write-Host "Tacview found for $testName at $tacviewPath"
					Write-Host "##teamcity[publishArtifacts '$tacviewPath']"
					$artifactPath = split-path $tacviewPath -leaf
					Write-Host "##teamcity[testMetadata testName='$testName' type='artifact' value='$(TeamCitySafeString -Value $artifactPath)']"
				} else {
					Write-Host "Tacview not found for $testName"
				}
			}
			# If test failed upload the track as an artifact
			if ($result -eq $false) {
				Write-Host "##teamcity[publishArtifacts '$($_.FullName)']"
				$artifactPath = split-path $_.FullName -leaf
				Write-Host "##teamcity[testMetadata testName='$testName' type='artifact' value='$(TeamCitySafeString -Value $artifactPath)']"
			}
		}
		
		try {
			$started = (Wait-Until -Predicate { OnMenu -eq $true } -CancelIf { -not (GetDCSRunning) } -Prefix "`t" -Message "Waiting for DCS to return to main menu" -Timeout $DCSStartTimeout -NoWaitSpinner:$Headless)
			if ($started -eq $false) {
				throw [TimeoutException] "DCS did not return to main menu"
			}
		} catch {
			Write-Host "`t❌ $($_.ToString()), Restarting DCS" -ForegroundColor Red
			KillDCS
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
	if ($trackSuccessCount -eq $trackCount){
		Write-Host "✅ [$trackSuccessCount/$trackCount]" -F Green -B Black -NoNewline
	} else {
		Write-Host "❌ [$trackSuccessCount/$trackCount]" -F Red -B Black -NoNewline
	}
	Write-Host " in $($globalStopwatch.Elapsed.ToString('hh\:mm\:ss'))";
	if (-not $Headless -and (Get-ExecutionPolicy -Scope Process) -eq 'Bypass'){
		Read-Host "Press enter to exit"
	}
} finally {
	if ($connector) { $connector.Dispose() }
}