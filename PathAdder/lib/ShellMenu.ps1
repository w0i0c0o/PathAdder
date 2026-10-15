# -----------------------------------------------------------------------------
# PathAdder - Shell context menu registration and Shell cache refresh (lib\ShellMenu.ps1)
#
# Target runtime: Windows PowerShell 5.1 (never use PS7-only syntax such as
# ?? / && / || / the ternary operator / $PSStyle).
#
# Capabilities:
#   1. Get-PathAdderShellVerbDefinitions      - single source of truth for the 4 commands
#   2. Get-PathAdderShellRegistrationLocation - the current registration location (single)
#   3. Get-PathAdderShellCleanupLocations     - every location to clean (current + historical)
#   4. Install-PathAdderShellMenu             - idempotent write of the menu under HKCU
#   5. Uninstall-PathAdderShellMenu           - removes exactly this tool's own keys
#   6. Update-PathAdderShellAssociationCache  - notifies Explorer to refresh its association cache
#   7. Restart-PathAdderExplorer              - restarts Explorer (must ask the user first)
#
# Localization note (important, applies to the whole module):
#   Every string written into the registry (the parent menu label and the four
#   command labels) is resolved through T 'Shell.*' at *registration* time, in the
#   language that is active when Install-PathAdderShellMenu runs. Windows stores a
#   plain literal there, so switching the language afterwards does NOT rewrite
#   entries that were already registered: the user must re-run install.ps1
#   (or re-register the menu) to refresh the context menu text. This is inherent
#   to how registry verbs work and is deliberately left unchanged - do not try to
#   "fix" it from inside this file.
#
# -----------------------------------------------------------------------------
# [Registration location: HKCU\Software\Classes\*\shell\PathAdder]
#
#   `*` is the officially supported Windows association key for "all file objects",
#   covering any extension (including .exe). Early versions registered under
#   `exefile\shell` (only affects .exe) and `SystemFileAssociations\.exe\shell`
#   (lazy fallback when .exe has no associated ProgID); both are retired:
#     - exefile: the requirement changed to "works when right-clicking any file",
#       and `*` already covers .exe; registering both would simply make the same
#       action appear twice in the menu;
#     - SystemFileAssociations\.exe: it only existed as a fallback for .exe without
#       an associated ProgID. Since `*` unconditionally covers every file, that
#       fallback has lost all meaning and was removed entirely.
#   A single registration point is the cleanest option and least likely to produce
#   duplicated menu entries.
#
#   Uninstall must clean all three locations (current + two historical), otherwise
#   upgrading users keep orphan menu entries under exefile\shell and
#   SystemFileAssociations\.exe\shell.
#
# -----------------------------------------------------------------------------
# [Submenu implementation: click to expand, not native SubCommands hover cascade]  (changed 2026-10-04)
#
#   Early versions used the native Windows static cascade (hover to expand):
#
#       parent\SubCommands = "PathAdder.AddUser;PathAdder.AddSystem;…"
#       parent\shell\PathAdder.AddUser\command
#
#   It works on Windows 7/10 but was measured to FAIL on Windows 11: the parent
#   entry is visible yet never expands on hover, and because the SubCommands
#   mechanism forbids a command on the parent entry, clicking does nothing either -
#   the feature is completely unusable.
#
#   Root cause: Windows 11 switched to a new context menu pipeline where classic
#   registry verbs are surfaced through an "ExplorerCommand verb" wrapper. That
#   wrapper has incomplete support for the static SubCommands cascade; the more
#   third-party IExplorerCommand extensions are installed, the more obvious the
#   failure is.
#
#   Current approach (reliability first):
#
#     HKCU\Software\Classes\*\shell\PathAdder
#         (Default)          = "PATH Assistant"
#         MUIVerb            = "PATH Assistant"
#         Icon               = "…powershell.exe,0"
#         NoWorkingDirectory = ""
#         └─ command\(Default) = powershell … -File "…\MenuPicker.ps1" -Target "%V"
#
#   Clicking the parent lets MenuPicker.ps1 pop a native WinForms ContextMenuStrip
#   at the cursor position. It looks and behaves much like a native cascading
#   submenu without depending on Explorer's cascade implementation.
#   Trade-off: a "click" is required instead of a "hover" - the only approach that
#   is 100% reliable on Windows 11.
#
#   Upgrade compatibility: installation removes the leftover SubCommands value and
#   the …\shell\ subcommand tree from the previous version; uninstall deletes the
#   whole PathAdder subtree, and the two historical locations (exefile, SFA) have
#   their own cleanup logic.
#
#   Position="Bottom" is intentionally unused: see install.ps1 (discoverability
#   beats menu tidiness).
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# 0. State, localization bootstrap and native methods
# -----------------------------------------------------------------------------

