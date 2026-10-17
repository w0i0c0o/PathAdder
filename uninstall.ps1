# -----------------------------------------------------------------------------
# uninstall.ps1 - Removes the right-click menu (user level HKCU, no elevation)
#
# Usage:
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "…\uninstall.ps1"
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "…\uninstall.ps1" -RestartExplorer
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "…\uninstall.ps1" -NoRestart
#
# Idempotent: missing menu entries are not an error, the user is told that there
# is nothing to uninstall.
#
# Cleanup scope (current location + ALL historical locations, so upgrading from
# an old version never leaves orphan menu items):
#   1. HKCU\Software\Classes\*\shell\PathAdder                  (current, whole subtree)
#   2. HKCU\Software\Classes\exefile\shell\PathAdder*           (historical flat verbs x4)
#   3. HKCU\Software\Classes\SystemFileAssociations\.exe\shell\PathAdder* (historical x4)
#      plus parent keys that became empty after the removal (empty keys only)
#
#   Never touched: any HKLM key, menu items registered by other programs,
#   and the default verbs of `*\shell` / `exefile\shell` (which decide the
#   double-click behaviour).
#
# Note: uninstalling only removes the right-click menu; backups and logs under
#       %LOCALAPPDATA%\PathAdder are kept so PATH can still be restored later.
#       Delete that directory manually for a complete cleanup.
#
# Runtime: Windows PowerShell 5.1 (no PowerShell 7-only syntax)
# -----------------------------------------------------------------------------

[CmdletBinding()]
param(
    [Parameter()]
    [switch]$RestartExplorer,

    [Parameter()]
    [switch]$NoRestart,

    [Parameter()]
    [string]$Language = ''
)

$ErrorActionPreference = 'Stop'

$script:MainScriptPath = $PSCommandPath
if ([string]::IsNullOrWhiteSpace($script:MainScriptPath)) {
    $script:MainScriptPath = $MyInvocation.MyCommand.Path
}
$script:ScriptRoot = Split-Path -Parent $script:MainScriptPath
$global:PathAdderRootDirectory = $script:ScriptRoot

# Load i18n defensively: lib\Common.ps1 may already dot-source lib\i18n.ps1.
if (-not (Get-Command -Name 'Get-PathAdderText' -ErrorAction SilentlyContinue)) {
    . (Join-Path $script:ScriptRoot 'lib\i18n.ps1')
}
if (Get-Command -Name 'Initialize-PathAdderI18n' -ErrorAction SilentlyContinue) {
    Initialize-PathAdderI18n -Language $Language | Out-Null
}

$script:LibraryPath = Join-Path $script:ScriptRoot 'lib\Common.ps1'
if (-not (Test-Path -LiteralPath $script:LibraryPath -PathType Leaf)) {
    Write-Error (T 'Setup.Error.MissingLibrary' @($script:LibraryPath))
    exit 1
}
. $script:LibraryPath

$script:ShellMenuPath = Join-Path $script:ScriptRoot 'lib\ShellMenu.ps1'
if (-not (Test-Path -LiteralPath $script:ShellMenuPath -PathType Leaf)) {
    Write-Error (T 'Setup.Error.MissingShellMenuLib' @($script:ShellMenuPath))
    exit 1
}
. $script:ShellMenuPath

try {
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
} catch {
    # Falls back to console output when WinForms is unavailable
}

if ($RestartExplorer -and $NoRestart) {
    Show-PathAdderMessageBox -Message (T 'Setup.Error.RestartConflict') -Title (T 'App.Name') -Icon 'Error'
    exit 1
}

# -----------------------------------------------------------------------------
# Run the uninstallation
# -----------------------------------------------------------------------------

$uninstallResult = $null

try {
    $uninstallResult = Uninstall-PathAdderShellMenu
} catch {
    Show-PathAdderMessageBox -Message (T 'Setup.Uninstall.Failed' @($_.Exception.Message)) -Title (T 'App.Name') -Icon 'Error'
    exit 1
}

