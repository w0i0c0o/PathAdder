# -----------------------------------------------------------------------------
# PathAdder - shared function library (lib\Common.ps1)
#
# Target runtime: Windows PowerShell 5.1 (3.0+ compatible).
# PowerShell 7 only syntax (?? / && / || / ternary operator / $PSStyle) is
# forbidden.
#
# Provides:
#   1. Application data directory / backup directory / log file paths
#   2. Registry PATH read and write (keeps the original REG_EXPAND_SZ / REG_SZ type)
#   3. PATH entry normalization and robust duplicate comparison
#   4. Automatic backup before every change + change log
#   5. Backup restore
#   6. Administrator detection and UAC self-elevation
#   7. WM_SETTINGCHANGE environment change broadcast
#   8. WinForms message box
#
# Design principles: back up before modifying; on failure restore or report
# clearly; never silently damage an existing PATH.
#
# Localization: every other script dot-sources this file, so it is also the
# i18n entry point of the whole project (see section 0a below). User visible
# text goes through Get-PathAdderText (short alias T). Programmatic contract
# values - the Status field (Added / Removed / AlreadyExists / NotFound /
# Failed) and the Scope field (User / System) - stay in English.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# 0a. Localization bootstrap
# -----------------------------------------------------------------------------

# lib\i18n.ps1 is loaded here (and only here) so that T() is available to every
# script that dot-sources this library. The guard keeps the load idempotent:
# entry points that already loaded lib\i18n.ps1 are not loaded twice.
$script:PathAdderLibDirectory = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($script:PathAdderLibDirectory)) {
    $script:PathAdderLibDirectory = Split-Path -Parent $MyInvocation.MyCommand.Definition
}
if (-not (Get-Command -Name 'Get-PathAdderText' -ErrorAction SilentlyContinue)) {
    . (Join-Path $script:PathAdderLibDirectory 'i18n.ps1')
}

# -----------------------------------------------------------------------------
# 0. Native methods (P/Invoke)
# -----------------------------------------------------------------------------

<#
.SYNOPSIS
    Initializes the P/Invoke native methods (SendMessageTimeout / GetLongPathName).
.DESCRIPTION
    A compilation failure (for example no C# compiler available) does not throw.
    It only leaves $script:PathAdderNativeReady set to $false, and callers then
    degrade gracefully to "no broadcast" / "no long path conversion" so that the
    feature itself keeps working.
#>
function Initialize-PathAdderNativeMethods {
    if ($script:PathAdderNativeReady) {
        return
    }
    $script:PathAdderNativeReady = $false

    if ('PathAdder.NativeMethods' -as [type]) {
        $script:PathAdderNativeReady = $true
        return
    }

    $source = @'
using System;
using System.Runtime.InteropServices;
using System.Text;

namespace PathAdder
{
    public static class NativeMethods
    {
        [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
        public static extern IntPtr SendMessageTimeout(
            IntPtr hWnd,
            uint Msg,
            UIntPtr wParam,
            string lParam,
            uint fuFlags,
            uint uTimeout,
            out UIntPtr lpdwResult);

        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Auto)]
        public static extern int GetLongPathName(
            string shortPath,
            StringBuilder longPath,
            int bufferSize);
    }
}
'@

    try {
        Add-Type -TypeDefinition $source -ErrorAction Stop
        $script:PathAdderNativeReady = $true
    } catch {
        $script:PathAdderNativeReady = $false
    }
}

if (-not $script:PathAdderNativeReady) {
    $script:PathAdderNativeReady = $false
}

# -----------------------------------------------------------------------------
# 1. Paths and directories
# -----------------------------------------------------------------------------

<#
.SYNOPSIS
    Returns the full path of the native Windows PowerShell 5.1 (powershell.exe).
.DESCRIPTION
    Prefers %WINDIR%\System32\WindowsPowerShell\v1.0\powershell.exe (present on
    both 32-bit and 64-bit systems) and falls back to the first powershell.exe
    found on PATH.
#>
function Get-SystemPowerShellPath {
    $candidate = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
        return $candidate
    }

    $cmd = Get-Command -Name 'powershell.exe' -ErrorAction SilentlyContinue
    if ($null -ne $cmd) {
        return $cmd.Source
    }

    return 'powershell.exe'
}

<#
.SYNOPSIS
    Returns the PathAdder application data root: %LOCALAPPDATA%\PathAdder
#>
function Get-PathAdderAppDataRoot {
    $root = $env:LOCALAPPDATA
    if ([string]::IsNullOrWhiteSpace($root)) {
        $root = Join-Path $env:USERPROFILE 'AppData\Local'
    }

    $target = Join-Path $root 'PathAdder'
    if (-not (Test-Path -LiteralPath $target)) {
        New-Item -Path $target -ItemType Directory -Force | Out-Null
    }
    return $target
}

<#
.SYNOPSIS
    Returns the backup directory: %LOCALAPPDATA%\PathAdder\backups (created on demand)
#>
function Get-PathAdderBackupDirectory {
    $dir = Join-Path (Get-PathAdderAppDataRoot) 'backups'
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -Path $dir -ItemType Directory -Force | Out-Null
    }
    return $dir
}

<#
.SYNOPSIS
    Returns the change log file path: %LOCALAPPDATA%\PathAdder\change.log
#>
function Get-PathAdderLogFilePath {
    $root = Get-PathAdderAppDataRoot
    return (Join-Path $root 'change.log')
}

<#
.SYNOPSIS
    Expands a possible 8.3 short path back to its long form (compatibility with
    the legacy behaviour of the context menu passing %1).