# Defensive i18n load. This file normally gets dot-sourced by lib\Common.ps1 or by
# a top-level script that already loaded lib\i18n.ps1, but it is also dot-sourced
# directly by install.ps1 / uninstall.ps1 / verify-registration.ps1. Loading it here
# - only when Get-PathAdderText is still missing - makes both paths work without
# ever overwriting an already-initialized language pack.
if (-not (Get-Command -Name 'Get-PathAdderText' -ErrorAction SilentlyContinue)) {
    $script:PathAdderShellLibDirectory = ''
    if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
        $script:PathAdderShellLibDirectory = $PSScriptRoot
    } elseif ($null -ne $MyInvocation -and $null -ne $MyInvocation.MyCommand) {
        try {
            $script:PathAdderShellLibDirectory = Split-Path -Parent $MyInvocation.MyCommand.Definition
        } catch {
            $script:PathAdderShellLibDirectory = ''
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($script:PathAdderShellLibDirectory)) {
        $script:PathAdderShellI18nPath = Join-Path $script:PathAdderShellLibDirectory 'i18n.ps1'
        if (Test-Path -LiteralPath $script:PathAdderShellI18nPath -PathType Leaf) {
            . $script:PathAdderShellI18nPath
        }
    }

    if (Get-Command -Name 'Initialize-PathAdderI18n' -ErrorAction SilentlyContinue) {
        Initialize-PathAdderI18n | Out-Null
    }
}

$script:PathAdderShellNativeReady = $false

<#
.SYNOPSIS
    Initializes the P/Invoke native methods (SHChangeNotify) used to tell the Shell
    that its association cache has changed.
