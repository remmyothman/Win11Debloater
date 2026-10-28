<#
.SYNOPSIS
    Build-Standalone.ps1 - assembles the single-file build of Win11Debloater.

.DESCRIPTION
    The repo keeps its logic in lib\Win11Debloat.Core.ps1 so the console script
    and the GUI cannot drift apart. That layout cannot survive `irm <url> | iex`,
    because a piped script has no $PSScriptRoot to resolve the library from.

    This script stitches the library into a copy of the console script and writes
    dist\Win11Debloater.standalone.ps1, which is self-contained and safe to pipe
    into iex. It also bakes the raw URL of the published build into the output so
    the script can re-fetch itself when it needs to re-launch elevated.

    -Verify regenerates in memory and fails if the committed dist file is stale.

.PARAMETER RepoRoot
    Repository root. Defaults to the parent of this script's folder.

.PARAMETER StandaloneUrl
    URL baked into the build for the elevation relaunch. Defaults to the raw URL
    of this repo's dist file on master. Override if you publish elsewhere.

.EXAMPLE
    .\tools\Build-Standalone.ps1

.EXAMPLE
    .\tools\Build-Standalone.ps1 -Verify
#>

[CmdletBinding()]
param(
    [string]$RepoRoot,
    [string]$StandaloneUrl = 'https://raw.githubusercontent.com/remmyothman/Win11Debloater/master/dist/Win11Debloater.standalone.ps1',
    [switch]$Verify
)

$ErrorActionPreference = 'Stop'

# $PSScriptRoot is not reliable inside a param() default on PowerShell 5.1,
# so resolve the repo root here instead.
if ([string]::IsNullOrEmpty($RepoRoot)) {
    $here = Split-Path -Parent $MyInvocation.MyCommand.Path
    $RepoRoot = Split-Path -Parent $here
}

$consolePath = Join-Path $RepoRoot 'Win11Debloater.ps1'
$corePath = Join-Path $RepoRoot 'lib\Win11Debloat.Core.ps1'
$distDir = Join-Path $RepoRoot 'dist'
$outPath = Join-Path $distDir 'Win11Debloater.standalone.ps1'

foreach ($f in @($consolePath, $corePath)) {
    if (!(Test-Path $f)) { throw "Missing source file: $f" }
}

$console = Get-Content -Path $consolePath -Raw
$core = Get-Content -Path $corePath -Raw

$beginMarker = '# >>> LIBRARY LOADER'
$endMarker = '# <<< LIBRARY LOADER'
$startIdx = $console.IndexOf($beginMarker)
$endIdx = $console.IndexOf($endMarker)

if ($startIdx -lt 0 -or $endIdx -lt 0) {
    throw 'Loader markers not found in Win11Debloater.ps1 - the build script needs them to know where to inject the library.'
}
if ($endIdx -lt $startIdx) { throw 'Loader markers are in the wrong order.' }

$endOfMarker = $console.IndexOf("`n", $endIdx)
if ($endOfMarker -lt 0) { $endOfMarker = $console.Length }

$pre = $console.Substring(0, $startIdx)
$post = $console.Substring($endOfMarker)

# Strip the library's own comment-based help, it is meaningless once inlined,
# and keep a marker so the generated file is obvious.
$coreBody = $core -replace '(?s)^\s*<#.*?#>\s*', ''

$banner = @"
# =============================================================================
#  Win11Debloater - single-file build. GENERATED FILE, DO NOT EDIT.
#  Source: Win11Debloater.ps1 + lib\Win11Debloat.Core.ps1
#  Rebuild with: tools\Build-Standalone.ps1
#  Safe to run as: irm <raw url of this file> | iex
# =============================================================================

"@

$injected = @"
# >>> LIBRARY LOADER (inlined by tools\Build-Standalone.ps1)
`$script:StandaloneUrl = '$StandaloneUrl'
# Custom blocklists are read from custom-lists.ps1 next to a script on disk;
# a piped build has no folder, so that feature is file-based only.
# <<< LIBRARY LOADER

"@ + $coreBody.TrimEnd() + "`r`n"

$standalone = $banner + $pre + $injected + $post

# Normalise to CRLF so the file behaves the same whichever tool reads it.
$standalone = ($standalone -replace "`r`n", "`n") -replace "`n", "`r`n"

# Sanity check before writing: it has to parse.
$errors = $null
$tokens = $null
[System.Management.Automation.Language.Parser]::ParseInput($standalone, [ref]$tokens, [ref]$errors) | Out-Null
if ($errors.Count -gt 0) {
    $errors | Select-Object -First 5 | ForEach-Object {
        Write-Host ("  line {0}: {1}" -f $_.Extent.StartLineNumber, $_.Message) -ForegroundColor Red
    }
    throw 'Generated standalone build does not parse - aborting, dist\ was not written.'
}

function Get-TextHash([string]$Text) {
    # Hash the text itself, not the file, so a BOM or trailing newline written by
    # Out-File cannot make -Verify report a false stale.
    $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha.ComputeHash($bytes)) -replace '-', '')
    }
    finally { $sha.Dispose() }
}

$hash = Get-TextHash $standalone

if ($Verify) {
    if (!(Test-Path $outPath)) { throw "dist file missing: $outPath" }
    $existing = Get-Content -Path $outPath -Raw
    $existingHash = Get-TextHash $existing
    if ($existingHash -ne $hash) {
        Write-Host 'STALE: dist\Win11Debloater.standalone.ps1 does not match the sources.' -ForegroundColor Red
        Write-Host 'Run tools\Build-Standalone.ps1 to regenerate it.' -ForegroundColor Yellow
        exit 1
    }
    Write-Host 'OK: standalone build is up to date with the sources.' -ForegroundColor Green
    exit 0
}

if (!(Test-Path $distDir)) { New-Item -Path $distDir -ItemType Directory -Force | Out-Null }
# UTF8 without BOM: keeps the file byte-identical to the string we hashed, and
# plain ASCII means no encoding surprises on PowerShell 5.1.
[IO.File]::WriteAllText($outPath, $standalone, (New-Object System.Text.UTF8Encoding($false)))

$lines = ($standalone -split "`n").Count
$kb = [Math]::Round((Get-Item $outPath).Length / 1KB, 1)
Write-Host "wrote $outPath"
Write-Host ("  {0} lines, {1} KB, sha256 {2}" -f $lines, $kb, $hash.Substring(0, 16))
Write-Host "  baked URL: $StandaloneUrl"
