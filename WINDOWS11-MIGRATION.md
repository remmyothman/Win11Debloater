# Windows 11 migration notes

What changed from the Windows 10 original, why, and what was verified.
Branch: `win11`. Original scripts preserved untouched in `Windows10-legacy/`.

## Why a port was needed

`Sycnex/Windows10Debloater` was archived in September 2023 and targets Windows 10.
Running it unchanged on Windows 11 fails in ways that range from noisy to
destructive. The problems found by reading the code and testing against a live
Windows 11 build (26H2, build 26300.9457):

| # | Problem in the original | Effect on Windows 11 |
|---|---|---|
| 1 | `DebloatAll` removes every Appx package that is not on a 2018-era whitelist | Wipes `MicrosoftWindows.Client.*`, `Microsoft.WindowsAppRuntime.*`, `Microsoft.UI.Xaml.*` and the `MicrosoftWindows.NNNNNNNN.*` shell packages. Result: no Start menu, no Settings, no Explorer. |
| 2 | Package list is 2018-era | Half the names no longer exist (`Microsoft.Messaging`, `Microsoft.OneConnect`, `Microsoft.Print3D`, `Microsoft.Windows.Cortana`). Each miss writes a red error but keeps going, so the log is unreadable. |
| 3 | Real Windows 11 bloat is missing | Copilot, Dev Home, new Outlook, Clipchamp, Phone Link, Chat/Teams, Family, Quick Assist, Power Automate are all untouched. |
| 4 | `DisableCortana`, People band, Wi-Fi Sense, Mixed Reality | Cortana is gone from Windows 11, `PeopleBand` does nothing, Wi-Fi Sense was removed in 2018, WMR is deprecated. Dead code that implies protection you do not get. |
| 5 | `Get-ScheduledTask Consolidator \| Disable-ScheduledTask` | Tasks are looked up by bare name. If one is missing the whole statement errors. Newer builds rename Application Experience tasks, so name matching silently misses telemetry tasks. |
| 6 | `DisableDiagTrack` and `DisableWAPPush` are called in the menu | Both functions are **not defined anywhere** in the file. Selecting "Yes" in the interactive menu throws `CommandNotFoundException` twice per run. |
| 7 | `Remove-Keys` deletes `HKCR:` keys with no existence check | Errors on every missing key; on Windows 11 most of them are missing. |
| 8 | `AllowTelemetry = 0` | Only honoured on Enterprise/Education. On Pro/Home Windows 11 clamps to Required (1). The original implies full telemetry off; that is not what happens. |
| 9 | Revert re-registers all Appx packages | `Add-AppxPackage -Register` on 280 packages throws hundreds of errors on Windows 11 and cannot restore anything that was deprovisioned. |

## What the port does

### Structure

The original kept two full copies of the debloat logic (console + GUI), which is
why bug #6 existed in one place and not the other. Now:

```
Win11Debloater.ps1          console + interactive menu
Win11DebloaterGUI.ps1       WinForms front-end
lib/Win11Debloat.Core.ps1   all functions - single source of truth
```

The GUI dot-sources the library and overrides `Write-Log` so output lands in its
log pane. Neither entry point owns logic any more.

### Removal safety

Two independent gates before anything is removed:

1. `$_.NonRemovable` and `$_.IsFramework` from the package catalog itself.
2. A regex protected list, including the families the original had no idea about:
   `MicrosoftWindows.*` (the Windows 11 shell), `Microsoft.Windows.Client.*`,
   `Microsoft.WindowsAppRuntime.*`, `Microsoft.WinAppRuntime.*`, `Microsoft.UI.Xaml`,
   `Microsoft.VCLibs`, `Microsoft.DesktopAppInstaller` (winget),
   `Microsoft.Windows.ShellExperienceHost`, `StartMenuExperienceHost`,
   `SecHealthUI` (Defender), and GUID-named system packages.

`DebloatAll` also defaults to the curated list. The "remove everything" path needs
`-Aggressive` or an explicit `YES` in the menu, and still honours both gates.

Every removal is existence-checked first, so absent packages are reported as
skipped instead of throwing.

### Windows 11 specific work

Removed (was Windows 10 only): Cortana app, People band, Wi-Fi Sense, Mixed
Reality Portal activation, `AllowTelemetry` theatre, live tiles.

Added:

- **Copilot** - `ShowCopilotButton`, `TurnOffWindowsCopilot` policy (24H2).
- **Widgets** - `TaskbarDa`, `AllowNewsAndInterests` (machine policy + user policy).
- **Chat / Teams** - `TaskbarMn`, optional package removal. Work Teams (`MSTeams`)
  is deliberately left in place; only the consumer Chat app is removed.
- **Start menu** - `Start_IrisRecommendations`, `Start_AccountNotifications`,
  `HideRecommendedSection`.
- **Search** - `BingSearchEnabled`, `DisableWebSearch`, `ConnectedSearchUseWeb`,
  `SearchboxTaskbarMode`.
- **Recall / AI** - `DisableAIDataAnalysis`, `AllowRecallEnablement` (24H2+).
- **Consumer content** - `SubscribedContent-*`, `DisableWindowsConsumerFeatures`,
  `SilentInstalledAppsEnabled`, `SoftLandingEnabled`.
- **Edge nudges** - `ShowRecommendationsEnabled`, `EdgeShoppingAssistantEnabled`.
- **Updates nag** - `IsContinuousInnovationOptedIn`.

Scheduled tasks are disabled by **path** and iterate whatever is actually there,
so obfuscated task names are still caught, and missing tasks cannot break the run.

### Operations

- `-DryRun` - full report, zero changes. Works without elevation.
- Restore point before the first change, unless `-NoRestorePoint`.
- Transcript log in `%ProgramData%\Win11Debloater\`.
- `-Action Inventory` - CSV of every package with `NonRemovable`, `IsFramework`
  and whether this script would protect it.
- Summary counters: removed / skipped / failed / settings / tasks / services.
- Elevation is parameter-preserving (the original dropped its arguments when
  self-elevating).

## Verification performed

On Windows 11 Pro 26H2, build 26300.9457, PowerShell 5.1:

| Check | Result |
|---|---|
| AST parse of all three files | pass, no syntax errors |
| `-Action DebloatBlacklist -DryRun` | 30 packages matched, 1 skipped, 0 failed |
| `-Action Privacy -DryRun` | 47 registry values, 14 tasks, 2 services |
| `-Action Extras -DryRun` | 14 registry values, package removals identified |
| `-Action Inventory` | 282 packages exported, 196 flagged protected |
| Function reference audit | 0 undefined calls (the original had 2) |
| GUI `-SelfTest` | form builds, 9 top-level / 17 grouped controls |
| GUI launched at 125% DPI | all 4 groups, 17 buttons, log and status line render without clipping |

Nothing was actually removed from the test machine - every removal path was
exercised in `-DryRun` only.

## Known limits

- `AllowTelemetry = 0` is written anyway, but Windows 11 Pro/Home clamps it to 1.
  DiagTrack is disabled and the telemetry tasks are disabled instead.
- Revert restores registry, services, tasks and re-registers apps still on disk.
  Packages removed with `-IncludeProvisioned` can only come back from the Store.
- `-UnpinStart` uses the `LockedStartLayout` method. It still works on 24H2/25H2
  but is undocumented, so it is opt-in (menu option 6) rather than part of the
  default flow.
- The GUI is DPI-aware and scales its fixed layout itself; it was checked at 125%
  only. 150%/200% should scale the same way but is untested.
- `Individual Scripts/` from the original is Windows 10 era and was moved to
  `Windows10-legacy/` rather than audited line by line.