#>
function ConvertTo-LongPath {
    param(
        [Parameter(Mandatory = $false)]
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $Path
    }

    Initialize-PathAdderNativeMethods
    if (-not $script:PathAdderNativeReady) {
        return $Path
    }

    try {
        $buffer = New-Object System.Text.StringBuilder(4096)
        $length = [PathAdder.NativeMethods]::GetLongPathName($Path, $buffer, $buffer.Capacity)
        if ($length -gt 0 -and $length -lt $buffer.Capacity) {
            return $buffer.ToString()
        }
    } catch {
        # Degrade: return the input unchanged
    }

    return $Path
}

<#
.SYNOPSIS
    Resolves an argument passed by the context menu (a file or a directory) into
    the absolute path of the directory that contains it.
.DESCRIPTION
    Order of processing: strip paired quotes -> expand $env:XXX / %XXX% ->
    expand 8.3 short paths -> validate a true absolute path -> validate that it
    really exists -> if it is a file, take its parent directory.

    Safety constraint: by default the target must really exist and must be a true
    absolute path. If either condition is missing an empty string is returned and
    the caller reports a clear error and exits - this stops arguments such as
    '...', '.' or 'C:' from being resolved to the current working directory of
    the script and then being added to PATH by mistake.

    Exception: -AllowMissing exists for the Remove (cleanup) scenario. Stale PATH
    entries often point at directories that no longer exist; requiring existence
    there would make them impossible to clean up, while the dialog would tell the
    user to make sure the file still exists - which is plain wrong guidance for a
    Remove. This switch relaxes the existence check only; the absolute path and
    junk input validations remain strict.
.OUTPUTS
    The canonical directory on success, an empty string on failure.
#>
function Resolve-TargetDirectory {
    param(
        [Parameter(Mandatory = $false)]
        [string]$Target,

        [Parameter(Mandatory = $false)]
        [switch]$AllowMissing
    )

    if ([string]::IsNullOrWhiteSpace($Target)) {
        return ''
    }

    # -RequireAbsolute: require a true absolute path and reject dot-only / slash-only
    # and drive-relative forms
    $fullPath = ConvertTo-CanonicalDirectory -Path $Target -RequireAbsolute
    if ([string]::IsNullOrWhiteSpace($fullPath)) {
        return ''
    }

    # Target exists: return directories as-is, and for a file (such as a right-clicked
    # .exe) return the directory that contains it
    if (Test-Path -LiteralPath $fullPath -PathType Container) {
        return $fullPath
    }

    if (Test-Path -LiteralPath $fullPath -PathType Leaf) {
        return (Format-PathAdderDirectory -Path ([System.IO.Path]::GetDirectoryName($fullPath)))
    }

    # Target does not exist
    if ($AllowMissing) {
        # Remove scenario: clean up a stale entry that has disappeared. There is no way
        # to tell whether it used to be a file or a directory, so it is treated as
        # pointing at a directory - the typical case for a cleanup.
        return $fullPath
    }

    return ''
}

<#
.SYNOPSIS
    Normalizes a directory argument written in any form into an absolute path.
.DESCRIPTION
    Processing: trim -> strip paired quotes (both double and single quotes) ->
    expand $env:XXX and %XXX% -> expand 8.3 short paths -> take the absolute path
    -> remove the trailing backslash (except for a drive root). The directory is
    not required to exist (removing a legacy PATH entry requires that).

    With -RequireAbsolute the input must additionally be an absolute path, and
    input consisting only of whitespace / dots / slashes is rejected - such strings
    would be resolved by GetFullPath into the **current working directory**, and if
    they were allowed the CWD of the script could end up in PATH.
#>
function ConvertTo-CanonicalDirectory {
    param(
        [Parameter(Mandatory = $false)]
        [string]$Path,

        [Parameter(Mandatory = $false)]
        [switch]$RequireAbsolute
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return ''
    }

    $result = $Path.Trim()

    # 1) Strip paired quotes: both double and single quotes (more than one level)
    $stripping = $true
    while ($stripping) {
        $stripping = $false
        if ($result.Length -ge 2 -and $result.StartsWith('"') -and $result.EndsWith('"')) {
            $result = $result.Substring(1, $result.Length - 2).Trim()
            $stripping = $true
        }
        if ($result.Length -ge 2 -and $result.StartsWith("'") -and $result.EndsWith("'")) {
            $result = $result.Substring(1, $result.Length - 2).Trim()
            $stripping = $true
        }
    }

    # Clean up a possible leftover stray double quote (single quotes are kept so that
    # apostrophes inside a path are not damaged)
    $result = $result.Trim('"').Trim()

    if ([string]::IsNullOrWhiteSpace($result)) {
        return ''
    }

    # 2) Junk input guard: input made only of whitespace / . / / / \ would be resolved
    #    to the current directory by GetFullPath, so it must be rejected
    if (($result -replace '[\s./\\]', '') -eq '') {
        return ''
    }

    # 3) Expand PowerShell style $env:XXX (for example $env:LOCALAPPDATA\tools)
    try {
        $result = [regex]::Replace($result, '\$env:(\w+)', {
            param($match)
            $name = $match.Groups[1].Value
            $value = [System.Environment]::GetEnvironmentVariable($name)
            if ($null -eq $value) { $match.Value } else { $value }
        })
    } catch {
        # Expansion failed: keep the input as-is
    }

    # 4) Expand Windows style %XXX%
    try {
        $result = [System.Environment]::ExpandEnvironmentVariables($result)
    } catch {
        # Expansion failed: keep the input as-is
    }

    # 5) Expand a possible 8.3 short path
    $result = ConvertTo-LongPath -Path $result

    if ([string]::IsNullOrWhiteSpace($result)) {
        return ''
    }

    # 6) Absolute path validation (optional, for Add-like scenarios that must never
    #    involve the CWD)
    if ($RequireAbsolute) {
        # Note: IsPathRooted() cannot be used here. It also treats the drive-relative
        # forms "C:" / "C:win" as rooted, and GetFullPath expands those against the
        # current directory of that drive - the result depends on the process CWD,
        # which is exactly the same class of problem as "..." resolving to the CWD.
        # Only two forms that are truly independent of the CWD are accepted:
        #   * drive + separator: C:\ or C:/
        #   * UNC: \\server\share
        $trulyRooted = $false
        if ($result -match '^[A-Za-z]:[\\/]') {
            $trulyRooted = $true
        } elseif ($result -match '^\\\\') {
            $trulyRooted = $true
        }

        if (-not $trulyRooted) {
            return ''
        }
    }

    try {
        $result = [System.IO.Path]::GetFullPath($result)
    } catch {
        return ''
    }

    return (Format-PathAdderDirectory -Path $result)
}