.DESCRIPTION
    A compilation failure (e.g. no C# compiler available in a constrained host)
    never throws: it only sets $script:PathAdderShellNativeReady to $false, and the
    caller automatically degrades to "skip the refresh and tell the user to restart
    Explorer manually" - installation must NEVER fail because of a refresh failure.
#>
function Initialize-PathAdderShellNativeMethods {
    if ($script:PathAdderShellNativeReady) {
        return
    }
    $script:PathAdderShellNativeReady = $false

    if ('PathAdder.ShellNativeMethods' -as [type]) {
        $script:PathAdderShellNativeReady = $true
        return
    }

    $source = @'
using System;
using System.Runtime.InteropServices;

namespace PathAdder
{
    public static class ShellNativeMethods
    {
        // SHCNE_ASSOCCHANGED: notifies that all associations
        // (file extensions / ProgIDs / verbs) have changed.
        // Explorer drops its cached IContextMenu and re-reads the registry the
        // next time a context menu is opened.
        public const int SHCNE_ASSOCCHANGED = unchecked((int)0x08000000);

        // SHCNF_IDLIST: passing NULL for dwItem1/dwItem2 means
        // "a global association change".
        public const uint SHCNF_IDLIST = 0x0000;

        // SHCNE_UPDATEITEM: update of a single existing item (SHCNF_PATHW semantics).
        public const int SHCNE_UPDATEITEM = unchecked((int)0x00002000);
        public const uint SHCNF_PATHW = 0x0005;

        [DllImport("shell32.dll", SetLastError = false, CharSet = CharSet.Auto)]
        public static extern void SHChangeNotify(
            int wEventId,
            uint uFlags,
            IntPtr dwItem1,
            IntPtr dwItem2);
    }
}
'@

    try {
        Add-Type -TypeDefinition $source -ErrorAction Stop
        $script:PathAdderShellNativeReady = $true
    } catch {
        $script:PathAdderShellNativeReady = $false
    }
}

# -----------------------------------------------------------------------------
# 1. Menu definitions and registration locations
# -----------------------------------------------------------------------------

<#
.SYNOPSIS
    Returns the full path of powershell.exe. Self-contained version owned by this
    module so that it does not depend on the load order of Common.ps1.
#>
function Get-PathAdderPowerShellPath {
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
    Returns the definitions of the 4 commands. Installation, uninstallation and
    verification all share this single definition so the three never drift apart.
.DESCRIPTION
    Key is the namespaced verb name used by SubCommands (e.g. PathAdder.AddUser)
    and is also the subkey name under `…\PathAdder\shell\`.

    Localization note: the Label values are resolved through T 'Shell.Verb.*' when
    this function is called, i.e. in the language active at registration time.
    Windows stores the resulting literal in the registry, so already registered
    entries keep their old text. Switching the language requires re-running the
    installer / re-registering the menu to refresh the entries. The registration
    logic itself deliberately stays unchanged.
#>
function Get-PathAdderShellVerbDefinitions {
    $definitions = @(
        [PSCustomObject] @{
            Key       = 'PathAdder.AddUser'
            Label     = (T 'Shell.Verb.AddUser')
            Arguments = '-Action Add -Scope User -Target "%V"'
        },
        [PSCustomObject] @{
            Key       = 'PathAdder.AddSystem'
            Label     = (T 'Shell.Verb.AddSystem')
            Arguments = '-Action Add -Scope System -Target "%V"'
        },
        [PSCustomObject] @{
            Key       = 'PathAdder.Remove'
            Label     = (T 'Shell.Verb.Remove')
            Arguments = '-Action Remove -Scope All -Target "%V"'
        },
        [PSCustomObject] @{
            Key       = 'PathAdder.Manager'
            Label     = (T 'Shell.Verb.OpenManager')
            Arguments = '-Action OpenManager'
        }
    )

    return $definitions
}

<#
.SYNOPSIS
    Returns the verb names of the 4 commands (used by SubCommands and by the
    uninstall traversal).
#>
function Get-PathAdderShellVerbKeys {
    $keys = @()
    foreach ($definition in (Get-PathAdderShellVerbDefinitions)) {
        $keys += $definition.Key
    }
    return $keys
}

<#
.SYNOPSIS
    Returns the flat verb names that [historical versions] used.
.DESCRIPTION
    Early versions registered the 4 menu entries directly as flat verbs
    (PathAdderAddUser and friends) under exefile\shell and
    SystemFileAssociations\.exe\shell. Uninstall must remove them as well,
    otherwise upgrading users keep orphan menu entries.
#>
function Get-PathAdderShellLegacyVerbKeys {
    return @('PathAdderAddUser', 'PathAdderAddSystem', 'PathAdderRemove', 'PathAdderManager')
}

<#
.SYNOPSIS
    Returns the name of the cascading menu parent entry (also the subkey name under
    `*\shell`).
#>
function Get-PathAdderShellParentName {
    return 'PathAdder'
}

<#
.SYNOPSIS
    Returns the display text of the cascading menu parent entry.
.DESCRIPTION
    Extracted into its own function so that install.ps1 and
    verify-registration.ps1 share exactly one string, preventing the verification
    script from reporting a false mismatch caused by two divergent literals.

    Localization note: the label is resolved through T 'Shell.Parent.Label' at
    registration time and only then written into the registry values (Default) and
    MUIVerb. After the user switches language, the shell context menu keeps the old
    text until install.ps1 runs again (or the menu is re-registered). This is how
    registry verbs work and is intentionally not worked around here.
#>
function Get-PathAdderShellMenuParentLabel {
    return (T 'Shell.Parent.Label')
}

<#
.SYNOPSIS
    Returns the registration location of the current version (relative subkey path
    under HKCU).
#>
function Get-PathAdderShellRegistrationLocation {
    return ('Software\Classes\*\shell\' + (Get-PathAdderShellParentName))
}

<#
.SYNOPSIS
    Returns the list of locations to write during installation (only one in the
    current version).
#>
function Get-PathAdderShellRegistrationTargets {
    $targets = @(
        [PSCustomObject] @{
            Role        = 'Current'
            SubKey      = (Get-PathAdderShellRegistrationLocation)
            Description = (T 'Shell.Location.AllFiles')
        }
    )

    return $targets
}

<#
.SYNOPSIS
    Returns **all** locations to traverse during uninstall/cleanup (current
    location + every historical one).
.DESCRIPTION
    Each item contains:
      SubKey   - relative subkey path under HKCU
      Mode     - 'Subtree': the whole subtree belongs to this tool and may be
                 deleted entirely;
                 'NamedVerbs': only the same-named subkeys listed in Verbs are deleted
      Verbs    - verb names to delete when Mode='NamedVerbs'
      Description / IsLegacy

    Why historical locations are included: a machine may still carry an older
    version whose registration lives under exefile\shell and
    SystemFileAssociations\.exe\shell. Cleaning only the current location leaves
    orphan menu entries behind.
#>
function Get-PathAdderShellCleanupLocations {
    $locations = @(
        [PSCustomObject] @{
            SubKey      = (Get-PathAdderShellRegistrationLocation)
            Mode        = 'Subtree'
            Verbs       = @()
            IsLegacy    = $false
            Description = (T 'Shell.Cleanup.CurrentSubtree')
        },
        [PSCustomObject] @{
            SubKey      = 'Software\Classes\exefile\shell'
            Mode        = 'NamedVerbs'
            Verbs       = (Get-PathAdderShellLegacyVerbKeys)
            IsLegacy    = $true
            Description = (T 'Shell.Cleanup.LegacyFlatVerbs')
        },
        [PSCustomObject] @{
            SubKey      = 'Software\Classes\SystemFileAssociations\.exe\shell'
            Mode        = 'NamedVerbs'
            Verbs       = (Get-PathAdderShellLegacyVerbKeys)
            IsLegacy    = $true
            Description = (T 'Shell.Cleanup.LegacyExeFallback')
        }
    )

    return $locations
}

<#
.SYNOPSIS
    Builds the full command line of a given subcommand.
.DESCRIPTION
    Why %V and not %1:
      - %V always carries the "long file name" on Windows Vista and later, which is
        the most robust form for paths containing Chinese or spaces;
      - %1 is turned into an 8.3 short name in some legacy scenarios, which can lose
        Chinese directory names;
      - the scripts additionally fall back to GetLongPathName internally - belt and
        braces.
#>
function Get-PathAdderShellCommandLine {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PowerShellPath,

        [Parameter(Mandatory = $true)]
        [string]$EnginePath,

        [Parameter(Mandatory = $true)]
        [string]$Arguments
    )

    return '"' + $PowerShellPath + '"' +
        ' -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File' +
        ' "' + $EnginePath + '" ' + $Arguments
}

# -----------------------------------------------------------------------------
# 2. Installation
# -----------------------------------------------------------------------------

<#
.SYNOPSIS
    Writes the menu into HKCU (idempotent).
.DESCRIPTION
    Idempotent: calling it again only overwrites the same-named values and never
    errors out; CreateSubKey means "open or create" for an existing key.
    On failure it throws and the caller shows a uniform dialog.

    [About the default verb] This function NEVER writes the (Default) value of any
    parent key - neither for `*\shell` nor for `exefile\shell`. Those values decide
    what happens on double-click, and pointing them at our menu item would make
    double-clicking a file pop up the PATH dialog instead of opening the file. That
    would be catastrophic damage and must never happen.

    Localization note: the label written here (both the parent entry and the
    command labels) comes from the language that is active *while this function
    runs*. Windows keeps plain literals in the registry, so an existing menu is not
    rewritten when the user switches language - they must re-run install.ps1 (or
    otherwise re-register the menu) to refresh the text. The registration logic is
    intentionally left untouched.

.OUTPUTS
    An object with Success / ParentSubKey / SubCommands / CommandLines.
#>
function Install-PathAdderShellMenu {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$EnginePath,

        [Parameter(Mandatory = $false)]
        [string]$PowerShellPath = '',

        [Parameter(Mandatory = $false)]
        [string]$ParentLabel = ''
    )

    # An empty label means "use the localized default resolved right now".
    if ([string]::IsNullOrWhiteSpace($ParentLabel)) {
        $ParentLabel = Get-PathAdderShellMenuParentLabel
    }

    $result = New-Object PSObject -Property @{
        Success         = $false
        EnginePath      = $EnginePath
        PowerShellPath  = $PowerShellPath
        ParentSubKey    = ''
        SubCommands     = ''
        Labels          = @()
        CommandLines    = @()
    }

    if ([string]::IsNullOrWhiteSpace($PowerShellPath)) {
        $PowerShellPath = Get-PathAdderPowerShellPath
        $result.PowerShellPath = $PowerShellPath
    }

    $iconValue = $PowerShellPath + ',0'
    $definitions = Get-PathAdderShellVerbDefinitions
    $parentSubKey = Get-PathAdderShellRegistrationLocation
    $result.ParentSubKey = $parentSubKey

    $verbKeys = @()
    foreach ($definition in $definitions) { $verbKeys += $definition.Key }
    $subCommandsValue = [string]::Join(';', $verbKeys)
    $result.SubCommands = $subCommandsValue

    $labels = @()
    $commandLines = @()

    # ---- Parent entry ----
    $parentKey = $null
    try {
        $parentKey = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($parentSubKey)
    } catch {
        throw (T 'Shell.Error.CreateKeyFailed' @($parentSubKey, $_.Exception.Message))
    }

    if ($null -eq $parentKey) {
        throw (T 'Shell.Error.CreateKeyFailedNoDetail' @($parentSubKey))
    }

    try {
        $parentKey.SetValue('', $ParentLabel, [Microsoft.Win32.RegistryValueKind]::String)
        $parentKey.SetValue('MUIVerb', $ParentLabel, [Microsoft.Win32.RegistryValueKind]::String)
        $parentKey.SetValue('Icon', $iconValue, [Microsoft.Win32.RegistryValueKind]::ExpandString)
        # Never let the directory of the right-clicked file become the working
        # directory of the child process (the scripts work purely with absolute paths).
        $parentKey.SetValue('NoWorkingDirectory', '', [Microsoft.Win32.RegistryValueKind]::String)

        # Old versions used the native Windows SubCommands static cascade
        # (expand on hover). Measurements showed that on Windows 11 the parent is
        # visible but does NOT expand on hover, and since the parent may not carry a
        # command, clicking does nothing either - the feature was unusable.
        # The design is now "click the parent -> MenuPicker pops the action menu at
        # the cursor". Two kinds of leftovers from the previous version are cleaned
        # up here:
        #     1) the SubCommands value
        #     2) the subcommand key tree under …\PathAdder\shell\
        try { $parentKey.DeleteValue('SubCommands', $false) } catch { }

        try {
            $legacyShell = $parentKey.OpenSubKey('shell', $false)
            if ($null -ne $legacyShell) {
                $legacyShell.Close()
                $parentKey.DeleteSubKeyTree('shell', $false)
            }
        } catch {
            # Nothing there or it cannot be deleted - ignore.
        }
    } finally {
        $parentKey.Close()
    }

    # ---- Parent command: pops the action menu at the cursor after a click ----
    $pickerPath = Join-Path (Split-Path -Parent $EnginePath) 'MenuPicker.ps1'
    if (-not (Test-Path -LiteralPath $pickerPath -PathType Leaf)) {
        throw (T 'Shell.Error.PickerMissing' @($pickerPath))
    }

    $pickerCommandKey = $null
    try {
        $pickerCommandKey = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($parentSubKey + '\command')
    } catch {
        throw (T 'Shell.Error.CreateKeyFailed' @($parentSubKey + '\command', $_.Exception.Message))
    }

    if ($null -eq $pickerCommandKey) {
        throw (T 'Shell.Error.CreateKeyFailedNoDetail' @($parentSubKey + '\command'))
    }

    $pickerCommandLine = ''
    try {
        $pickerCommandLine = Get-PathAdderShellCommandLine `
            -PowerShellPath $PowerShellPath `
            -EnginePath $pickerPath `
            -Arguments '-Target "%V"'
        $pickerCommandKey.SetValue('', $pickerCommandLine, [Microsoft.Win32.RegistryValueKind]::String)
    } finally {
        $pickerCommandKey.Close()
    }

    $labels += $ParentLabel
    $commandLines += $pickerCommandLine

    $result.Success = $true
    $result.Labels = $labels
    $result.CommandLines = $commandLines
    return $result
}

