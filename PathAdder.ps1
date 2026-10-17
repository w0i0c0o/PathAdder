# -----------------------------------------------------------------------------
# PathAdder.ps1 - Entry point invoked from the right-click menu (core engine)
#
# Usage (called from the right-click menu or the command line):
#   powershell.exe -ExecutionPolicy Bypass -NoProfile -WindowStyle Hidden -File
#       "…\PathAdder.ps1" -Action Add    -Scope User   -Target "%V"
#       "…\PathAdder.ps1" -Action Add    -Scope System -Target "%V"
#       "…\PathAdder.ps1" -Action Remove -Scope All    -Target "%V"
#       "…\PathAdder.ps1" -Action OpenManager
#       "…\PathAdder.ps1" -Action Restore -Scope System -BackupFile "system-20261002-070000.txt"
#
# -Language receives the UI language selected by the parent process
# (COM shell extension / GUI) so every message box follows that choice.
#
# Runtime: Windows PowerShell 5.1 (no PowerShell 7-only syntax)
# -----------------------------------------------------------------------------

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('Add', 'Remove', 'Restore', 'OpenManager')]
    [string]$Action = 'Add',

    [Parameter(Position = 1)]
    [ValidateSet('User', 'System', 'All')]
    [string]$Scope = 'User',

    [Parameter(Position = 2)]
    [string]$Target = '',

    [Parameter()]
    [string]$BackupFile = '',

    [Parameter()]
    [switch]$Elevated,

    [Parameter()]
    [string]$Language = ''
)

$ErrorActionPreference = 'Stop'

# -----------------------------------------------------------------------------
# Initialization
# -----------------------------------------------------------------------------

$script:MainScriptPath = $PSCommandPath
if ([string]::IsNullOrWhiteSpace($script:MainScriptPath)) {
    $script:MainScriptPath = $MyInvocation.MyCommand.Path
}
$script:ScriptRoot = Split-Path -Parent $script:MainScriptPath
$global:PathAdderRootDirectory = $script:ScriptRoot

# Load i18n defensively: lib\Common.ps1 may already dot-source lib\i18n.ps1,
# and lib\i18n.ps1 may be loaded by another entry point before us.
if (-not (Get-Command -Name 'Get-PathAdderText' -ErrorAction SilentlyContinue)) {
    . (Join-Path $script:ScriptRoot 'lib\i18n.ps1')
}
if (Get-Command -Name 'Initialize-PathAdderI18n' -ErrorAction SilentlyContinue) {
    Initialize-PathAdderI18n -Language $Language | Out-Null
}

$script:LibraryPath = Join-Path $script:ScriptRoot 'lib\Common.ps1'
if (-not (Test-Path -LiteralPath $script:LibraryPath -PathType Leaf)) {
    Write-Error (T 'Cli.Error.MissingLibrary' @($script:LibraryPath))
    exit 1
}
. $script:LibraryPath

# -----------------------------------------------------------------------------
# Helper functions
# -----------------------------------------------------------------------------

<#
.SYNOPSIS
    Returns the localized label of a PATH scope.
#>
function Get-ScopeLabelText {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScopeName
    )

    if ($ScopeName -eq 'System') {
        return (T 'App.Scope.System')
    }
    return (T 'App.Scope.User')
}

<#
.SYNOPSIS
    Builds the user-facing sentence that describes one operation result.