<#
.SYNOPSIS
    Canonical directory formatting: removes the trailing backslash (except for a
    drive root).
#>
function Format-PathAdderDirectory {
    param(
        [Parameter(Mandatory = $false)]
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return ''
    }

    $result = $Path.Trim()
    if ($result -match '^[A-Za-z]:\\$') {
        return $result
    }

    return $result.TrimEnd('\')
}

# -----------------------------------------------------------------------------
# 2. PATH normalization and comparison
# -----------------------------------------------------------------------------

<#
.SYNOPSIS
    Splits a PATH string into an array of entries on semicolons (dropping blank ones).
#>
function Split-PathList {
    param(
        [Parameter(Mandatory = $false)]
        [string]$Value
    )

    $list = @()
    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $list
    }

    foreach ($part in ($Value -split ';')) {
        if (-not [string]::IsNullOrWhiteSpace($part)) {
            $list += $part
        }
    }

    return $list
}

<#
.SYNOPSIS
    Normalizes a path for comparison: strip quotes -> expand environment variables
    -> unify separators -> remove the trailing backslash -> lowercase.
#>
function ConvertTo-NormalizedPath {
    param(
        [Parameter(Mandatory = $false)]
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return ''
    }

    $result = $Path.Trim()
    $result = $result.Trim().Trim('"').Trim()

    try {
        $result = [System.Environment]::ExpandEnvironmentVariables($result)
    } catch {
        # Expansion failed: keep the input as-is
    }

    $result = $result.Trim().Trim('"').Trim()
    $result = $result.Replace('/', '\')

    if ($result -match '^[A-Za-z]:\\$') {
        return $result.ToLowerInvariant()
    }

    return $result.TrimEnd('\').ToLowerInvariant()
}

<#
.SYNOPSIS
    Tests whether a directory is already present in a list of PATH entries
    (robust duplicate comparison).
#>
function Test-PathInList {
    param(
        [Parameter(Mandatory = $false)]
        [string[]]$Entries,

        [Parameter(Mandatory = $false)]
        [string]$Directory
    )

    $target = ConvertTo-NormalizedPath -Path $Directory
    if ([string]::IsNullOrWhiteSpace($target)) {
        return $false
    }

    foreach ($entry in $Entries) {
        $current = ConvertTo-NormalizedPath -Path $entry
        if ($current -eq $target) {
            return $true
        }
    }

    return $false
}

# -----------------------------------------------------------------------------
# 3. Registry PATH read and write (keeps the original value type)
# -----------------------------------------------------------------------------

<#
.SYNOPSIS
    Normalizes the various spellings of a value type name into the name really
    used by the registry.
.DESCRIPTION
    Pitfall: the member of Microsoft.Win32.RegistryValueKind is named
    ExpandString, not ExpandSz; in PowerShell 5.1 writing ::ExpandSz does not
    throw, it silently returns $null, which then breaks overload resolution of
    the 3-parameter SetValue. Mapping everything here removes that problem.

    This tool only handles **string typed** PATH values. Unknown/None falls back
    to REG_EXPAND_SZ as the default type for a newly created value (the Windows
    convention); for Binary/DWord/QWord or any unknown name it does not fall back
    silently but warns explicitly first, so that numeric registry values are never
    overwritten out of overconfidence.
#>
function ConvertTo-RegistryValueKindName {
    param(
        [Parameter(Mandatory = $false)]
        [string]$KindName = ''
    )

    if ([string]::IsNullOrWhiteSpace($KindName)) {
        # No type given: create PATH as REG_EXPAND_SZ, following the Windows convention
        return 'ExpandString'
    }

    switch ($KindName) {
        'Unknown'      { return 'ExpandString' }   # value does not exist yet, same as above
        'None'         { return 'ExpandString' }   # same as above
        'String'       { return 'String' }
        'ExpandString' { return 'ExpandString' }
        'ExpandSz'     { return 'ExpandString' }   # compatibility with the old spelling in logs
        'MultiString'  { return 'MultiString' }
        default {
            Write-Warning (Get-PathAdderText -Key 'Core.Warn.UnknownPathValueKind' -Arguments @($KindName) -Default ('PATH value type is unknown or non-string: ' + $KindName))
            return 'ExpandString'
        }
    }
}

<#
.SYNOPSIS
    Safely converts a value type name into a Microsoft.Win32.RegistryValueKind value.
#>
function ConvertTo-RegistryValueKind {
    param(
        [Parameter(Mandatory = $false)]
        [string]$KindName = ''
    )

    $canonical = ConvertTo-RegistryValueKindName -KindName $KindName
    return [System.Enum]::Parse([Microsoft.Win32.RegistryValueKind], $canonical)
}

<#
.SYNOPSIS
    Returns the registry sub key path relative to the hive for a given scope.
#>
function Get-PathAdderRegistrySubKeyPath {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('User', 'System')]
        [string]$Scope
    )

    if ($Scope -eq 'User') {
        return 'Environment'
    }

    return 'SYSTEM\CurrentControlSet\Control\Session Manager\Environment'
}