# -----------------------------------------------------------------------------
# Notify refresh + ask whether to restart Windows Explorer
# -----------------------------------------------------------------------------

$refreshResult = $null
$restartResult = $null
$restartDeclined = $false

if ($uninstallResult.RemovedCount -gt 0) {
    $refreshResult = Update-PathAdderShellAssociationCache

    if ($NoRestart) {
        $restartDeclined = $true
    } elseif ($RestartExplorer) {
        $restartResult = Restart-PathAdderExplorer
    } else {
        $askMessage = (T 'Setup.Uninstall.RemovedNotice') + "`r`n`r`n" +
            (T 'Setup.Uninstall.RestartQuestion') + "`r`n`r`n" +
            (T 'Setup.Uninstall.RestartWarning')

        if (Show-PathAdderConfirmBox -Message $askMessage) {
            $restartResult = Restart-PathAdderExplorer
        } else {
            $restartDeclined = $true
        }
    }
} else {
    $restartDeclined = $true
}

# -----------------------------------------------------------------------------
# Result report
# -----------------------------------------------------------------------------

$message = ''
$script:Separator = '=================================================='

if ($uninstallResult.RemovedCount -gt 0) {
    $message = (T 'Setup.Uninstall.RemovedNotice') + "`r`n" +
        $script:Separator + "`r`n" +
        (T 'Setup.Uninstall.NextStepTitle') + "`r`n" +
        $script:Separator + "`r`n"
    if ($null -ne $restartResult) {
        if ($restartResult.Success) {
            $message = $message + (T 'Setup.Uninstall.RestartSucceeded') + "`r`n`r`n"
        } else {
            $message = $message + (T 'Setup.Uninstall.RestartFailed' @($restartResult.Message)) + "`r`n`r`n"
        }
    } elseif ($restartDeclined) {
        $message = $message + (T 'Setup.Uninstall.NotRestarted') + "`r`n" +
            (T 'Setup.Uninstall.RestartCommand') + "`r`n" +
            (T 'Setup.Uninstall.RestartAlt') + "`r`n`r`n"
    }

    $message = $message +
        (T 'Setup.Uninstall.CleanedSummary' @($uninstallResult.LocationsScanned.Count, $uninstallResult.RemovedCount)) + "`r`n"
    foreach ($location in $uninstallResult.LocationsScanned) {
        $message = $message + (T 'Setup.Uninstall.LocationItem' @($location)) + "`r`n"
    }
    $message = $message + "`r`n"
} else {
    $message = (T 'Setup.Uninstall.NothingFound') + "`r`n`r`n"
}

if ($uninstallResult.Failed.Count -gt 0) {
    $message = $message + (T 'Setup.Uninstall.DeleteFailed' @(($uninstallResult.Failed -join ', '))) + "`r`n`r`n"
}

if ($uninstallResult.PrunedEmptyKeys.Count -gt 0) {
    $message = $message + (T 'Setup.Uninstall.PrunedEmptyKeys') + "`r`n" +
        (($uninstallResult.PrunedEmptyKeys | ForEach-Object { (T 'Setup.Uninstall.PrunedItem' @($_)) }) -join "`r`n") + "`r`n`r`n"
}

if ($null -ne $refreshResult) {
    $message = $message + (T 'Setup.Label.RefreshStatus' @($refreshResult.Message)) + "`r`n`r`n"
}

$message = $message +
    (T 'Setup.Uninstall.KeptNote') + "`r`n" +
    (T 'Setup.Uninstall.BackupKept') + "`r`n" + (Get-PathAdderAppDataRoot) + "`r`n`r`n" +
    (T 'Setup.Uninstall.ManualCleanup')

Show-PathAdderMessageBox -Message $message -Title (T 'App.Name') -Icon 'Information'
exit 0
