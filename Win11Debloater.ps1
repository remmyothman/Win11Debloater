param(
    [ValidateSet('Menu', 'DebloatAll', 'DebloatBlacklist', 'Privacy', 'Extras', 'Revert', 'Inventory')]
    [string]$Action = 'Menu',

    [switch]$DryRun,
    [switch]$Aggressive,
    [switch]$NoRestorePoint,
    [switch]$NoRebootPrompt,
    [switch]$KeepXbox,
    [switch]$KeepMdmService,
    [switch]$KeepSearchService,
    [switch]$UninstallOneDrive,
    [switch]$UnpinStart,
    [switch]$Remove3dObjects,
    [switch]$DisableTelemetry,
    [switch]$DisableCopilot,
    [switch]$DisableWidgets,
    [switch]$DisableChat,
    [switch]$DisableStartAds,
    [switch]$DisableBingSearch,

    [string]$LogPath,

    # Diagnostics: write the elevation launcher this build would use and exit.
    # Mainly for testing the piped (irm | iex) path without a UAC prompt.
    [string]$EmitElevationLauncher
)

$ErrorActionPreference = 'Continue'

# >>> LIBRARY LOADER (tools\Build-Standalone.ps1 replaces this block with lib\Win11Debloat.Core.ps1)
$script:StandaloneUrl = ''
$corePath = Join-Path $PSScriptRoot 'lib\Win11Debloat.Core.ps1'
if (!(Test-Path $corePath)) {
    Write-Host "Missing library: $corePath" -ForegroundColor Red
    Write-Host 'If you piped this script into iex, use dist\Win11Debloater.standalone.ps1 instead.'
    exit 1
}
. $corePath

if (![string]::IsNullOrEmpty($PSScriptRoot)) {
    $customLists = Join-Path $PSScriptRoot 'custom-lists.ps1'
    if (Test-Path $customLists) { . $customLists }
}
# <<< LIBRARY LOADER

# Switches the caller passed, so elevation can re-apply them.
$script:BoundArgs = $PSBoundParameters

# --------------------------------------------------------------------------
# Main
# --------------------------------------------------------------------------

Initialize-Log

$info = Get-Win11Info
$productLabel = $info.ProductName
if ($info.IsWindows11) { $productLabel = $productLabel -replace 'Windows 10', 'Windows 11' }  # registry string is stale on Win11
Write-Log ("Windows: {0} {1} build {2}.{3}" -f $productLabel, $info.DisplayVer, $info.Build, $info.UBR)
if (!$info.IsWindows11) {
    Write-Log 'This build is NOT Windows 11 (build < 22000). The package lists are tuned for Windows 11 and may behave oddly on Windows 10.' 'WARN'
}

if (![string]::IsNullOrEmpty($EmitElevationLauncher)) {
    try {
        New-ElevationLauncher -Path $EmitElevationLauncher | Out-Null
        Write-Log "elevation launcher written: $EmitElevationLauncher" 'OK'
    }
    catch {
        Write-Log "could not write launcher: $($_.Exception.Message)" 'ERROR'
    }
    Stop-Log
    exit
}

if (!(Test-Admin)) {
    if ($DryRun) {
        Write-Log 'Not elevated - dry run continues, but Appx state will be read-only.' 'WARN'
    }
    else {
        Stop-Log
        if (Invoke-SelfElevate) { }
        exit
    }
}
Write-Log 'Running elevated.' 'OK'

if ($DryRun) { Write-Log 'DRY RUN: no changes will be made.' 'DRY' }

$script:ProtectedPatterns = Get-ProtectedAppxPatterns
$script:ProtectedNames = Get-ProtectedPackageName
Write-Log ("loaded {0} protected package name(s) and {1} protected pattern(s)" -f @($script:ProtectedNames).Count, @($script:ProtectedPatterns).Count)

# Mount HKCR once - needed for leftover key cleanup and reads
if (!(Get-PSDrive -Name HKCR -ErrorAction SilentlyContinue)) {
    New-PSDrive -Name HKCR -PSProvider Registry -Root HKEY_CLASSES_ROOT -Scope Global -ErrorAction SilentlyContinue | Out-Null
}

switch ($Action) {
    'Inventory' { Show-Inventory; Show-Summary; Stop-Log; exit }

    'DebloatBlacklist' {
        New-DebloatRestorePoint
        Invoke-DebloatBlacklist
        Remove-LeftoverKeys
    }

    'DebloatAll' {
        New-DebloatRestorePoint
        Invoke-DebloatAll
        Remove-LeftoverKeys
        if ($DisableTelemetry) { Disable-TelemetryTasks }
    }

    'Privacy' {
        New-DebloatRestorePoint
        Invoke-Privacy
    }

    'Extras' {
        New-DebloatRestorePoint
        if ($DisableCopilot) { Disable-Copilot }
        if ($DisableWidgets) { Disable-Widgets }
        if ($DisableChat) { Disable-ChatTaskbar }
        if ($DisableStartAds) { Disable-StartAds }
        if ($DisableBingSearch) { Disable-BingSearch }
        Invoke-Win11Extras
    }

    'Revert' {
        Invoke-Revert
    }

    'Menu' {
        Show-Menu
        $choice = Read-Host 'Select an option'
        switch ($choice) {
            '1' { New-DebloatRestorePoint; Invoke-DebloatBlacklist; Remove-LeftoverKeys }
            '2' {
                $confirm = Read-Host 'This removes every Appx package that is not on the protected or keep list. Type YES to continue'
                if ($confirm -eq 'YES') { $Aggressive = [switch]$true; New-DebloatRestorePoint; Invoke-DebloatAll }
                else { Write-Log 'aggressive removal cancelled' 'WARN' }
            }
            '3' { New-DebloatRestorePoint; Invoke-Privacy }
            '4' { New-DebloatRestorePoint; Invoke-Win11Extras }
            '5' { New-DebloatRestorePoint; Uninstall-OneDrive }
            '6' { Set-UnpinStart }
            '7' { Remove-3DObjects }
            '8' { Show-Inventory }
            '9' { Invoke-Revert }
            '0' { Write-Log 'exiting' }
            default { Write-Log "unknown option: $choice" 'WARN' }
        }
    }
    default { }
}

Show-Summary

if (!$NoRebootPrompt -and !$DryRun -and $Action -ne 'Inventory') {
    $ans = Read-Host 'Reboot now to finish applying changes? (y/N)'
    if ($ans -match '^(y|Y)') {
        Write-Log 'rebooting'
        Stop-Log
        Restart-Computer -Force
    }
}

Stop-Log
