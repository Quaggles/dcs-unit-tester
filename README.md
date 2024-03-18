# DCS Unit Tester

## Summary
A powershell script that handles opening DCS and automatically running through unit test tracks, at the end of each track an assersion is evaluated and sent back to the powershell script which marks it as a success of failure.

![image](https://user-images.githubusercontent.com/8382945/113413719-a0949380-93fe-11eb-9859-a739065cb44a.png)

Video overview of PowerShell script:

[![IMAGE ALT TEXT](https://user-images.githubusercontent.com/8382945/193401137-bde808d0-b5de-43f6-b094-60232379179d.png)](http://www.youtube.com/watch?v=NL5GRlY3plM "DCS Unit Tester Overview")

## What is it?

DCS is a massive game/simulation with hundreds of elements that come together to create a working aircraft, every single change could potentially break a system and doing regression testing for every system on every aircraft for every patch is a massive time investment. 

The track system in DCS is designed so for the player aircraft the inputs recorded during the track are simply played back in the running sim. The seed is stored and fed into any random number generators so things like flaring missiles are relatively consistent (Though obviously not all modules are equal in how well they can replay tracks and problems can occur). Usually this is a problem for players as it means that as updates come out and the behaviour of aircraft/systems/weapons change the tracks now desyncronise and don't play back correctly.

The basic idea is to create a test track with as few variables as possible apart from the ones we are testing. A mission is created with an assertion that is checked when the mission ends, as an example, for a test to check if the AIM-9X in HOBS works I created a mission with a stationary helicopter that has AI disabled, no flares and a trigger that instantly sets the player aircraft to active pause (This prevents flight model updates from invalidating the test). Then I play the mission, shoot the helicopter and export a track.

Now the track can be replayed whenever a new patch is released and report as a failure if the helicopter didn't take damage which likely means one of the related systems broke so it should be looked at.

## Limitations

The system can only test against things that exist in the mission lua environment, it cannot for example tell you if something looks visually wrong in the aircraft, tests need to be structured so they result in a quantifiable result that can be measured.

For example you could test waypoint entry and coupled autopilot modes by configuring everything and then having a an assertion that the aircraft has to fly within a 500m zone around the waypoint before a time expires. You cannot test things like "Is the CCIP reticule accurate" because by replaying the player actions even if the reticule was broken they would fly the aircraft to the same positon every time.

## How to create a test (Quick)

Video Guide: https://www.youtube.com/watch?v=D214oTs1dGg

A template miz [DUT - Template.miz](./DUT%20-%20Template.miz?raw=true) is available in this repository that tests if all Red team units are damaged by the end of the test.

When creating tests remove as many variables from each test as possible and make sure you are testing ONLY the variable that you want, as an example for my F/A-18C AIM-120 LTWS test I do the following:

* Have a trigger to set the player aircraft to active pause instantly, this prevents flight model changes from effecting the outcome of the test
* Enemy target aircraft has Task = 'nothing', Reaction to Threat = 'No Reaction', Chaff - Flare Using = 'Never Use'. This means they fly the same path every time and the minimum amount of randomness is introduced.
* Since I'm testing whether the Hornet radar works to guide the AMRAAM onto the target I make sure the target aircraft is not infront of the Hornet since if LTWS failed the missile would be fired in visual mode and might find the target without the Hornet's radar
* To mark the target as L&S I use the undesignate button (Makes highest priority target L&S) instead of slewing to the target and pressing TDC depress, this means that if ED changes the slew rate or the scale of the radar display it won't break the test

These are the types of considerations you should make when creating your tests if you want them to work across versions and be as consistent as possible which is after all the whole point of the tests. I've done some tests of CCRP bombing that break some of these rules by having the player aircraft start in active pause, I configure all systems, then escape active pause with the aircraft in an autopilot mode to fly straight, the aircraft is placed roughly 10 seconds before the CCRP release point so a minimum amount of entropy is introduced by the flight model. This has worked so far without issue but I would avoid any flight model interaction if possible.

Once your test mission is ready play through it once and successfully satisfy the assertion (Shoot the red unit), save the track and then it can be loaded by the unit tester.

## How to create a test (Detailed)

Add an `OnMissionStart` trigger that sets the player aircraft to Active Pause:

![image](https://user-images.githubusercontent.com/8382945/113410438-bdc56400-93f6-11eb-983f-6a6cebdc29c6.png)

Add an `OnMissionStart` trigger that runs a `Do Script File` on the `Scripts/InitialiseNetworking.lua` in this repository, this sets up the networking to talk to the Powershell script:

![image](https://user-images.githubusercontent.com/8382945/113411124-55778200-93f8-11eb-9f5f-4e9e516250d1.png)

To output some debug information call `Output(string)`, this prints information in the unit tester, for example you could print out `On Shot` events to see what happened in the log

To report a result use an `OnMissionEnd` trigger to call the global function `Assert(bool)`, so using just triggers you could setup:

![image](https://user-images.githubusercontent.com/8382945/113410977-fd408000-93f7-11eb-8029-e9f445c4cbe9.png)

Alternatively you can call `Do Script File` on `Scripts/OnMissionEnd.lua` located in this repository, this script asserts true if every red unit has taken some damage and will call `Output()` showing any units who survived and how much health they have

Set a mission description to explain what your test does and what the success condition is, this text is reported in the testing tool and on the WebGUI:

![image](https://user-images.githubusercontent.com/8382945/193400705-4c4c32e4-59e2-4782-bd57-49fdbda2ab59.png)

## Setup

### 0. Clone the project into a folder

`git clone https://github.com/Quaggles/dcs-unit-tester.git --recurse-submodules` or download the project zip from [here](https://github.com/Quaggles/dcs-unit-tester/archive/refs/heads/master.zip)

### 1. Configure a DCS profile for the tester

Put the `[Project Folder]\Saved Games\DCS.unittest` folder in your Saved Games folder next to your `DCS` and `DCS.openbeta` folders, this is a profile with an autoexec.cfg file that will run the tests in DCS without rendering anything and in windowed mode, this allows you to keep it in the background and work on other things.

### 2. Get some tests

[Follow the guide](https://github.com/Quaggles/dcs-unit-tester#how-to-create-a-test)

I've also created 81 tests for the F/A-18C Hornet which are [available here](https://github.com/Quaggles/dcs-unit-tests), it covers every weapon system available for the aircraft. It also tests where necessary every variant of every weapon when they have different racks, for example there used to be a bug where the AIM-9X on a single rail would work different than when loaded on a double rail, this avoids missing those peculiarities.

### 3. Install the DCS Unit Tester Mod in OVGME

[Get OVGME from here and configure it](https://wiki.hoggitworld.com/view/OVGME)

Install the mod from this repository: [DCS Unit Tester Mod - Enable SSE LuaSocket](/DCS%20Unit%20Tester%20Mod%20-%20Enable%20SSE%20LuaSocket.zip)

This mod whitelists the LuaSocket library in the Safe Scripting Environment to allow the mission track to talk over a TCP connection to the powershell script, it previously handled disabling the briefing but that is now handled automatically by the tester script calling `DCS.setPause(false)`

It also contains `DCS-LuaConnector-hook.lua` from my [DCS.Lua.Connector](https://github.com/Quaggles/DCS.Lua.Connector) system which allows the Powershell script to talk to the DCS Lua environment directly and determine if it's waiting on the menu and to tell it to load tracks.

Remember the implications of disabling the Safe Scripting Environment:
> This makes available some unsecure functions. 
> Mission downloaded from server to client may contain potentialy harmful lua code that may use these functions.

Because of this I recommend only enabling the mod when testing or developing missions

### 4. Run!

[Powershell 7 is required](https://github.com/PowerShell/PowerShell/releases/latest) since I use my [DCS.Lua.Connector](https://github.com/Quaggles/DCS.Lua.Connector) to talk to DCS and only Powershell 7 and higher can load .net 5.0 libraries

Run the script like so: `dcs-unit-tester.ps1 -TrackDirectory "C:/Path/To/Directory/Containing/Tracks"`, the script should automatically find your DCS installation through the registry but if you want to use a different one you can use the `-GamePath` argument to provide the path <b>To your DCS.exe specifically</b> don't just point it to the DCS folder

For a full list of parameters read: [PowerShell Parameters](#powershell-parameters)

The supported extensions are:
* <b>.trk</b> - Runs as a track file, ends when the track ends (Useful for testing the modules)
* <b>.miz</b> - Runs in singleplayer mission file, ends when test returns the assertion (Useful for testing scripting functions and AI)
* <b>.mp.miz</b> - Runs as a multiplayer server, ends when test returns the assertion (Useful for testing scripting functions and AI)

### 5. Observe

If you want have the game render to watch what it's doing go to `Saved Games\DCS.unittest\Config\autoexec.cfg` and comment out the line like so
```lua
-- options.graphics.render3D = false
```
Otherwise leave it set uncommented to save your power bill

Once the script has finished you should see a lot of terminal output showing the results of each test like so:
![image](https://user-images.githubusercontent.com/8382945/113414119-932bd900-93ff-11eb-8aad-a445ad953112.png)

## PowerShell Parameters
Parameter Name|Default Value|Description
--|--|--
GamePath|`HKCU\SOFTWARE\Eagle Dynamics\DCS World\Path`|Path to the game executable e.g. `C:/DCS World/bin/dcs.exe`, overrides the one found in the registry
TrackDirectory|Working Directory|Path to the directory containing tracks
QuitDcsOnFinish|false|Sets if the tester quits DCS when tests are complete
UpdateTracks|false|If enabled updates scripts in the track file with those from [MissionScripts/](/MissionScripts/), useful for keeping the networking scripts up to date across hundreds of track files
Reseed|false|If enabled regenerates the tracks RNG seed, can be used for testing things with randomness like AI decision making or weapon CEP
ReseedSeed|`[Environment]::TickCount`|Seed used for generating random seeds for track reseeding
Headless|false|If enabled outputs TeamCity service messages
DCSStartTimeout|360|Time in seconds the tester will wait for DCS to start before reporting a failure
TrackLoadTimeout|240|Time in seconds the tester will wait for the track to load before reporting a failure
TrackPingTimeout|30|Time in seconds the tester will wait between responses from the track file before reporting a failure (Detects crashes/freezes)
MissionPlayTimeout|240|Time in seconds the tester will wait for a .miz file to call Assert(), not needed for trk files as they have a predetermined end time
RetryLimit|2|How many times a track will be retried after a DCS failure (Crash\Fail to load\track freeze)
RerunCount|1|How many times the track will be run, used in combination with PassMode below
PassMode|All|Possible values:<br><b>All</b>: All runs of the test must pass for the test to report success<br><b>Majority</b>: Greater than 50% test runs must pass for the test to report success<br><b>Any</b>: At least 1 test run must pass for the test to report success<br><b>Last</b>: The result from the final test run is reported
PassModeShortCircuit|false|If enabled prevents rerunning a test more times than needed once the PassMode has been satisfied, for example with `PassMode:All` if a single test fails no more are run and the result is reported as failed immediately, helps cut down on test execution time
TimeAcceleration|1|Sets the time acceleration in each track to reduce runtime, done using AutoHotKey which sends presses of `Ctrl + Z` once the track is playing, set this to a sane number for your hardware, for complex tests above 8x on slow computers can cause track desync. This parameter overrides any time acceleration that was recorded in the track
InvertAssertion|false|If enabled tests for false negatives (A test reports success if nothing happened), will end the tests after 1 second and fail them if they report true

To override these parameters on a per test basis read: [Local track config files](#local-track-config-files)

## CreateMissionsFromTemplates.ps1

Located in the `Scripts/` folder is `CreatemissionsFromTemplates.ps1` script this simplifies creating tests for lots of weapon variants. Follow the structure in https://github.com/Quaggles/dcs-unit-tests. Create your template by naming your track `.base.trk`, put file called `payloads.lua` next to it with a format like this:

```lua
payloads = {
    ["AIM-7F Cheek"] = {
        ["pylons"] = {
            [6] = {["CLSID"] = "{AIM-7F}",},
            [4] = {["CLSID"] = "{AIM-7F}",},
        }
    },
    ["AIM-7M Cheek"] = {
        ["pylons"] = {
            [6] = {["CLSID"] = "{8D399DDA-FF81-4F14-904D-099B34FE7918}",},
            [4] = {["CLSID"] = "{8D399DDA-FF81-4F14-904D-099B34FE7918}",},
        }
    },
    ["AIM-7H Cheek"] = {
        ["pylons"] = {
            [6] = {["CLSID"] = "{AIM-7H}",},
            [4] = {["CLSID"] = "{AIM-7H}",},
        }
    },
}
```

The above example will result in 3 .trk files being created with the player having a different missile loaded in all of them.

Run the script and it will recursively search that directly and create the variants of each .trk file: `.\CreateMissionsFromTemplates.ps1 "C:\Users\Quaggles\Git\DCS\dcs-unit-tests\FA-18C"`

## Local track config files

Certain PowerShell parameters can be overridden on a per-test basis

The priority orders for parameters is as follows:
1. Local Config (Overrides all)
2. Powershell Params
3. Track File (The time acceleration that is built into the recording)

Local Config files are written in JSON and placed next to the .trk file you wish to customise, for example:

* Named `.base.json` if you want it to apply to all tests in this directory

* Named `AIM-7F Cheek.json` if you wanted to apply to a specific test in this directory

In this example the RerunCount is overridden to `10` and PassMode is set to `All`, this can be useful for flaky tests as the tester will ensure that it passes 10 runs, values set to `null` are not overridden
```json
{
	"RerunCount": 10,
	"PassMode": "All",
	"TimeAcceleration": null,
	"RetryLimit": null,
	"Reseed": null,
}
```
You could use something like this if you have a very long running test that you know will run stable with a high time acceleration set, or you could force it to 1x if you know the track can't handle time acceleration
```json
{
	"RerunCount": null,
	"PassMode": null,
	"TimeAcceleration": 16,
	"RetryLimit": null,
	"Reseed": null,
}
```
## FAQ

### I have a mission script error popup
![image](https://user-images.githubusercontent.com/8382945/113410741-7d1a1a80-93f7-11eb-85c3-fdd738a049b7.png)

This probably means you haven't installed the mod `DCS Unit Tester Mod - Enable SSE LuaSocket.zip` using OVGME, the mission will give you errors if it's not installed

### Testing mission assertions live

You can run [Receive-TCPMessage.ps1](/Receive-TCPMessage.ps1) with PowerShell while recording your track or running the tracks manually to get a live output of what your test is sending without having to run the full tester
