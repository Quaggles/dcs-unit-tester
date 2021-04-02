# DCS Unit Tester

## Summary
A powershell script that handles opening DCS and automatically running through unit test tracks, at the end of each track an assersion is evaluated and sent back to the powershell script which marks it as a success of failure.

![image](https://user-images.githubusercontent.com/8382945/113413719-a0949380-93fe-11eb-9859-a739065cb44a.png)

## What is it?

DCS is a massive game/simulation with hundreds of elements that come together to create a working aircraft, every single change could potentially break a system and doing regression testing for every system on every aircraft for every patch is a massive time investment. 

The track system in DCS is designed so for the player aircraft the inputs recorded during the track are simply played back in the running sim. The seed is stored and fed into any random number generators so things like flaring missiles are relatively consistent (Though obviously not all modules are equal in how well they can replay tracks and problems can occur). Usually this is a problem for players as it means that as updates come out and the behaviour of aircraft/systems/weapons change the tracks now desyncronise and don't play back correctly.

The basic idea is to create a test track with as few variables as possible apart from the ones we are testing. A mission is created with an assertion that is checked when the mission ends, as an example, for a test to check if the AIM-9X in HOBS works I created a mission with a stationary helicopter that has AI disabled, no flares and a trigger that instantly sets the player aircraft to active pause (This prevents flight model updates from invalidating the test). Then I play the mission, shoot the helicopter and export a track.

Now the track can be replayed whenever a new patch is released and report as a failure if the helicopter didn't take damage which likely means one of the related systems broke so it should be looked at.

## Limitations

The system can only test against things that exist in the mission lua environment, it cannot for example tell you if something looks visually wrong in the aircraft, tests need to be structured so they result in a quantifiable result that can be measured.

For example you could test waypoint entry and coupled autopilot modes by configuring everything and then having a an assersion that the aircraft has to fly within a 500m zone around the waypoint before a time expires. You cannot test things like "Is the CCIP reticule accurate" because by replaying the player actions even if the reticule was broken they would fly the aircraft to the same positon every time.

## How to create a test

A template miz `DUT - Template.miz` is available in this repository that tests if all Red team units are damaged by the end of the test.

When creating tests remove as many variables from each test as possible and make sure you are testing ONLY the variable that you want, as an example for my F/A-18C AIM-120 LTWS test I do the following:

* Have a trigger to set the player aircraft to active pause instantly, this prevents flight model changes from effecting the outcome of the test
* Enemy target aircraft has Task = 'nothing', Reaction to Threat = 'No Reaction', Chaff - Flare Using = 'Never Use'. This means they fly the same path every time and the minimum amount of randomness is introduced.
* Since I'm testing whether the Hornet radar works to guide the AMRAAM onto the target I make sure the target aircraft is not infront of the Hornet since if LTWS failed the missile would be fired in visual mode and might find the target without the Hornet's radar
* To mark the target as L&S I use the undesignate button (Makes highest priority target L&S) instead of slewing to the target and pressing TDC depress, this means that if ED changes the slew rate or the scale of the radar display it won't break the test

These are the types of considerations you should make when creating your tests if you want them to work across versions and be as consistent as possible which is after all the whole point of the tests. I've done some tests of CCRP bombing that break some of these rules by having the player aircraft start in active pause, I configure all systems, then escape active pause with the aircraft in an autopilot mode to fly straight, the aircraft is placed roughly 10 seconds before the CCRP release point so a minimum amount of entropy is introduced by the flight model. This has worked so far without issue but I would avoid any flight model interaction if possible.

Once your test mission is ready play through it once and successfully satisfy the assersion (Shoot the red unit), save the track and then it can be loaded by the unit tester.

## How to create a test (Detailed)

Add an `OnMissionStart` trigger that sets the player aircraft to Active Pause:

![image](https://user-images.githubusercontent.com/8382945/113410438-bdc56400-93f6-11eb-983f-6a6cebdc29c6.png)

Add an `OnMissionStart` trigger that runs a `Do Script File` on the `Scripts/InitialiseNetworking.lua` in this repository, this sets up the networking to talk to the Powershell script:

![image](https://user-images.githubusercontent.com/8382945/113411124-55778200-93f8-11eb-9f5f-4e9e516250d1.png)

To output some debug information call `Output(string)`, this prints information in the unit tester, for example you could print out `On Shot` events to see what happened in the log

To report a result use an `OnMissionEnd` trigger to call the global function `Assert(bool)`, so using just triggers you could setup:

![image](https://user-images.githubusercontent.com/8382945/113410977-fd408000-93f7-11eb-8029-e9f445c4cbe9.png)

Alternatively you can call `Do Script File` on `Scripts/OnMissionEnd.lua` located in this repository, this script asserts true if every red unit has taken some damage and will call `Output()` showing any units who survived and how much health they have

## Setup

1. Configure a DCS profile for the tester

Put the `Saved Games\DCS.unittest` folder in your Saved Games folder next to your `DCS` and `DCS.openbeta` folders, this is a profile with an autoexec.cfg file that will run the tests in DCS without rendering anything and in windowed mode, this allows you to keep it in the background and work on other things.

It also contains `DCS-LuaConnector-hook.lua` from my [DCS.Lua.Connector](https://github.com/Quaggles/DCS.Lua.Connector) system which allows the Powershell script to talk to the DCS Lua environment directly and determine if it's waiting on the menu and to tell it to load tracks.

2. Get some tests

I've created 81 tests for the F/A-18C Hornet which are [available here](https://github.com/Quaggles/dcs-unit-tests), it covers every weapon system available for the aircraft. It also tests where necessary every variant of every weapon when they have different racks, for example there used to be a bug where the AIM-9X on a single rail would work different than when loaded on a double rail, this avoids missing those peculiarities.

3. Install the DCS Unit Tester Mod in OVGME

In the repository as `DCS Unit Tester Mod - Disable SSE and Briefing.zip`

This does two things, disables the safe scripting environment to allow the mission track to talk over a TCP connection to the powershell script and also mods the game to skip any briefings that would show up at the start of a track and wait for user input

Remember the implications of disabling the Safe Scripting Environment:
> This makes available some unsecure functions. 
> Mission downloaded from server to client may contain potentialy harmful lua code that may use these functions.

Because of this I recommend only enabling the mod when testing or developing missions

4. Run!

[Powershell 7 is required](https://github.com/PowerShell/PowerShell/releases/latest) since I use my [DCS.Lua.Connector](https://github.com/Quaggles/DCS.Lua.Connector) to talk to DCS and only Powershell 7 and higher can load .net 5.0 libraries

Run the script like so: `dcs-unit-tester.ps1 -TrackDirectory "C:/Path/To/Directory/Containing/Tracks"`, the script should automatically find your DCS installation through the registry but if you want to use a different one you can use the `-GamePath` argument to provide the path <b>To your DCS.exe specifically</b> don't just point it to the DCS folder

5. Observe

If you want have the game render to watch what it's doing go to `Saved Games\DCS.unittest\Config\autoexec.cfg` and comment out the line like so
```lua
-- options.graphics.render3D = false
```
Otherwise leave it set uncommented to save your power bill

Once the script has finished you should see a lot of terminal output showing the results of each test like so:
![image](https://user-images.githubusercontent.com/8382945/113414119-932bd900-93ff-11eb-8aad-a445ad953112.png)

## FAQ

### I have a mission script error popup
![image](https://user-images.githubusercontent.com/8382945/113410741-7d1a1a80-93f7-11eb-85c3-fdd738a049b7.png)

This probably means you haven't installed the mod `DCS Unit Tester Mod - Disable SSE and Briefing.zip` using OVGME, the mission will give you errors if it's not installed