<#
.SYNOPSIS
    Opens the registry key that holds PATH.
#>
function Open-PathAdderRegistryKey {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('User', 'System')]
        [string]$Scope,

        [Parameter(Mandatory = $false)]
        [switch]$Writable
    )

    $subKeyPath = Get-PathAdderRegistrySubKeyPath -Scope $Scope

    if ($Scope -eq 'User') {
        if ($Writable) {
            return [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($subKeyPath, $true)
        }
        return [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($subKeyPath, $false)
    }

    if ($Writable) {
        return [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($subKeyPath, $true)
    }
    return [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($subKeyPath, $false)
}

<#
.SYNOPSIS
    Reads PATH for a given scope and returns an object with Value / Kind / Exists.
.DESCRIPTION
    Pitfall: Path may be REG_EXPAND_SZ, may be REG_SZ, and may not exist at all.
    Both the value (GetValue) and the type (GetValueKind) are read here, and the
    original type is preserved when writing back.
#>
function Get-EnvironmentPathInfo {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('User', 'System')]
        [string]$Scope
    )

    $result = New-Object PSObject -Property @{
        Scope   = $Scope
        Exists  = $false
        Value   = ''
        Kind    = 'Unknown'
        Error   = ''
        Entries = @()
    }

    $key = $null
    try {
        $key = Open-PathAdderRegistryKey -Scope $Scope
    } catch {
        $result.Error = $_.Exception.Message
        return $result
    }

    if ($null -eq $key) {
        $result.Error = Get-PathAdderText -Key 'Core.Err.RegistryKeyOpenFailed' -Default 'Unable to open the registry key.'
        return $result
    }

    try {
        $value = $key.GetValue('Path', $null)
        if ($null -ne $value) {
            $result.Exists = $true
            $result.Value = [string]$value
        }

        try {
            $kind = $key.GetValueKind('Path')
            if ($null -ne $kind) {
                $result.Kind = $kind.ToString()
            }
        } catch {
            # GetValueKind throws when the value does not exist: keep Unknown
            $result.Kind = 'Unknown'
        }

        # Normalization: Unknown / None falls back to REG_EXPAND_SZ (the most common
        # type for Path on Windows)
        $result.Kind = ConvertTo-RegistryValueKindName -KindName $result.Kind

        $result.Entries = @(Split-PathList -Value $result.Value)
    } finally {
        $key.Close()
    }

    return $result
}

<#
.SYNOPSIS
    Writes PATH for a given scope and keeps the original value type.
#>
function Set-EnvironmentPathValue {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('User', 'System')]
        [string]$Scope,

        [Parameter(Mandatory = $true)]
        [string]$Value,

        [Parameter(Mandatory = $false)]
        [string]$Kind = 'ExpandString'
    )

    $key = $null
    try {
        $key = Open-PathAdderRegistryKey -Scope $Scope -Writable
    } catch {
        throw (Get-PathAdderText -Key 'Core.Err.RegistryWriteOpenFailed' -Arguments @($_.Exception.Message) -Default ('Failed to open the registry for writing: ' + $_.Exception.Message))
    }

    if ($null -eq $key) {
        throw (Get-PathAdderText -Key 'Core.Err.RegistryWriteHandleFailed' -Arguments @($Scope) -Default ('Failed to open the registry for writing: ' + $Scope))
    }

    try {
        $valueKind = ConvertTo-RegistryValueKind -KindName $Kind
        $key.SetValue('Path', $Value, $valueKind)
    } finally {
        $key.Close()
    }
}

# -----------------------------------------------------------------------------
# 4. Backup and log
# -----------------------------------------------------------------------------

<#
.SYNOPSIS
    Appends one line to the change log.
.DESCRIPTION
    Log line format (human readable and parseable):
    [yyyy-MM-dd HH:mm:ss] action=Add scope=User dir=D:\bin backup=user-20261002-070000.txt kind=ExpandString

    The field labels are localized, so a log written in one language can contain
    the labels of another; Get-BackupKindFromLog accepts both spellings.
#>
function Write-PathAdderLog {
    param(
        [Parameter(Mandatory = $false)]
        [string]$Scope = '-',

        [Parameter(Mandatory = $false)]
        [string]$Action = '-',

        [Parameter(Mandatory = $false)]
        [string]$Directory = '-',

        [Parameter(Mandatory = $false)]
        [string]$BackupFile = '-',

        [Parameter(Mandatory = $false)]
        [string]$Kind = '-'
    )

    $logFile = Get-PathAdderLogFilePath
    $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = '[' + $stamp + '] ' +
            (Get-PathAdderText -Key 'Core.Log.Label.Action'    -Default 'action=')    + $Action +
            ' ' + (Get-PathAdderText -Key 'Core.Log.Label.Scope'     -Default 'scope=')     + $Scope +
            ' ' + (Get-PathAdderText -Key 'Core.Log.Label.Directory' -Default 'dir=')        + $Directory +
            ' ' + (Get-PathAdderText -Key 'Core.Log.Label.Backup'    -Default 'backup=')     + $BackupFile +
            ' ' + (Get-PathAdderText -Key 'Core.Log.Label.Kind'      -Default 'kind=')       + $Kind

    try {
        Add-Content -LiteralPath $logFile -Value $line -Encoding UTF8 -ErrorAction Stop
    } catch {
        # A logging failure must not block the main flow
    }
}

<#
.SYNOPSIS
    Backs up the current PATH value before modifying it, and writes a log entry.
.OUTPUTS
    An object with FileName / FullPath.