#>
function Get-OperationMessage {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ActionName,

        [Parameter(Mandatory = $true)]
        [string]$ScopeName,

        [Parameter(Mandatory = $false)]
        $Result
    )

    $scopeLabel = Get-ScopeLabelText -ScopeName $ScopeName

    if ($null -eq $Result) {
        return (T 'Cli.Result.NotExecuted' @($scopeLabel))
    }

    $line = ''
    $status = [string]$Result.Status

    if ($status -eq 'Added') {
        $line = (T 'Cli.Result.Added' @($scopeLabel))
    } elseif ($status -eq 'AlreadyExists') {
        $line = (T 'Cli.Result.AlreadyExists' @($scopeLabel))
    } elseif ($status -eq 'Removed') {
        $line = (T 'Cli.Result.Removed' @($scopeLabel))
    } elseif ($status -eq 'NotFound') {
        $line = (T 'Cli.Result.NotFound' @($scopeLabel))
    } elseif ($status -eq 'Failed') {
        $line = (T 'Cli.Result.Failed' @($scopeLabel, $Result.Message))
    } else {
        $line = (T 'Cli.Result.Unknown' @($scopeLabel, $Result.Message))
    }

    if (-not [string]::IsNullOrEmpty($Result.BackupFile)) {
        $line = $line + "`r`n" + (T 'Cli.Label.BackupFile' @($Result.BackupFile))
    }

    return $line
}

<#
.SYNOPSIS
    Runs Add / Remove against a single scope.
#>
function Invoke-SingleScopeOperation {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Add', 'Remove')]
        [string]$ActionName,

        [Parameter(Mandatory = $true)]
        [ValidateSet('User', 'System')]
        [string]$ScopeName,

        [Parameter(Mandatory = $true)]
        [string]$Directory
    )

    if ($ActionName -eq 'Add') {
        return (Add-DirectoryToPath -Scope $ScopeName -Directory $Directory)
    }

    return (Remove-DirectoryFromPath -Scope $ScopeName -Directory $Directory)
}

<#
.SYNOPSIS
    Common exit point: shows one message box and returns an exit code.
#>
function Exit-WithMessage {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [string]$Icon = 'Information',

        [Parameter(Mandatory = $false)]
        [int]$ExitCode = 0
    )

    Show-PathAdderMessageBox -Message $Message -Title (T 'App.Name') -Icon $Icon
    exit $ExitCode
}

# -----------------------------------------------------------------------------
# Branch 1: open the PATH manager
# -----------------------------------------------------------------------------

if ($Action -eq 'OpenManager') {
    $managerPath = Join-Path $script:ScriptRoot 'PathManager.ps1'
    if (-not (Test-Path -LiteralPath $managerPath -PathType Leaf)) {
        Exit-WithMessage -Message ((T 'Cli.Manager.NotFound') + "`r`n" + $managerPath) -Icon 'Error' -ExitCode 1
    }

    $started = Start-PathAdderScript -ScriptPath $managerPath
    if (-not $started) {
        Exit-WithMessage -Message ((T 'Cli.Manager.StartFailed') + "`r`n" + $managerPath) -Icon 'Error' -ExitCode 1
    }

    exit 0
}

# -----------------------------------------------------------------------------
# Branch 2: restore from backup
# -----------------------------------------------------------------------------

if ($Action -eq 'Restore') {
    if ([string]::IsNullOrWhiteSpace($BackupFile)) {
        Exit-WithMessage -Message (T 'Cli.Restore.MissingBackupFile') -Icon 'Error' -ExitCode 1
    }

    $restoreScope = $Scope
    if ($restoreScope -eq 'All') {
        $restoreScope = 'User'
    }

    if ($restoreScope -eq 'System' -and -not (Test-PathAdderAdministrator)) {
        if ($Elevated) {
            Exit-WithMessage -Message ((T 'Cli.Restore.StillNotAdmin') + "`r`n`r`n" +
                (T 'Cli.Label.BackupFile' @($BackupFile)) + "`r`n" +
                (T 'Cli.Msg.SystemPathNotModified')) -Icon 'Warning' -ExitCode 1
        }

        $ok = Invoke-SelfElevation -ScriptPath $script:MainScriptPath -ArgumentList @(
            '-Action', 'Restore',
            '-Scope', 'System',
            '-BackupFile', $BackupFile,
            '-Elevated'
        )

        if ($ok) {
            Exit-WithMessage -Message ((T 'Cli.Restore.ElevationRequested') + "`r`n`r`n" +
                (T 'Cli.Label.BackupFile' @($BackupFile)) + "`r`n`r`n" +
                (T 'Cli.Restore.UacHint')) -Icon 'Information' -ExitCode 0
        }

        Exit-WithMessage -Message ((T 'Cli.Restore.ElevationFailed') + "`r`n`r`n" +
            (T 'Cli.Label.BackupFile' @($BackupFile)) + "`r`n" +
            (T 'Cli.Msg.SystemPathNotModified')) -Icon 'Warning' -ExitCode 1
    }

    try {
        $restoreResult = Restore-PathBackup -BackupFileName $BackupFile
    } catch {
        Exit-WithMessage -Message ((T 'Cli.Restore.Failed') + "`r`n`r`n" +
            (T 'Cli.Label.BackupFile' @($BackupFile)) + "`r`n" +
            (T 'Cli.Label.ErrorDetail' @($_.Exception.Message))) -Icon 'Error' -ExitCode 1
    }

    $scopeLabel = Get-ScopeLabelText -ScopeName $restoreResult.Scope
    Exit-WithMessage -Message ((T 'Cli.Restore.Succeeded' @($scopeLabel)) + "`r`n`r`n" +
        (T 'Cli.Label.RestoredFrom' @($restoreResult.RestoredFrom)) + "`r`n" +
        (T 'Cli.Label.RestoredBackup' @($restoreResult.BackupFile)) + "`r`n`r`n" +
        (T 'Cli.Msg.NewWindowsHint')) -Icon 'Information' -ExitCode 0
}

