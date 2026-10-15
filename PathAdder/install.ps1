# -----------------------------------------------------------------------------
# install.ps1 - Registers the right-click menu (user level HKCU, no elevation)
#
# Usage:
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "…\install.ps1"
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "…\install.ps1" -RestartExplorer
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "…\install.ps1" -NoRestart
#
# Idempotent: running it again never errors, it just overwrites existing values.
#
# Registration location (single place, covers every file type):
#   HKCU\Software\Classes\*\shell\PathAdder
#         (Default)/MUIVerb/Icon/SubCommands/NoWorkingDirectory
#         └─ shell\PathAdder.AddUser   -> Add to PATH (current user)
#            shell\PathAdder.AddSystem -> Add to PATH (system-wide, administrator)
#            shell\PathAdder.Remove    -> Remove this directory from PATH
#            shell\PathAdder.Manager   -> Open PATH Manager
#
#   `*` is the officially supported "all file objects" association key and covers
#   any extension (including .exe). Registering in one place is the cleanest
#   option: earlier versions also registered exefile\shell and
#   SystemFileAssociations\.exe\shell, which was redundant and produced two
#   identical menu entries. That approach is retired (uninstall still cleans up
#   leftovers from it).
#
#   WARNING: the PathAdder parent key must NEVER get a command subkey, otherwise
#   SubCommands is ignored and the cascade degrades into a dead menu item.
#   This script actively removes such a leftover.
#
# About -RestartExplorer / -NoRestart:
#   Default: a dialog ASKS whether to restart Windows Explorer right away
#   (the default button is "No").
#   Reason: on Windows 11 the SHChangeNotify notification does not always take
#   effect, so the menu usually appears only after explorer restarts; but a
#   restart closes every open folder window, so it must NEVER happen unasked.
#     -RestartExplorer  restart without asking (for scripted bulk deployment)
#     -NoRestart        neither ask nor restart (scripted and non-intrusive)
#
# About -MakeDefault (retired, kept only for backwards compatibility):
#   This version never writes a default verb ANYWHERE. The (Default) value of
#   `*\shell` / `exefile\shell` decides what happens on double-click; pointing it
#   at our menu item would stop files from opening and pop a PATH dialog instead
#   -- catastrophic. Passing the switch only prints a note and does nothing.
#
# Runtime: Windows PowerShell 5.1 (no PowerShell 7-only syntax)
# -----------------------------------------------------------------------------