# -----------------------------------------------------------------------------
# 3. Uninstallation
# -----------------------------------------------------------------------------

<#
.SYNOPSIS
    Deletes the given key, then walks upwards removing empty parents (cleans the
    shells created during installation).
.DESCRIPTION
    Strictly "only empty keys are deleted": the moment any subkey or value is found
    it returns immediately and leaves things untouched. It therefore can never delete
    content written by another program - even if that program happens to have
    registered its own menu entry under the same parent key, this function simply
    gives up because the key is "not empty".
#>
function Remove-PathAdderEmptyRegistryKey {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SubKeyPath
    )

    $removed = @()
    $current = $SubKeyPath

    while (-not [string]::IsNullOrWhiteSpace($current)) {
        $readKey = $null
        try {
            $readKey = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($current, $false)
        } catch {
            $readKey = $null
        }

        if ($null -eq $readKey) {
            break
        }

        $isEmpty = $false
        try {
            $isEmpty = (($readKey.ValueCount -eq 0) -and ($readKey.SubKeyCount -eq 0))
        } finally {
            $readKey.Close()
        }

        if (-not $isEmpty) {
            break
        }

        $separatorIndex = $current.LastIndexOf('\')
        if ($separatorIndex -lt 0) {
            break
        }
        $parentPath = $current.Substring(0, $separatorIndex)
        $leafName = $current.Substring($separatorIndex + 1)

        $parentKey = $null
        try {
            $parentKey = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($parentPath, $true)
        } catch {
            $parentKey = $null
        }

        if ($null -eq $parentKey) {
            break
        }

        try {
            $parentKey.DeleteSubKeyTree($leafName, $false)
            $removed += $current
        } catch {
            # Has subkeys / is protected: give up on this level only.
        } finally {
            $parentKey.Close()
        }

        $current = $parentPath
    }

    return $removed
}