#>
function Backup-EnvironmentPath {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('User', 'System')]
        [string]$Scope,

        [Parameter(Mandatory = $false)]
        [string]$Action = 'Unknown',

        [Parameter(Mandatory = $false)]
        [string]$Directory = '-',

        [Parameter(Mandatory = $false)]
        [string]$CurrentValue = '',

        [Parameter(Mandatory = $false)]
        [string]$Kind = 'ExpandString'
    )

    $backupDir = Get-PathAdderBackupDirectory
    $prefix = $Scope.ToLowerInvariant()
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'

    $fileName = $prefix + '-' + $stamp + '.txt'
    $fullPath = Join-Path $backupDir $fileName
    $index = 1
    while (Test-Path -LiteralPath $fullPath) {
        $fileName = $prefix + '-' + $stamp + '-' + $index + '.txt'
        $fullPath = Join-Path $backupDir $fileName
        $index = $index + 1
    }

    $content = ''
    if ($null -ne $CurrentValue) {
        $content = [string]$CurrentValue
    }

    Set-Content -LiteralPath $fullPath -Value $content -Encoding UTF8 -ErrorAction Stop

    Write-PathAdderLog -Scope $Scope -Action $Action -Directory $Directory -BackupFile $fileName -Kind $Kind

    return New-Object PSObject -Property @{
        FileName = $fileName
        FullPath = $fullPath
    }
}

<#
.SYNOPSIS
    Looks up the PATH value type recorded for a backup in the change log (used to
    keep the type when restoring).
.DESCRIPTION
    Both the localized label and the historical Chinese label are accepted, so
    backups logged before the i18n conversion are still resolved correctly.
#>
function Get-BackupKindFromLog {
    param(
        [Parameter(Mandatory = $false)]
        [string]$BackupFileName
    )

    if ([string]::IsNullOrWhiteSpace($BackupFileName)) {
        return ''
    }

    $logFile = Get-PathAdderLogFilePath
    if (-not (Test-Path -LiteralPath $logFile)) {
        return ''
    }

    $backupLabel = Get-PathAdderText -Key 'Core.Log.Label.Backup' -Default 'backup='
    $kindLabel = Get-PathAdderText -Key 'Core.Log.Label.Kind' -Default 'kind='
    $pattern = '(?:' + [regex]::Escape($backupLabel) + '|' + [regex]::Escape('备份=') + ')' +
               [regex]::Escape($BackupFileName) +
               '\s+(?:' + [regex]::Escape($kindLabel) + '|' + [regex]::Escape('类型=') + ')(\S+)'
    $lines = @(Get-Content -LiteralPath $logFile -Encoding UTF8 -ErrorAction SilentlyContinue)

    for ($i = $lines.Count - 1; $i -ge 0; $i--) {
        if ($lines[$i] -match $pattern) {
            return $matches[1]
        }
    }

    return ''
}

<#
.SYNOPSIS
    Lists all backup files (newest first).
#>
function Get-PathAdderBackups {
    $dir = Get-PathAdderBackupDirectory
    $files = @(Get-ChildItem -LiteralPath $dir -Filter '*.txt' -File -ErrorAction SilentlyContinue |
        Sort-Object -Property LastWriteTime -Descending)

    $items = @()
    foreach ($file in $files) {
        $scopeKey = 'User'
        $scopeLabel = Get-PathAdderText -Key 'App.Scope.User' -Default 'User'
        if ($file.Name.ToLowerInvariant().StartsWith('system-')) {
            $scopeKey = 'System'
            $scopeLabel = Get-PathAdderText -Key 'App.Scope.System' -Default 'System'
        }

        $items += New-Object PSObject -Property @{
            FileName      = $file.Name
            FullPath      = $file.FullName
            Scope         = $scopeKey
            ScopeLabel    = $scopeLabel
            LastWriteTime = $file.LastWriteTime
            Length        = $file.Length
        }
    }

    return $items
}

<#
.SYNOPSIS
    Restores a backup.
.DESCRIPTION
    A restore is itself a modification, so the current PATH is backed up first
    and then overwritten.