# -----------------------------------------------------------------------------
# Branch 3: Add / Remove
# -----------------------------------------------------------------------------

# 3.1 Resolve the target directory.
#     Remove tolerates a missing target (-AllowMissing): stale PATH entries often
#     point to directories deleted long ago, and requiring them to exist would
#     make those entries impossible to clean up.
#     Add stays strict: the target must really exist as a file or directory.
$directory = ''
if ($Action -eq 'Remove') {
    $directory = Resolve-TargetDirectory -Target $Target -AllowMissing
} else {
    $directory = Resolve-TargetDirectory -Target $Target
}

if ([string]::IsNullOrWhiteSpace($directory)) {
    $reason = (T 'Cli.Target.AddReason')
    if ($Action -eq 'Remove') {
        $reason = (T 'Cli.Target.RemoveReason')
    }
    Exit-WithMessage -Message ((T 'Cli.Target.ResolveFailed') + "`r`n" + $Target + "`r`n`r`n" +
        $reason + "`r`n" + (T 'Cli.Msg.PathNotModified')) -Icon 'Error' -ExitCode 1
}

# 3.2 System-only: administrator rights are required, so elevate first. The
#     elevated child process does all the work and shows the result dialog.
if ($Scope -eq 'System' -and -not (Test-PathAdderAdministrator)) {
    if ($Elevated) {
        Exit-WithMessage -Message ((T 'Cli.System.StillNotAdmin') + "`r`n`r`n" +
            (T 'Cli.Label.Directory' @($directory)) + "`r`n`r`n" +
            (T 'Cli.System.AdminHint') + "`r`n" +
            (T 'Cli.Msg.SystemPathNotModified')) -Icon 'Warning' -ExitCode 1
    }

    $elevated = Invoke-SelfElevation -ScriptPath $script:MainScriptPath -ArgumentList @(
        '-Action', $Action,
        '-Scope', 'System',
        '-Target', $directory,
        '-Elevated'
    )

    if ($elevated) {
        # The elevated process shows its own message box; exit silently here.
        exit 0
    }

    $verb = (T 'Cli.Verb.Add')
    if ($Action -eq 'Remove') {
        $verb = (T 'Cli.Verb.Remove')
    }

    Exit-WithMessage -Message ((T 'Cli.System.ElevationFailed' @($verb)) + "`r`n`r`n" +
        (T 'Cli.Label.Directory' @($directory)) + "`r`n`r`n" +
        (T 'Cli.Msg.SystemPathNotModified') + ' ' + (T 'Cli.System.NoAdminHint')) -Icon 'Warning' -ExitCode 1
}

