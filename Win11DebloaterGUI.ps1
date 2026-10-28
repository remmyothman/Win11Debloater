<#
.SYNOPSIS
    Win11DebloaterGUI.ps1 - WinForms front-end for Win11Debloater (Windows 11).

.DESCRIPTION
    Same visual language as the original Windows10Debloater GUI (dark, flat,
    Consolas) but it no longer carries its own copy of the debloat logic.
    Every button calls the shared library in lib\Win11Debloat.Core.ps1, so the
    console script and the GUI can never drift apart again.

    Buttons are non-blocking enough to use interactively: each action writes to
    the log pane and refreshes the status bar.

.PARAMETER DryRun
    Start in preview mode. Buttons log what they would do and change nothing.

.PARAMETER SelfTest
    Build the form, force handle creation, report the control count, exit.
    Used to verify the GUI parses and constructs without showing a window.

.NOTES
    Requires Windows 11 and an elevated session (the script self-elevates).
#>

[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$SelfTest,
    [switch]$KeepXbox
)

$ErrorActionPreference = 'Continue'

# --------------------------------------------------------------------------
# Elevation
# --------------------------------------------------------------------------

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $pr = New-Object Security.Principal.WindowsPrincipal($id)
    return $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (!(Test-Admin) -and !$SelfTest) {
    $args = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"")
    if ($DryRun) { $args += '-DryRun' }
    Start-Process -FilePath 'powershell.exe' -ArgumentList $args -Verb RunAs
    exit
}

# --------------------------------------------------------------------------
# Shared library
# --------------------------------------------------------------------------

$corePath = Join-Path $PSScriptRoot 'lib\Win11Debloat.Core.ps1'
if (!(Test-Path $corePath)) {
    [System.Windows.Forms.MessageBox]::Show("Missing library:`n$corePath", 'Win11Debloater', 'OK', 'Error') | Out-Null
    exit 1
}
. $corePath

$customLists = Join-Path $PSScriptRoot 'custom-lists.ps1'
if (Test-Path $customLists) { . $customLists }

$script:GuiLogFile = Join-Path $env:ProgramData 'Win11Debloater\gui.log'
if (!(Test-Path (Split-Path $script:GuiLogFile))) {
    New-Item -Path (Split-Path $script:GuiLogFile) -ItemType Directory -Force | Out-Null
}

# The GUI is created below; the log sink is swapped in once the pane exists.
$script:LogBox = $null

# Override the library's console logger so output lands in the window instead
# of a hidden console host. Defined after the dot-source, so this wins.
function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')

    $stamp = (Get-Date).ToString('HH:mm:ss')
    $line = "[$stamp][$Level] $Message"

    try { Add-Content -Path $script:GuiLogFile -Value $line -ErrorAction SilentlyContinue } catch { }

    if ($null -ne $script:LogBox -and !$script:LogBox.IsDisposed) {
        $script:LogBox.AppendText($line + "`r`n")
        $script:LogBox.SelectionStart = $script:LogBox.TextLength
        $script:LogBox.ScrollToCaret()
        [System.Windows.Forms.Application]::DoEvents()
    }
}