#>
function Restore-PathBackup {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BackupFileName
    )

    $backupDir = Get-PathAdderBackupDirectory
    $fullPath = Join-Path $backupDir $BackupFileName
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        throw (Get-PathAdderText -Key 'Core.Err.BackupFileNotFound' -Arguments @($fullPath) -Default ('Backup file not found: ' + $fullPath))
    }

    $scope = 'User'
    if ($BackupFileName.ToLowerInvariant().StartsWith('system-')) {
        $scope = 'System'
    }

    $content = ''
    $raw = Get-Content -LiteralPath $fullPath -Raw -Encoding UTF8 -ErrorAction Stop
    if ($null -ne $raw) {
        $content = ([string]$raw).TrimEnd([char[]]@([char]13, [char]10))
    }

    $kind = Get-BackupKindFromLog -BackupFileName $BackupFileName
    if ([string]::IsNullOrWhiteSpace($kind) -or $kind -eq 'Unknown') {
        $currentInfo = Get-EnvironmentPathInfo -Scope $scope
        $kind = $currentInfo.Kind
    }
    $kind = ConvertTo-RegistryValueKindName -KindName $kind

    # Back up the current value before restoring
    $currentInfo = Get-EnvironmentPathInfo -Scope $scope
    $backup = Backup-EnvironmentPath -Scope $scope -Action 'Restore' `
        -Directory (Get-PathAdderText -Key 'Core.Log.RestoreFrom' -Arguments @($BackupFileName) -Default ('restored from ' + $BackupFileName)) `
        -CurrentValue $currentInfo.Value `
        -Kind $currentInfo.Kind

    Set-EnvironmentPathValue -Scope $scope -Value $content -Kind $kind
    Publish-EnvironmentChange -Scope $scope -Value $content

    return New-Object PSObject -Property @{
        Scope          = $scope
        RestoredFrom   = $BackupFileName
        BackupFile     = $backup.FileName
        RestoredValue  = $content
    }
}

# -----------------------------------------------------------------------------
# 5. Broadcasting the environment change
# -----------------------------------------------------------------------------

<#
.SYNOPSIS
    Updates the environment variable of the current process and broadcasts
    WM_SETTINGCHANGE to all top level windows.
#>
function Publish-EnvironmentChange {
    param(
        [Parameter(Mandatory = $false)]
        [ValidateSet('User', 'System')]
        [string]$Scope = 'User',

        [Parameter(Mandatory = $false)]
        [string]$Value = ''
    )

    # 1) Update the environment variable of the **current process**.
    #    Note: never use Environment.SetEnvironmentVariable(name, value, 'User'/'Machine'),
    #    that overload **writes back to the registry** and silently turns REG_EXPAND_SZ
    #    into REG_SZ, breaking the "keep the original value type" requirement. Only the
    #    default Process target is used here (memory only, the registry is not touched).
    $combined = ''
    try {
        $machine = [System.Environment]::GetEnvironmentVariable('Path', 'Machine')
        $user = [System.Environment]::GetEnvironmentVariable('Path', 'User')
        if ([string]::IsNullOrEmpty($machine)) {
            $combined = $user
        } elseif ([string]::IsNullOrEmpty($user)) {
            $combined = $machine
        } else {
            $combined = $machine + ';' + $user
        }
    } catch {
        $combined = ''
    }

    if ($combined -ne '') {
        try {
            [System.Environment]::SetEnvironmentVariable('Path', $combined)
            $env:Path = $combined
        } catch {
            # Ignored: affects the current process only
        }
    }

    # 3) Broadcast WM_SETTINGCHANGE so that Explorer and already running programs notice
    Initialize-PathAdderNativeMethods
    if (-not $script:PathAdderNativeReady) {
        return
    }

    try {
        $hwndBroadcast = [IntPtr]0xffff
        $WM_SETTINGCHANGE = [uint32]0x001A
        $SMTO_ABORTIFHUNG = [uint32]0x0002
        $result = [UIntPtr]::Zero

        [void][PathAdder.NativeMethods]::SendMessageTimeout(
            $hwndBroadcast,
            $WM_SETTINGCHANGE,
            [UIntPtr]::Zero,
            'Environment',
            $SMTO_ABORTIFHUNG,
            [uint32]5000,
            [ref]$result)
    } catch {
        # A failed broadcast does not change the registry result
    }
}

# -----------------------------------------------------------------------------
# 6. Administrator detection and UAC self-elevation
# -----------------------------------------------------------------------------

<#
.SYNOPSIS
    Tests whether the current process runs elevated.
#>
function Test-PathAdderAdministrator {
    try {
        $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object System.Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        return $false
    }
}

<#
.SYNOPSIS
    Restarts a script with administrator rights (triggers the UAC prompt).
.DESCRIPTION
    Three conditions must be met at the same time, none of them optional:
      1. UseShellExecute = $true - otherwise Verb is ignored and no elevation happens;
      2. Verb = 'runas'          - the switch that actually triggers UAC elevation;
      3. the process is started through Start() - clicking "No" throws Win32Exception.

    Because UseShellExecute must stay $true, ProcessStartInfo.EnvironmentVariables
    cannot be used (the two are mutually exclusive), so the current language is
    handed to the child process as the -Language command line argument instead.
.OUTPUTS
    $true when the elevated process was started; $false when the user cancelled UAC
    or elevation failed.
#>
function Invoke-SelfElevation {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptPath,

        [Parameter(Mandatory = $false)]
        [string[]]$ArgumentList = @()
    )

    $quotedArgs = New-Object System.Collections.ArrayList

    # Propagate the language to the child process: -Language "<code>" right after -File
    if (Get-Command -Name 'Get-PathAdderLanguageArgument' -ErrorAction SilentlyContinue) {
        foreach ($langArg in (Get-PathAdderLanguageArgument)) {
            [void]$quotedArgs.Add('"' + ([string]$langArg) + '"')
        }
    }

    foreach ($arg in $ArgumentList) {
        $escaped = ([string]$arg) -replace '"', '\"'
        [void]$quotedArgs.Add('"' + $escaped + '"')
    }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = Get-SystemPowerShellPath
    $psi.Arguments = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $ScriptPath + '" ' + ($quotedArgs -join ' ')
    $psi.UseShellExecute = $true
    # Critical: Verb='runas' is the switch that triggers UAC. Without this line every
    # setting above only launches another powershell with the current user rights, and
    # writing the system PATH is still refused.
    $psi.Verb = 'runas'
    $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
    $psi.WorkingDirectory = (Split-Path -Parent $ScriptPath)

    try {
        [void][System.Diagnostics.Process]::Start($psi)
        return $true
    } catch {
        # The user clicked "No" in UAC, or the account cannot be elevated
        return $false
    }
}

<#
.SYNOPSIS
    Starts a PowerShell script as a separate (hidden console) process.
.DESCRIPTION
    The current language is passed on the command line (-Language "<code>") because
    ProcessStartInfo.EnvironmentVariables is not available with UseShellExecute.
#>
function Start-PathAdderScript {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptPath,

        [Parameter(Mandatory = $false)]
        [string[]]$ArgumentList = @()
    )

    $quotedArgs = New-Object System.Collections.ArrayList

    # Propagate the language to the child process: -Language "<code>" right after -File
    if (Get-Command -Name 'Get-PathAdderLanguageArgument' -ErrorAction SilentlyContinue) {
        foreach ($langArg in (Get-PathAdderLanguageArgument)) {
            [void]$quotedArgs.Add('"' + ([string]$langArg) + '"')
        }
    }

    foreach ($arg in $ArgumentList) {
        $escaped = ([string]$arg) -replace '"', '\"'
        [void]$quotedArgs.Add('"' + $escaped + '"')
    }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = Get-SystemPowerShellPath
    $psi.Arguments = '-NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $ScriptPath + '" ' + ($quotedArgs -join ' ')
    $psi.UseShellExecute = $true
    $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
    $psi.WorkingDirectory = (Split-Path -Parent $ScriptPath)

    try {
        [void][System.Diagnostics.Process]::Start($psi)
        return $true
    } catch {
        return $false
    }
}

# -----------------------------------------------------------------------------
# 7. Message box
# -----------------------------------------------------------------------------

<#
.SYNOPSIS
    Shows the common Windows message box (title defaults to the application name).
#>
function Show-PathAdderMessageBox {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [string]$Title = '',

        [Parameter(Mandatory = $false)]
        [ValidateSet('Information', 'Warning', 'Error', 'Question')]
        [string]$Icon = 'Information'
    )

    if ([string]::IsNullOrWhiteSpace($Title)) {
        $Title = Get-PathAdderText -Key 'App.Name' -Default 'PATH Assistant'
    }

    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
    } catch {
        Write-Host ('[' + $Title + '] ' + $Message)
        return
    }

    $iconType = [System.Windows.Forms.MessageBoxIcon]::Information
    if ($Icon -eq 'Warning') {
        $iconType = [System.Windows.Forms.MessageBoxIcon]::Warning
    } elseif ($Icon -eq 'Error') {
        $iconType = [System.Windows.Forms.MessageBoxIcon]::Error
    } elseif ($Icon -eq 'Question') {
        $iconType = [System.Windows.Forms.MessageBoxIcon]::Question
    }

    try {
        [void][System.Windows.Forms.MessageBox]::Show(
            $Message,
            $Title,
            [System.Windows.Forms.MessageBoxButtons]::OK,
            $iconType)
    } catch {
        Write-Host ('[' + $Title + '] ' + $Message)
    }
}

# -----------------------------------------------------------------------------
# 8. PATH modification operations
# -----------------------------------------------------------------------------

<#
.SYNOPSIS
    Adds a directory to PATH for a given scope.
.DESCRIPTION
    Flow: read -> duplicate check (on a hit it returns AlreadyExists immediately,
    without touching the registry and without a backup) -> back up -> write the
    registry (keeping the original type) -> broadcast.
.OUTPUTS
    An object with Status / Scope / Directory / BackupFile / Message.
    Status is a programming contract and is always one of the English values
    Added / Removed / AlreadyExists / NotFound / Failed.
#>
function Add-DirectoryToPath {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('User', 'System')]
        [string]$Scope,

        [Parameter(Mandatory = $true)]
        [string]$Directory
    )

    $result = New-Object PSObject -Property @{
        Status     = 'Failed'
        Scope      = $Scope
        Directory  = $Directory
        BackupFile = ''
        NewValue   = ''
        Message    = ''
    }

    if ([string]::IsNullOrWhiteSpace($Directory)) {
        $result.Message = Get-PathAdderText -Key 'Core.Msg.Add.DirEmpty' -Default 'The directory is empty; nothing was added.'
        return $result
    }

    # Normalization: strip quotes -> expand environment variables -> expand short names ->
    # absolute path -> remove the trailing backslash
    # -RequireAbsolute: reject relative paths and junk input, never involve the CWD
    $target = ConvertTo-CanonicalDirectory -Path $Directory -RequireAbsolute
    if ([string]::IsNullOrWhiteSpace($target)) {
        $result.Message = Get-PathAdderText -Key 'Core.Msg.Add.InvalidDir' -Arguments @($Directory) -Default ('Invalid directory path: ' + $Directory)
        return $result
    }
    $result.Directory = $target

    if (-not (Test-Path -LiteralPath $target -PathType Container)) {
        $result.Message = Get-PathAdderText -Key 'Core.Msg.DirNotFound' -Arguments @($target) -Default ('The directory does not exist: ' + $target)
        return $result
    }

    $info = Get-EnvironmentPathInfo -Scope $Scope
    if (-not [string]::IsNullOrEmpty($info.Error)) {
        $result.Message = Get-PathAdderText -Key 'Core.Msg.ReadPathFailed' -Arguments @($info.Error) -Default ('Failed to read PATH: ' + $info.Error)
        return $result
    }

    if (Test-PathInList -Entries $info.Entries -Directory $target) {
        $result.Status = 'AlreadyExists'
        $result.Message = Get-PathAdderText -Key 'Core.Msg.Add.AlreadyExists' -Default 'The directory is already present in PATH; nothing was changed.'
        return $result
    }

    $newValue = ''
    if ([string]::IsNullOrWhiteSpace($info.Value)) {
        $newValue = $target
    } else {
        $newValue = $info.Value.TrimEnd(';') + ';' + $target
    }

    $backup = Backup-EnvironmentPath -Scope $Scope -Action 'Add' -Directory $target `
        -CurrentValue $info.Value -Kind $info.Kind
    $result.BackupFile = $backup.FileName

    try {
        Set-EnvironmentPathValue -Scope $Scope -Value $newValue -Kind $info.Kind
    } catch {
        $result.Status = 'Failed'
        $result.Message = Get-PathAdderText -Key 'Core.Msg.WritePathFailed' -Arguments @($backup.FileName, $_.Exception.Message) -Default ('Failed to write PATH: ' + $_.Exception.Message)
        Write-PathAdderLog -Scope $Scope -Action 'AddFailed' -Directory $target -BackupFile $backup.FileName -Kind $info.Kind
        return $result
    }

    Publish-EnvironmentChange -Scope $Scope -Value $newValue

    $result.Status = 'Added'
    $result.NewValue = $newValue
    $result.Message = Get-PathAdderText -Key 'Core.Msg.Added' -Default 'Added to PATH.'
    return $result
}