# 3.3 User scope / system scope (privileges already available)
if ($Scope -ne 'All') {
    try {
        $result = Invoke-SingleScopeOperation -ActionName $Action -ScopeName $Scope -Directory $directory
    } catch {
        Exit-WithMessage -Message ((T 'Cli.Operation.Failed') + "`r`n`r`n" +
            (T 'Cli.Label.Directory' @($directory)) + "`r`n" +
            (T 'Cli.Label.ErrorDetail' @($_.Exception.Message))) -Icon 'Error' -ExitCode 1
    }

    $head = ''
    if ($result.Status -eq 'Added' -or $result.Status -eq 'Removed') {
        $head = (T 'Cli.Result.Success')
    } elseif ($result.Status -eq 'AlreadyExists' -or $result.Status -eq 'NotFound') {
        $head = (T 'Cli.Result.NoChange')
    } else {
        $head = (T 'Cli.Result.Incomplete')
    }

    $icon = 'Information'
    $exitCode = 0
    if ($result.Status -eq 'Failed') {
        $icon = 'Error'
        $exitCode = 1
    }

    $tail = ''
    if ($result.Status -eq 'Added' -or $result.Status -eq 'Removed') {
        $tail = "`r`n`r`n" + (T 'Cli.Msg.EffectHint')
    }

    Exit-WithMessage -Message ($head + "`r`n`r`n" +
        (T 'Cli.Label.Directory' @($directory)) + "`r`n`r`n" +
        (Get-OperationMessage -ActionName $Action -ScopeName $Scope -Result $result) +
        $tail) -Icon $icon -ExitCode $exitCode
}

# 3.4 Both (All): run the user-scope part without elevation first, then handle
#     the system scope.
$userResult = $null
try {
    $userResult = Invoke-SingleScopeOperation -ActionName $Action -ScopeName 'User' -Directory $directory
} catch {
    $userResult = New-Object PSObject -Property @{
        Status     = 'Failed'
        Directory  = $directory
        BackupFile = ''
        Message    = $_.Exception.Message
    }
}

$systemNote = ''
$systemResult = $null

if (Test-PathAdderAdministrator) {
    try {
        $systemResult = Invoke-SingleScopeOperation -ActionName $Action -ScopeName 'System' -Directory $directory
    } catch {
        $systemResult = New-Object PSObject -Property @{
            Status     = 'Failed'
            Directory  = $directory
            BackupFile = ''
            Message    = $_.Exception.Message
        }
    }
} elseif ($Elevated) {
    $systemNote = "`r`n" + (T 'Cli.All.SystemNoAdminNote')
} else {
    $ok = Invoke-SelfElevation -ScriptPath $script:MainScriptPath -ArgumentList @(
        '-Action', $Action,
        '-Scope', 'System',
        '-Target', $directory,
        '-Elevated'
    )

    if ($ok) {
        $systemNote = "`r`n" + (T 'Cli.All.SystemElevationRequestedNote')
    } else {
        $systemNote = "`r`n" + (T 'Cli.All.SystemElevationFailedNote')
    }
}

$combinedMessage = (T 'Cli.Label.Directory' @($directory)) + "`r`n`r`n" +
    (Get-OperationMessage -ActionName $Action -ScopeName 'User' -Result $userResult) + "`r`n"

if ($null -ne $systemResult) {
    $combinedMessage = $combinedMessage + "`r`n" + (Get-OperationMessage -ActionName $Action -ScopeName 'System' -Result $systemResult)
} else {
    $combinedMessage = $combinedMessage + $systemNote
}

$allOk = $true
if ($userResult.Status -eq 'Failed') {
    $allOk = $false
}
if ($null -ne $systemResult -and $systemResult.Status -eq 'Failed') {
    $allOk = $false
}

$icon = 'Information'
$exitCode = 0
if (-not $allOk) {
    $icon = 'Error'
    $exitCode = 1
}

$combinedMessage = $combinedMessage + "`r`n`r`n" + (T 'Cli.All.EffectHint')

Exit-WithMessage -Message $combinedMessage -Icon $icon -ExitCode $exitCode