function Update-StatusBar {
    if ($null -eq $script:StatusLabel -or $script:StatusLabel.IsDisposed) { return }
    $mode = 'APPLY'
    if ($DryRun) { $mode = 'PREVIEW ONLY' }
    $script:StatusLabel.Text = ("{0}  |  removed {1}  skipped {2}  failed {3}  settings {4}  tasks {5}  services {6}" -f `
            $mode, $script:Stats.Removed, $script:Stats.Skipped, $script:Stats.Failed, $script:Stats.Settings, $script:Stats.Tasks, $script:Stats.Services)
}

function Invoke-GuiAction {
    param(
        [scriptblock]$Action,
        [string]$Label,
        [switch]$RecreateAppxCache
    )
    try {
        if ($RecreateAppxCache) { $script:AppxCache = $null }
        & $Action
    }
    catch {
        Write-Log "$Label failed: $($_.Exception.Message)" 'ERROR'
    }
    Update-StatusBar
}

# --------------------------------------------------------------------------
# Form
# --------------------------------------------------------------------------

Add-Type -AssemblyName System.Windows.Forms, System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# Tell Windows we draw at physical pixels so the window is not bitmap-scaled
# (blurry) on 125% / 150% displays. Layout is then scaled by WinForms itself.
Add-Type @"
using System.Runtime.InteropServices;
public class DpiNative {
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
}
"@
try { [void][DpiNative]::SetProcessDPIAware() } catch { }

$bg = [System.Drawing.ColorTranslator]::FromHtml('#252525')
$fg = [System.Drawing.ColorTranslator]::FromHtml('#eeeeee')
$btnBg = [System.Drawing.ColorTranslator]::FromHtml('#333333')
$border = [System.Drawing.ColorTranslator]::FromHtml('#555555')
$accent = [System.Drawing.ColorTranslator]::FromHtml('#7ec8e3')
$headerFont = New-Object System.Drawing.Font('Consolas', 12, [System.Drawing.FontStyle]::Bold)
$bodyFont = New-Object System.Drawing.Font('Consolas', 9)
$smallFont = New-Object System.Drawing.Font('Consolas', 8)

$Form = New-Object System.Windows.Forms.Form
$Form.ClientSize = New-Object System.Drawing.Point(620, 800)
$Form.StartPosition = 'CenterScreen'
$Form.FormBorderStyle = 'FixedSingle'
$Form.MaximizeBox = $false
$Form.ShowIcon = $false
$Form.Text = 'Win11Debloater'
$Form.BackColor = $bg
$Form.ForeColor = $fg
$Form.Font = $bodyFont
$Form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::None

$Title = New-Object System.Windows.Forms.Label
$Title.Text = 'WINDOWS 11 DEBLOATER'
$Title.AutoSize = $true
$Title.Location = New-Object System.Drawing.Point(12, 10)
$Title.Font = New-Object System.Drawing.Font('Consolas', 15, [System.Drawing.FontStyle]::Bold)
$Title.ForeColor = $accent

$info = Get-Win11Info
$SubTitle = New-Object System.Windows.Forms.Label
$SubTitle.Text = ("{0} {1}  build {2}.{3}   |   ported from Sycnex/Windows10Debloater" -f $info.ProductName.Replace('Windows 10', 'Windows 11'), $info.DisplayVer, $info.Build, $info.UBR)
$SubTitle.AutoSize = $true
$SubTitle.Location = New-Object System.Drawing.Point(14, 40)
$SubTitle.Font = $smallFont
$SubTitle.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#999999')

function New-Group {
    param([string]$Text, [int]$X, [int]$Y, [int]$W, [int]$H)
    $g = New-Object System.Windows.Forms.GroupBox
    $g.Text = $Text
    $g.Location = New-Object System.Drawing.Point($X, $Y)
    $g.Size = New-Object System.Drawing.Size($W, $H)
    $g.ForeColor = $accent
    $g.Font = $bodyFont
    return $g
}

function New-Button {
    param([string]$Text, [int]$X, [int]$Y, [int]$W, [int]$H = 30)
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $Text
    $b.Location = New-Object System.Drawing.Point($X, $Y)
    $b.Size = New-Object System.Drawing.Size($W, $H)
    $b.FlatStyle = 'Flat'
    $b.BackColor = $btnBg
    $b.ForeColor = $fg
    $b.FlatAppearance.BorderColor = $border
    $b.FlatAppearance.MouseOverBackColor = [System.Drawing.ColorTranslator]::FromHtml('#3f3f3f')
    $b.Font = $bodyFont
    $b.Cursor = [System.Windows.Forms.Cursors]::Hand
    return $b
}

# --- DEBLOAT ---
$DebloatGroup = New-Group 'DEBLOAT' 12 64 596 108
$BtnBlacklist = New-Button 'REMOVE BLOATWARE (CURATED)' 12 26 280
$BtnAll = New-Button 'REMOVE ALL NON-PROTECTED' 304 26 280
$BtnPreview = New-Button 'PREVIEW: WHAT WOULD BE REMOVED' 12 62 572
$DebloatGroup.Controls.AddRange(@($BtnBlacklist, $BtnAll, $BtnPreview))

# --- PRIVACY ---
$PrivacyGroup = New-Group 'PRIVACY & TELEMETRY' 12 180 596 108
$BtnPrivacy = New-Button 'APPLY PRIVACY HARDENING' 12 26 280
$BtnTelemetry = New-Button 'DISABLE TELEMETRY TASKS + SERVICES' 304 26 280
$BtnRevert = New-Button 'REVERT ALL CHANGES' 12 62 572
$PrivacyGroup.Controls.AddRange(@($BtnPrivacy, $BtnTelemetry, $BtnRevert))

# --- WINDOWS 11 EXTRAS ---
$ExtrasGroup = New-Group 'WINDOWS 11 EXTRAS' 12 296 596 144
$BtnCopilot = New-Button 'COPILOT OFF' 12 26 180
$BtnWidgets = New-Button 'WIDGETS OFF' 200 26 180
$BtnChat = New-Button 'CHAT / TEAMS OFF' 388 26 196
$BtnStartAds = New-Button 'START MENU ADS OFF' 12 62 180
$BtnBing = New-Button 'BING SEARCH OFF' 200 62 180
$BtnRecall = New-Button 'RECALL / AI OFF' 388 62 196
$BtnExtrasAll = New-Button 'APPLY ALL WINDOWS 11 EXTRAS' 12 98 572
$ExtrasGroup.Controls.AddRange(@($BtnCopilot, $BtnWidgets, $BtnChat, $BtnStartAds, $BtnBing, $BtnRecall, $BtnExtrasAll))

# --- TOOLS ---
$ToolsGroup = New-Group 'TOOLS' 12 448 596 108
$BtnOneDrive = New-Button 'UNINSTALL ONEDRIVE' 12 26 180
$BtnUnpin = New-Button 'CLEAR START PINS' 200 26 180
$BtnInventory = New-Button 'EXPORT APP INVENTORY' 388 26 196
$BtnRestore = New-Button 'CREATE RESTORE POINT' 12 62 572
$ToolsGroup.Controls.AddRange(@($BtnOneDrive, $BtnUnpin, $BtnInventory, $BtnRestore))

# --- LOG ---
$LogLabel = New-Object System.Windows.Forms.Label
$LogLabel.Text = 'LOG'
$LogLabel.AutoSize = $true
$LogLabel.Location = New-Object System.Drawing.Point(14, 566)
$LogLabel.ForeColor = $accent

$script:LogBox = New-Object System.Windows.Forms.TextBox
$script:LogBox.Multiline = $true
$script:LogBox.ReadOnly = $true
$script:LogBox.ScrollBars = 'Vertical'
$script:LogBox.Location = New-Object System.Drawing.Point(12, 586)
$script:LogBox.Size = New-Object System.Drawing.Size(596, 160)
$script:LogBox.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#1b1b1b')
$script:LogBox.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#d0d0d0')
$script:LogBox.BorderStyle = 'FixedSingle'
$script:LogBox.Font = $smallFont
$script:LogBox.WordWrap = $false

$script:StatusLabel = New-Object System.Windows.Forms.Label
$script:StatusLabel.Location = New-Object System.Drawing.Point(12, 754)
$script:StatusLabel.Size = New-Object System.Drawing.Size(596, 20)
$script:StatusLabel.Font = $smallFont
$script:StatusLabel.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#9ad29a')

$Form.Controls.AddRange(@($Title, $SubTitle, $DebloatGroup, $PrivacyGroup, $ExtrasGroup, $ToolsGroup, $LogLabel, $script:LogBox, $script:StatusLabel))

# The form is DPI-aware, so fonts already render at the right physical size -
# the fixed pixel layout has to be scaled by hand to match, otherwise labels
# overflow their buttons on 125% / 150% displays.
function Scale-ControlTree {
    # Scales only the CHILDREN of the control passed in, so a container is never
    # scaled twice (once as a child, once as the root of the recursion).
    param([System.Windows.Forms.Control]$Parent, [double]$Factor)

    foreach ($c in $Parent.Controls) {
        $c.Location = New-Object System.Drawing.Point(
            [int][Math]::Round($c.Location.X * $Factor),
            [int][Math]::Round($c.Location.Y * $Factor))
        $c.Size = New-Object System.Drawing.Size(
            [int][Math]::Round($c.Size.Width * $Factor),
            [int][Math]::Round($c.Size.Height * $Factor))
        if ($c.HasChildren) { Scale-ControlTree -Parent $c -Factor $Factor }
    }
}

$Form.CreateControl()
$gfx = $Form.CreateGraphics()
$dpiScale = $gfx.DpiX / 96.0
$gfx.Dispose()
if ([Math]::Abs($dpiScale - 1.0) -gt 0.01) {
    $Form.ClientSize = New-Object System.Drawing.Size(
        [int][Math]::Round($Form.ClientSize.Width * $dpiScale),
        [int][Math]::Round($Form.ClientSize.Height * $dpiScale))
    Scale-ControlTree -Parent $Form -Factor $dpiScale
}

# --------------------------------------------------------------------------
# Button wiring
# --------------------------------------------------------------------------

$BtnBlacklist.Add_Click({
        Invoke-GuiAction -Label 'Remove bloatware' -RecreateAppxCache -Action {
            Write-Log '--- removing curated bloatware ---'
            New-DebloatRestorePoint
            Invoke-DebloatBlacklist
            Remove-LeftoverKeys
            Write-Log ("done - {0} package(s) removed" -f $script:Stats.Removed) 'OK'
        }
    })

$BtnAll.Add_Click({
        $answer = [System.Windows.Forms.MessageBox]::Show(
            "This removes every Appx package that is not on the protected or keep list.`n`nWindows 11 needs its shell packages intact - this build keeps them, but app data and settings for removed apps are lost.`n`nContinue?",
            'Remove all non-protected apps', 'YesNo', 'Warning')
        if ($answer -ne 'Yes') { return }
        Invoke-GuiAction -Label 'Remove all' -RecreateAppxCache -Action {
            $script:Aggressive = $true
            Write-Log '--- removing all non-protected apps ---'
            New-DebloatRestorePoint
            Invoke-DebloatAll
            Remove-LeftoverKeys
        }
    })

$BtnPreview.Add_Click({
        Invoke-GuiAction -Label 'Preview' -RecreateAppxCache -Action {
            $script:PreviewBackup = $DryRun
            $DryRun = $true
            Write-Log '--- preview: nothing will be changed ---'
            Invoke-DebloatBlacklist
            Write-Log '--- end of preview ---'
            $DryRun = $script:PreviewBackup
        }
    })

$BtnPrivacy.Add_Click({
        Invoke-GuiAction -Label 'Privacy' -Action {
            New-DebloatRestorePoint
            Invoke-Privacy
        }
    })

$BtnTelemetry.Add_Click({
        Invoke-GuiAction -Label 'Telemetry' -Action {
            Disable-DiagTrack
            Disable-WAPPush
            Disable-TelemetryTasks
        }
    })

$BtnRevert.Add_Click({
        $answer = [System.Windows.Forms.MessageBox]::Show('Re-enable telemetry, taskbar extras and re-register apps?', 'Revert', 'YesNo', 'Question')
        if ($answer -ne 'Yes') { return }
        Invoke-GuiAction -Label 'Revert' -RecreateAppxCache -Action { Invoke-Revert }
    })

$BtnCopilot.Add_Click({ Invoke-GuiAction -Label 'Copilot' -Action { Disable-Copilot } })
$BtnWidgets.Add_Click({ Invoke-GuiAction -Label 'Widgets' -Action { Disable-Widgets } })
$BtnChat.Add_Click({ Invoke-GuiAction -Label 'Chat' -Action { Disable-ChatTaskbar } })
$BtnStartAds.Add_Click({ Invoke-GuiAction -Label 'Start ads' -Action { Disable-StartAds } })
$BtnBing.Add_Click({ Invoke-GuiAction -Label 'Bing search' -Action { Disable-BingSearch } })
$BtnRecall.Add_Click({ Invoke-GuiAction -Label 'Recall' -Action { Disable-RecallAI } })
$BtnExtrasAll.Add_Click({ Invoke-GuiAction -Label 'Extras' -RecreateAppxCache -Action { Invoke-Win11Extras } })

$BtnOneDrive.Add_Click({
        $answer = [System.Windows.Forms.MessageBox]::Show('Back up OneDrive files to the Desktop and uninstall OneDrive?', 'Uninstall OneDrive', 'YesNo', 'Warning')
        if ($answer -ne 'Yes') { return }
        Invoke-GuiAction -Label 'OneDrive' -Action { Uninstall-OneDrive }
    })
$BtnUnpin.Add_Click({
        $answer = [System.Windows.Forms.MessageBox]::Show('Clear all Start menu pins? Explorer will restart twice.', 'Clear Start pins', 'YesNo', 'Warning')
        if ($answer -ne 'Yes') { return }
        Invoke-GuiAction -Label 'Unpin Start' -Action { Set-UnpinStart }
    })
$BtnInventory.Add_Click({ Invoke-GuiAction -Label 'Inventory' -Action { Show-Inventory } })
$BtnRestore.Add_Click({ Invoke-GuiAction -Label 'Restore point' -Action { New-DebloatRestorePoint } })

# --------------------------------------------------------------------------
# Go
# --------------------------------------------------------------------------

Update-StatusBar
if ($DryRun) {
    Write-Log 'GUI started in PREVIEW mode - nothing will be changed.' 'DRY'
}
else {
    Write-Log ("GUI ready on Windows {0} build {1}." -f $info.DisplayVer, $info.Build) 'OK'
}
Write-Log 'Tip: use PREVIEW first to see exactly what REMOVE ALL would take.'

if ($SelfTest) {
    $Form.CreateControl()
    $count = $Form.Controls.Count
    $buttons = 0
    foreach ($g in $Form.Controls) { if ($g -is [System.Windows.Forms.GroupBox]) { $buttons += $g.Controls.Count } }
    Write-Host "GUI SELFTEST OK - top-level controls: $count, grouped controls: $buttons, title: $($Form.Text)"
    $Form.Dispose()
    exit 0
}

[void]$Form.ShowDialog()
$Form.Dispose()