<#
.SYNOPSIS
    Removes a directory from PATH for a given scope.
.OUTPUTS
    An object with Status / Scope / Directory / BackupFile / Message.
    Status is a programming contract and is always one of the English values
    Added / Removed / AlreadyExists / NotFound / Failed.
#>
function Remove-DirectoryFromPath {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('User', 'System')]
        [string]$Scope,

        [Parameter(Mandatory = $true)]
        [string]$Directory
    )

    $result = New-Object PSObject -Property @{
        Status     = 'Failed'
        Scope      = $Scope
        Directory  = $Directory
        BackupFile = ''
        NewValue   = ''
        Message    = ''
    }

    if ([string]::IsNullOrWhiteSpace($Directory)) {
        $result.Message = Get-PathAdderText -Key 'Core.Msg.Remove.DirEmpty' -Default 'The directory is empty; nothing was removed.'
        return $result
    }

    # Same normalization as Add (a directory that no longer exists may be removed)
    # -RequireAbsolute applies here too: the drive-relative form "C:" would be expanded
    # against the CWD, and allowing it could make one right-click "Remove" silently
    # delete a legitimate PATH entry - unacceptable damage.
    $target = ConvertTo-CanonicalDirectory -Path $Directory -RequireAbsolute
    if ([string]::IsNullOrWhiteSpace($target)) {
        $result.Message = Get-PathAdderText -Key 'Core.Msg.Remove.InvalidDir' -Arguments @($Directory) -Default ('Invalid directory path: ' + $Directory)
        return $result
    }
    $result.Directory = $target

    $info = Get-EnvironmentPathInfo -Scope $Scope
    if (-not [string]::IsNullOrEmpty($info.Error)) {
        $result.Message = Get-PathAdderText -Key 'Core.Msg.ReadPathFailed' -Arguments @($info.Error) -Default ('Failed to read PATH: ' + $info.Error)
        return $result
    }

    $targetNormalized = ConvertTo-NormalizedPath -Path $target

    $kept = New-Object System.Collections.ArrayList
    $removed = $false
    foreach ($entry in $info.Entries) {
        $entryNormalized = ConvertTo-NormalizedPath -Path $entry
        if ($entryNormalized -eq $targetNormalized) {
            $removed = $true
            continue
        }
        [void]$kept.Add($entry)
    }

    if (-not $removed) {
        $result.Status = 'NotFound'
        $result.Message = Get-PathAdderText -Key 'Core.Msg.Remove.NotFound' -Default 'The directory is not present in PATH; nothing was changed.'
        return $result
    }

    $newValue = [string]::Join(';', ($kept.ToArray()))

    $backup = Backup-EnvironmentPath -Scope $Scope -Action 'Remove' -Directory $target `
        -CurrentValue $info.Value -Kind $info.Kind
    $result.BackupFile = $backup.FileName

    try {
        Set-EnvironmentPathValue -Scope $Scope -Value $newValue -Kind $info.Kind
    } catch {
        $result.Status = 'Failed'
        $result.Message = Get-PathAdderText -Key 'Core.Msg.WritePathFailed' -Arguments @($backup.FileName, $_.Exception.Message) -Default ('Failed to write PATH: ' + $_.Exception.Message)
        Write-PathAdderLog -Scope $Scope -Action 'RemoveFailed' -Directory $target -BackupFile $backup.FileName -Kind $info.Kind
        return $result
    }

    Publish-EnvironmentChange -Scope $Scope -Value $newValue

    $result.Status = 'Removed'
    $result.NewValue = $newValue
    $result.Message = Get-PathAdderText -Key 'Core.Msg.Removed' -Default 'Removed from PATH.'
    return $result
}

# -----------------------------------------------------------------------------
# 9. Version
# -----------------------------------------------------------------------------

<#
.SYNOPSIS
    Returns the PathAdder version string read from the root version.json.
.DESCRIPTION
    The repository/installation root is located in the same way the rest of the
    library locates its own folder: $PSScriptRoot of lib\Common.ps1 is the lib\
    directory, so its parent is the application root. A registered
    $global:PathAdderRootDirectory takes precedence when an entry point has
    already published it.

    Failure is never fatal: when version.json is missing, unreadable, malformed,
    or has no usable `version` field, the sentinel '0.0.0-dev' is returned so the
    caller can display something sensible instead of crashing.
.OUTPUTS
    The version string (for example '1.0.0'), or '0.0.0-dev' on any failure.
#>
function Get-PathAdderVersion {
    $root = $global:PathAdderRootDirectory
    if ([string]::IsNullOrWhiteSpace($root)) {
        # lib\Common.ps1 lives in lib\, so the parent of $PSScriptRoot is the root
        $libDirectory = $PSScriptRoot
        if ([string]::IsNullOrWhiteSpace($libDirectory)) {
            $libDirectory = Split-Path -Parent $MyInvocation.MyCommand.Definition
        }
        if (-not [string]::IsNullOrWhiteSpace($libDirectory)) {
            $root = Split-Path -Parent $libDirectory
        }
    }

    if ([string]::IsNullOrWhiteSpace($root)) {
        return '0.0.0-dev'
    }

    $file = Join-Path $root 'version.json'
    try {
        if (Test-Path -LiteralPath $file -PathType Leaf) {
            # Read explicitly as UTF-8: version.json must be stored without a BOM,
            # and an explicit encoding keeps behaviour identical on every host locale
            # (PS 5.1 otherwise falls back to the ANSI code page).
            $raw = [System.IO.File]::ReadAllText($file, [System.Text.Encoding]::UTF8)
            $obj = $raw | ConvertFrom-Json
            if ($null -ne $obj -and -not [string]::IsNullOrWhiteSpace($obj.version)) {
                return [string]$obj.version
            }
        }
    } catch {
        # Never throw: the version string is cosmetic and must not break a flow
    }

    return '0.0.0-dev'
}
