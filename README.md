# Win11Debloater

Windows 11 debloater, ported from [Sycnex/Windows10Debloater](https://github.com/Sycnex/Windows10Debloater)
(archived September 2023, Windows 10 era).

Removes preinstalled consumer bloatware, disables telemetry and advertising
surfaces, and turns off the Windows 11 extras: Copilot, widgets, Chat/Teams,
Start menu recommendations and web search in Start.

The original Windows 10 scripts are kept, unchanged, in [`Windows10-legacy/`](Windows10-legacy/).
What changed and why: [`WINDOWS11-MIGRATION.md`](WINDOWS11-MIGRATION.md).

## Requirements

- Windows 11 (build 22000 or later)
- PowerShell 5.1 (the built-in one - no PowerShell 7 needed)
- Administrator rights (both scripts self-elevate)

## Quick start

Always preview first. It changes nothing and needs no elevation:

```powershell
.\Win11Debloater.ps1 -Action DebloatBlacklist -DryRun
```

Then run for real, from an elevated prompt:

```powershell
.\Win11Debloater.ps1                      # interactive menu
.\Win11Debloater.ps1 -Action DebloatBlacklist
.\Win11Debloater.ps1 -Action Privacy
.\Win11Debloater.ps1 -Action Extras
```

If PowerShell refuses to run the file:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

Or double-click `Win11DebloaterGUI.ps1` for the window version.

## Actions

| Action | What it does |
|---|---|
| `Menu` | Interactive menu (default) |
| `DebloatBlacklist` | Removes the curated Windows 11 bloat list only. Recommended. |
| `DebloatAll` | Removes all non-protected Appx packages. Conservative unless `-Aggressive`. |
| `Privacy` | Telemetry, advertising ID, Bing/web search, consumer content, Recall/AI, DiagTrack, telemetry tasks |
| `Extras` | Copilot, widgets, Chat/Teams, Start recommendations, taskbar search box, update nags |
| `Revert` | Re-enables services/tasks/registry and re-registers apps still on disk |
| `Inventory` | Exports every Appx package to CSV on the Desktop and exits |

## Switches

| Switch | Effect |
|---|---|
| `-DryRun` | Report only. No changes anywhere. |
| `-Aggressive` | With `DebloatAll`, also remove unclassified leftovers. Still respects the protected list. |
| `-NoRestorePoint` | Skip the System Restore checkpoint. |
| `-NoRebootPrompt` | Do not ask to reboot at the end (for unattended runs). |
| `-KeepXbox` | Keep the Xbox app, Game Bar and Xbox services. |
| `-KeepMdmService` | Keep `dmwappushservice` (Intune / MDM enrolled machines). |
| `-DisableCopilot`, `-DisableWidgets`, `-DisableChat`, `-DisableStartAds`, `-DisableBingSearch` | Individual Windows 11 extras with `-Action Extras`. |
| `-LogPath <file>` | Where to write the transcript. Default `%ProgramData%\Win11Debloater\`. |

## Example: unattended run

```powershell
.\Win11Debloater.ps1 -Action DebloatBlacklist -NoRebootPrompt
.\Win11Debloater.ps1 -Action Privacy -NoRestorePoint -NoRebootPrompt
.\Win11Debloater.ps1 -Action Extras -NoRebootPrompt
```

## Custom blocklist

Create `custom-lists.ps1` next to `Win11Debloater.ps1` (regex fragments, matched
against package names):

```powershell
$global:ExtraBloat = @(
    'Microsoft\.YourPhone'
    'SomeVendor\.SomeApp'
)
```

Both the console and the GUI pick it up automatically.

## What is protected

Nothing matching these is ever removed, whatever the switches say:

`MicrosoftWindows.*` (Windows 11 shell), `Microsoft.Windows.Client.*`,
`Microsoft.WindowsStore`, `Microsoft.DesktopAppInstaller` (winget),
`Microsoft.WindowsAppRuntime.*`, `Microsoft.UI.Xaml`, `Microsoft.VCLibs`,
`Microsoft.NET.Native`, `Microsoft.Windows.ShellExperienceHost`,
`Microsoft.Windows.StartMenuExperienceHost`, `Microsoft.Windows.SecHealthUI`
(Defender), `Microsoft.Windows.Search`, and anything the package catalog itself
flags as `NonRemovable` or `IsFramework`.

Calculator, Store, Photos, Camera, Notepad, Terminal, Paint, Snipping Tool,
Media Player, Voice Recorder and the media extensions are on the keep list -
removable by hand, never by `DebloatAll`.

## Files

```
Win11Debloater.ps1           console / interactive
Win11DebloaterGUI.ps1        WinForms front-end
lib/Win11Debloat.Core.ps1    shared functions (both entry points use this)
WINDOWS11-MIGRATION.md       change log and verification results
Windows10-legacy/            the original Windows 10 scripts, untouched
```

## Before you run it

Removing Appx packages uninstalls apps and their local data. Make sure System
Restore is enabled, or take an image first, and read the `-DryRun` output.
Scripts are provided as-is, no warranty - same terms as upstream.

## Licence

MIT, inherited from the upstream project. Original work by Sycnex and
contributors.