<#
.SYNOPSIS
    Precisely removes every menu entry this tool registered in all locations
    (current + historical); idempotent.
.DESCRIPTION
    Safety boundaries (hard constraints):
      - a whole subtree is only deleted for `*\shell\PathAdder` (that name belongs
        exclusively to this tool);
      - historical locations only lose the 4 flat same-named subkeys listed in
        LegacyVerbKeys;
      - HKLM is never touched, and no sibling key that "does not carry our name" is
        ever deleted (e.g. third-party menus such as meituxiuxiu / git / VLC under
        `*\shell`);
      - **the (Default) value of any parent key is never written or cleared** (the
        default verb is the double-click behaviour and must not be touched);
      - a missing key is skipped silently (repeated uninstall never errors out).

    Note: removing keys is language independent - nothing written into the registry
    is read back here, so uninstall works the same under every language.
.OUTPUTS
    An object with Success / RemovedCount / Failed / RemovedItems /
    PrunedEmptyKeys / LocationsScanned.
#>
function Uninstall-PathAdderShellMenu {
    [CmdletBinding()]
    param()

    $result = New-Object PSObject -Property @{
        Success          = $false
        RemovedCount     = 0
        Failed           = @()
        RemovedItems     = @()
        PrunedEmptyKeys  = @()
        LocationsScanned = @()
    }

    $locations = Get-PathAdderShellCleanupLocations

    $removedCount = 0
    $failed = @()
    $removedItems = @()
    $pruned = @()
    $scanned = @()

    foreach ($location in $locations) {
        $scanned += $location.SubKey

        if ($location.Mode -eq 'Subtree') {
            # The whole subtree belongs to this tool - delete it directly.
            $parentKey = $null
            try {
                $parentKey = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($location.SubKey, $false)
            } catch {
                $parentKey = $null
            }

            if ($null -eq $parentKey) {
                continue
            }
            $parentKey.Close()

            $separatorIndex = $location.SubKey.LastIndexOf('\')
            if ($separatorIndex -lt 0) {
                continue
            }
            $containerPath = $location.SubKey.Substring(0, $separatorIndex)
            $leafName = $location.SubKey.Substring($separatorIndex + 1)

            $containerKey = $null
            try {
                $containerKey = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($containerPath, $true)
            } catch {
                $containerKey = $null
            }

            if ($null -eq $containerKey) {
                continue
            }

            try {
                $containerKey.DeleteSubKeyTree($leafName, $false)
                $removedCount = $removedCount + 1
                $removedItems += (T 'Shell.Uninstall.RemovedSubtree' @('HKCU\' + $location.SubKey))
            } catch {
                $failed += ($location.SubKey)
            } finally {
                $containerKey.Close()
            }

            continue
        }

        # Mode = 'NamedVerbs': only same-named subkeys are deleted.
        $baseKey = $null
        try {
            $baseKey = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($location.SubKey, $true)
        } catch {
            $baseKey = $null
        }

        if ($null -eq $baseKey) {
            continue
        }

        try {
            foreach ($verbKey in $location.Verbs) {
                $existing = $null
                try {
                    $existing = $baseKey.OpenSubKey($verbKey, $false)
                } catch {
                    $existing = $null
                }

                if ($null -eq $existing) {
                    continue
                }
                $existing.Close()

                try {
                    $baseKey.DeleteSubKeyTree($verbKey, $false)
                    $removedCount = $removedCount + 1
                    $removedItems += ('HKCU\' + $location.SubKey + '\' + $verbKey)
                } catch {
                    $failed += ($location.SubKey + '\' + $verbKey)
                }
            }
        } finally {
            $baseKey.Close()
        }

        # Reclaim empty parent keys created during installation, bottom-up (only
        # empty keys are removed).
        $pruned += Remove-PathAdderEmptyRegistryKey -SubKeyPath $location.SubKey
    }

    $result.Success = ($failed.Count -eq 0)
    $result.RemovedCount = $removedCount
    $result.Failed = $failed
    $result.RemovedItems = $removedItems
    $result.PrunedEmptyKeys = $pruned
    $result.LocationsScanned = $scanned
    return $result
}

# -----------------------------------------------------------------------------
# 4. Shell cache refresh and Explorer restart
# -----------------------------------------------------------------------------

<#
.SYNOPSIS
    Notifies Explorer that "file associations / verbs have changed" so that it drops
    its cached context menu.
.DESCRIPTION
    First choice is SHChangeNotify(SHCNE_ASSOCCHANGED, SHCNF_IDLIST, NULL, NULL),
    followed by an extra SHCNE_UPDATEITEM to nudge the refresh (Windows versions
    differ slightly in how they react to the former).

    Measured result: on Windows 11 this notification is NOT reliable; very often the
    explorer process must be restarted or the user must sign out and back in for it
    to take effect. Callers should therefore still guide the user through a restart
    after receiving this result (see Restart-PathAdderExplorer and install.ps1).

    Degraded strategy: when Add-Type compilation fails or the call throws, it returns
    Refreshed = $false plus manual instructions and NEVER throws to abort the
    installation/uninstallation.
#>
function Update-PathAdderShellAssociationCache {
    [CmdletBinding()]
    param()

    $result = New-Object PSObject -Property @{
        Refreshed = $false
        Message   = ''
    }

    Initialize-PathAdderShellNativeMethods
    if (-not $script:PathAdderShellNativeReady) {
        $result.Message = (T 'Shell.Refresh.InteropFailed')
        return $result
    }

    try {
        [void][PathAdder.ShellNativeMethods]::SHChangeNotify(
            [int][PathAdder.ShellNativeMethods]::SHCNE_ASSOCCHANGED,
            [uint32][PathAdder.ShellNativeMethods]::SHCNF_IDLIST,
            [IntPtr]::Zero,
            [IntPtr]::Zero)

        [void][PathAdder.ShellNativeMethods]::SHChangeNotify(
            [int][PathAdder.ShellNativeMethods]::SHCNE_UPDATEITEM,
            [uint32][PathAdder.ShellNativeMethods]::SHCNF_PATHW,
            [IntPtr]::Zero,
            [IntPtr]::Zero)

        $result.Refreshed = $true
        $result.Message = (T 'Shell.Refresh.Notified')
    } catch {
        $result.Refreshed = $false
        $result.Message = (T 'Shell.Refresh.Failed' @($_.Exception.Message))
    }

    return $result
}

<#
.SYNOPSIS
    Shows a Yes/No confirmation box; degrades safely to "No" when no graphical
    session is available.
.DESCRIPTION
    The default button is "No" (Button2) so that simply pressing Enter can never
    trigger a destructive operation by accident.
.OUTPUTS
    $true = the user chose "Yes"; $false = they chose "No" or there is no GUI.
#>
function Show-PathAdderConfirmBox {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [string]$Title = ''
    )

    # An empty title means "fall back to the localized application name".
    if ([string]::IsNullOrWhiteSpace($Title)) {
        $Title = T 'App.Name'
    }

    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
    } catch {
        Write-Host (T 'Shell.Confirm.PrefixedMessage' @($Message))
        Write-Host (T 'Shell.Confirm.NoGui')
        return $false
    }

    try {
        $answer = [System.Windows.Forms.MessageBox]::Show(
            $Message,
            $Title,
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Question,
            [System.Windows.Forms.MessageBoxDefaultButton]::Button2)

        if ($answer -eq [System.Windows.Forms.DialogResult]::Yes) {
            return $true
        }
        return $false
    } catch {
        Write-Host (T 'Shell.Confirm.PrefixedMessage' @($Message))
        Write-Host (T 'Shell.Confirm.BoxFailed')
        return $false
    }
}

<#
.SYNOPSIS
    Restarts the Explorer process (this closes every open folder window, so the user
    must be asked first).
.DESCRIPTION
    Flow: Stop-Process -Name explorer -Force -> wait 2 seconds ->
    Start-Process explorer.exe.
    Only exceptions are caught, nothing is rethrown - a failed restart must not
    affect the installation result; instead the user is told to restart manually.
.OUTPUTS
    An object with Success / Message / ProcessCount.
#>
function Restart-PathAdderExplorer {
    [CmdletBinding()]
    param()

    $result = New-Object PSObject -Property @{
        Success      = $false
        Message      = ''
        ProcessCount = 0
    }

    try {
        $processes = @(Get-Process -Name 'explorer' -ErrorAction SilentlyContinue)
        $result.ProcessCount = $processes.Count

        Stop-Process -Name 'explorer' -Force -ErrorAction Stop
        Start-Sleep -Seconds 2
        Start-Process -FilePath 'explorer.exe' -ErrorAction Stop

        $result.Success = $true
        $result.Message = (T 'Shell.Restart.Success' @($processes.Count))
    } catch {
        $result.Success = $false
        $result.Message = (T 'Shell.Restart.Failed' @($_.Exception.Message, "`r`n"))
    }

    return $result
}