[CmdletBinding()]
param(
    [Parameter()]
    [switch]$MakeDefault,

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

$script:Separator = '=================================================='

# -----------------------------------------------------------------------------
# Mutually exclusive parameters
# -----------------------------------------------------------------------------

if ($RestartExplorer -and $NoRestart) {
    Show-PathAdderMessageBox -Message ((T 'Setup.Error.RestartConflict') + "`r`n`r`n" +
        (T 'Setup.Error.RestartConflictHint')) -Title (T 'App.Name') -Icon 'Error'
    exit 1
}

# -----------------------------------------------------------------------------
# Preconditions
# -----------------------------------------------------------------------------

$enginePath = Join-Path $script:ScriptRoot 'PathAdder.ps1'
$managerPath = Join-Path $script:ScriptRoot 'PathManager.ps1'

$missing = @()
if (-not (Test-Path -LiteralPath $enginePath -PathType Leaf)) { $missing += 'PathAdder.ps1' }
if (-not (Test-Path -LiteralPath $managerPath -PathType Leaf)) { $missing += 'PathManager.ps1' }
if ($missing.Count -gt 0) {
    $abortMessage = (T 'Setup.Install.MissingFiles' @(($missing -join ', '))) + "`r`n`r`n" +
        (T 'Setup.Install.MissingFilesHint')
    Show-PathAdderMessageBox -Message $abortMessage -Title (T 'App.Name') -Icon 'Error'
    exit 1
}

$powershellPath = Get-SystemPowerShellPath

# -----------------------------------------------------------------------------
# Write the registry
# -----------------------------------------------------------------------------

$installResult = $null

try {
    $installResult = Install-PathAdderShellMenu `
        -EnginePath $enginePath `
        -PowerShellPath $powershellPath `
        -ParentLabel (Get-PathAdderShellMenuParentLabel)
} catch {
    Show-PathAdderMessageBox -Message ((T 'Setup.Install.Failed' @($_.Exception.Message)) + "`r`n`r`n" +
        (T 'Setup.Install.MenuUnchanged')) -Title (T 'App.Name') -Icon 'Error'
    exit 1
}

if (-not $installResult.Success) {
    $failureMessage = (T 'Setup.Install.RegistryIncomplete') + "`r`n`r`n" +
        (T 'Setup.Install.PartialHint')
    Show-PathAdderMessageBox -Message $failureMessage -Title (T 'App.Name') -Icon 'Error'
    exit 1
}

# -----------------------------------------------------------------------------
# Notify Windows Explorer to refresh (a failure here is not fatal)
# -----------------------------------------------------------------------------

$refreshResult = Update-PathAdderShellAssociationCache

# -----------------------------------------------------------------------------
# Restart Windows Explorer (ask first; never restart unasked)
# -----------------------------------------------------------------------------

$restartResult = $null
$restartDeclined = $false

if ($NoRestart) {
    $restartDeclined = $true
} elseif ($RestartExplorer) {
    $restartResult = Restart-PathAdderExplorer
} else {
    $askMessage = (T 'Setup.Restart.Written') + "`r`n`r`n" +
        (T 'Setup.Restart.Question') + "`r`n`r`n" +
        (T 'Setup.Restart.Warning') + "`r`n" +
        (T 'Setup.Restart.SuggestNo')

    if (Show-PathAdderConfirmBox -Message $askMessage) {
        $restartResult = Restart-PathAdderExplorer
    } else {
        $restartDeclined = $true
    }
}

# -----------------------------------------------------------------------------
# Completion summary (the mandatory restart comes first in the report)
# -----------------------------------------------------------------------------

$restartStatus = ''
if ($null -ne $restartResult) {
    if ($restartResult.Success) {
        $restartStatus = (T 'Setup.Restart.Succeeded')
    } else {
        $restartStatus = (T 'Setup.Restart.Failed' @($restartResult.Message))
    }
} elseif ($restartDeclined) {
    $restartStatus = (T 'Setup.Restart.Declined')
}

$message = (T 'Setup.Install.Completed') + "`r`n" +
    $script:Separator + "`r`n" +
    (T 'Setup.Install.NextStepTitle') + "`r`n" +
    $script:Separator + "`r`n" +
    (T 'Setup.Install.CurrentStatus' @($restartStatus)) + "`r`n`r`n" +
    (T 'Setup.Install.ChooseOne') + "`r`n" +
    (T 'Setup.Install.MethodManual') + "`r`n" +
    (T 'Setup.Install.MethodCommand') + "`r`n" +
    (T 'Setup.Install.MethodLogoff') + "`r`n" +
    (T 'Setup.Install.ShnNote') + "`r`n" +
    (T 'Setup.Install.ShnNote2') + "`r`n`r`n" +
    $script:Separator + "`r`n" +
    (T 'Setup.Install.WhereTitle') + "`r`n" +
    $script:Separator + "`r`n" +
    (T 'Setup.Install.WhereBody') + "`r`n" +
    (T 'Setup.Install.SubItem.AddUser') + "`r`n" +
    (T 'Setup.Install.SubItem.AddSystem') + "`r`n" +
    (T 'Setup.Install.SubItem.Remove') + "`r`n" +
    (T 'Setup.Install.SubItem.Manager') + "`r`n`r`n" +
    (T 'Setup.Install.Win11Menu') + "`r`n" +
    (T 'Setup.Install.Win11Way1') + "`r`n" +
    (T 'Setup.Install.Win11Way2') + "`r`n" +
    (T 'Setup.Install.Win11Way3') + "`r`n`r`n" +
    $script:Separator + "`r`n" +
    (T 'Setup.Install.InfoTitle') + "`r`n" +
    $script:Separator + "`r`n" +
    (T 'Setup.Install.RegLocation') + "`r`n" +
    (T 'Setup.Label.HkcuKey' @($installResult.ParentSubKey)) + "`r`n" +
    (T 'Setup.Install.SubCommands' @($installResult.SubCommands)) + "`r`n" +
    (T 'Setup.Label.RefreshStatus' @($refreshResult.Message)) + "`r`n" +
    (T 'Setup.Label.BackupDirectory' @((Get-PathAdderBackupDirectory)))

if ($MakeDefault) {
    $message = $message + "`r`n`r`n" + (T 'Setup.Install.MakeDefaultDeprecated')
}

Show-PathAdderMessageBox -Message $message -Title (T 'App.Name') -Icon 'Information'
exit 0
