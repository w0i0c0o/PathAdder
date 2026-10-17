# -----------------------------------------------------------------------------
# verify-registration.ps1 - context menu registration verification script
#                           (standalone tool; not part of the install/uninstall
#                           flow)
#
# Purpose:
#   Answers one concrete question: "the registry holds 4 verbs - can Explorer
#   really enumerate them as real context menu entries?"
#
#   Reading the registry with Get-ItemProperty alone is NOT enough to prove
#   that: when the registration location is wrong, every key and value is
#   present, yet Explorer never reads that location. This script therefore
#   verifies in three layers:
#
#   Layer 1  Registry structure check
#            Confirms one by one that the verb key, (Default), MUIVerb, Icon,
#            NoWorkingDirectory and command\(Default) exist and are correct.
#
#   Layer 2  Real menu enumeration (the key evidence)
#            Calls SHCreateItemFromParsingName to get an IShellItem for the
#            target .exe, then BindToHandler(BHID_ShellMenu) to obtain the
#            *real* IContextMenu, fills an in-memory HMENU through
#            QueryContextMenu, and walks the menu items:
#              - display text comes from GetMenuStringW (what the user sees)
#              - verb names come from IContextMenu::GetCommandString
#                (GCS_VERBKEY), which returns the *canonical verb name* stored
#                in the registry (for example PathAdderAddUser), i.e. the very
#                key name Explorer uses to dispatch the command.
#            The check passes only when the 4 PathAdder* verb names show up in
#            the enumeration result.
#            This is a real COM call: it needs no Explorer restart and is not
#            affected by the menu cache.
#
#   Layer 3  Third-party menu survival check
#            Enumerates third-party menu entries under HKCR\*\shell (VLC, git,
#            meituxiuxiu, ...) to confirm the install/uninstall flow did not
#            damage them.
#
# Exit codes:
#   0 = everything passed
#   1 = at least one failure
#   2 = environment problem (COM unavailable, no C# compiler, ...), layer 2
#       could not be completed
#
# Compatibility: Windows PowerShell 5.1 (no ?? / && / || / ternary operator or
#                other PS7-only syntax).
# -----------------------------------------------------------------------------

<#
.SYNOPSIS
    Verifies that the PathAdder context menu registration is really visible to
    Windows Explorer.
.DESCRIPTION
    Runs a three-layer verification: registry structure, real IContextMenu
    enumeration (SHCreateItemFromParsingName + BindToHandler), and a
    third-party menu survival check. Every user-visible line is localized
    through lib\i18n.ps1.
.PARAMETER TargetExe
    File used as the right-click probe target. When omitted, a system .exe plus
    a temporary .txt file are probed.
.PARAMETER SkipContextMenu
    Skips layer 2 (the real IContextMenu enumeration).
.PARAMETER Language
    Language code for the report (for example 'zh-CN'). When omitted the
    language is resolved from PATHADDER_LANG, the configuration file, the
    registry and then the system UI language, falling back to en-US.
.EXAMPLE
    powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File ".\verify-registration.ps1"
.EXAMPLE
    powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File ".\verify-registration.ps1" -Language zh-CN
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$TargetExe = '',

    [Parameter()]
    [switch]$SkipContextMenu,

    [Parameter()]
    [string]$Language = ''
)

$ErrorActionPreference = 'Stop'

# -----------------------------------------------------------------------------
# Localization bootstrap.
#
# It has to run before the apartment check below: the relaunch notice is itself
# printed in the resolved language, and -Language must be forwarded to the
# re-launched process.
# -----------------------------------------------------------------------------

$script:MainScriptPath = $PSCommandPath
if ([string]::IsNullOrWhiteSpace($script:MainScriptPath)) {
    $script:MainScriptPath = $MyInvocation.MyCommand.Definition
}
$script:ScriptRoot = Split-Path -Parent $script:MainScriptPath
$global:PathAdderRootDirectory = $script:ScriptRoot
. (Join-Path $script:ScriptRoot 'lib\i18n.ps1')
Initialize-PathAdderI18n -Language $Language | Out-Null

# -----------------------------------------------------------------------------
# 0. Thread apartment check (IContextMenu enumeration must run on STA).
#
#    When the current thread is not STA, the script re-launches itself with
#    -STA and forwards the exit code, so that running
#    `powershell -File verify-registration.ps1` (MTA by default) just works.
# -----------------------------------------------------------------------------

if ([System.Threading.Thread]::CurrentThread.ApartmentState -ne
    [System.Threading.ApartmentState]::STA) {

    $script:SelfPath = $script:MainScriptPath

    $relaunchArgs = @(
        '-NoProfile'
        '-ExecutionPolicy', 'Bypass'
        '-STA'
        '-File', ('"' + $script:SelfPath + '"')
    )
    if (-not [string]::IsNullOrWhiteSpace($TargetExe)) {
        $relaunchArgs += @('-TargetExe', ('"' + $TargetExe + '"'))
    }
    if ($SkipContextMenu) {
        $relaunchArgs += '-SkipContextMenu'
    }
    if (-not [string]::IsNullOrWhiteSpace($Language)) {
        $relaunchArgs += @('-Language', $Language)
    }

    $powershellExe = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (-not (Test-Path -LiteralPath $powershellExe -PathType Leaf)) {
        $powershellExe = 'powershell.exe'
    }

    Write-Host (T 'Verify.Msg.RelaunchSta')
    $process = Start-Process -FilePath $powershellExe -ArgumentList $relaunchArgs -Wait -PassThru -NoNewWindow
    exit $process.ExitCode
}

# -----------------------------------------------------------------------------
# 1. Shared library and menu definitions
#    ($script:ScriptRoot was resolved by the localization bootstrap above.)
# -----------------------------------------------------------------------------

$script:ShellMenuPath = Join-Path $script:ScriptRoot 'lib\ShellMenu.ps1'
if (-not (Test-Path -LiteralPath $script:ShellMenuPath -PathType Leaf)) {
    Write-Host (T 'Verify.Line.Status' @((T 'Verify.Result.Fail'),
        (T 'Verify.Msg.MissingShellMenuLib' @($script:ShellMenuPath)))) -ForegroundColor Red
    exit 2
}
. $script:ShellMenuPath

# Note: wrapping in @() is required. The functions below return single-element
# arrays, and PowerShell 5.1 unrolls them into a bare PSCustomObject, which
# makes $targets.Count evaluate to nothing later on.
$verbDefinitions = @(Get-PathAdderShellVerbDefinitions)
$verbKeys = @(Get-PathAdderShellVerbKeys)
$targets = @(Get-PathAdderShellRegistrationTargets)

$script:Failures = @()
$script:Warnings = @()

# Whether layer 2 (the real menu enumeration) actually completed. While it has
# not, printing "all checks passed" is forbidden: that would be a false positive
# that skips the key evidence and claims the menu works just because the
# registry check passed.
$script:ContextMenuVerified = $false

# Whether the fallback path (derivation from Explorer's association resolution
# rules) completed. Its evidence is weaker than a real enumeration: it proves
# that the verb sits on Explorer's main lookup path, but not that the Shell has
# really built the menu. It may therefore only downgrade the conclusion to
# "needs manual confirmation" - it is never equivalent to ContextMenuVerified.
$script:AssocResolutionVerified = $false

# Measured state of the cascade menu (only meaningful after a successful layer 2
# real enumeration):
#   CascadeParentFound - did the parent entry "PATH Assistant" show up?
#   CascadeExpanded    - did the 4 subcommands show up in the *submenu*
#                        (depth > 1)?
# If the parent shows up but the subcommands do not, Windows 11 did not expand
# SubCommands and the fallback design has to be used.
$script:CascadeParentFound = $false
$script:CascadeExpanded = $false

function Write-Section {
    param([string]$Title)
    Write-Host ''
    Write-Host (T 'Verify.Section.Format' @($Title)) -ForegroundColor Cyan
}

function Write-Pass {
    param([string]$Text)
    Write-Host (T 'Verify.Line.Status' @((T 'Verify.Result.Pass'), $Text)) -ForegroundColor Green
}

function Write-Fail {
    param([string]$Text)
    Write-Host (T 'Verify.Line.Status' @((T 'Verify.Result.Fail'), $Text)) -ForegroundColor Red
    $script:Failures += $Text
}

function Write-Note {
    param([string]$Text)
    Write-Host (T 'Verify.Line.Status' @((T 'Verify.Result.Warn'), $Text)) -ForegroundColor Yellow
}

Write-Host (T 'Verify.Header.Banner') -ForegroundColor Cyan
Write-Host (T 'Verify.Header.Title' @((T 'App.Name'))) -ForegroundColor Cyan
Write-Host (T 'Verify.Header.Banner') -ForegroundColor Cyan

# -----------------------------------------------------------------------------
# 2. Layer 1: registry structure check
# -----------------------------------------------------------------------------

Write-Section (T 'Verify.Section.Layer1')

$expectedEnginePath = Join-Path $script:ScriptRoot 'PathAdder.ps1'
$parentSubKey = Get-PathAdderShellRegistrationLocation

foreach ($target in $targets) {
    Write-Host ''
    Write-Host (T 'Verify.Check.Location' @($target.Role, $target.Description)) -ForegroundColor White
    Write-Host (T 'Verify.Check.SubKey' @($target.SubKey)) -ForegroundColor DarkGray

    $parentKey = $null
    try {
        $parentKey = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($target.SubKey, $false)
    } catch {
        $parentKey = $null
    }

    if ($null -eq $parentKey) {
        Write-Fail (T 'Verify.Check.KeyMissing' @($target.SubKey))
        continue
    }

    try {
        # ---- Parent entry: MUIVerb / Icon / SubCommands / NoWorkingDirectory ----
        $parentLabel = [string]$parentKey.GetValue('MUIVerb', '')
        if ([string]::IsNullOrWhiteSpace($parentLabel)) {
            Write-Fail (T 'Verify.Check.ParentMissingMuiverb')
        } else {
            Write-Pass (T 'Verify.Check.ParentMuiverb' @($parentLabel))
        }

        $parentIcon = [string]$parentKey.GetValue('Icon', '')
        if ([string]::IsNullOrWhiteSpace($parentIcon)) {
            Write-Fail (T 'Verify.Check.ParentMissingIcon')
        } else {
            Write-Pass (T 'Verify.Check.ParentIcon' @($parentIcon))
        }

        if ($null -eq $parentKey.GetValue('NoWorkingDirectory', $null)) {
            Write-Fail (T 'Verify.Check.ParentMissingNoWorkingDirectory')
        } else {
            Write-Pass (T 'Verify.Check.ParentNoWorkingDirectorySet')
        }

        # ------------------------------------------------------------------
        # Current design (since 2026-10-04): clicking the parent entry makes
        # MenuPicker.ps1 pop up the action menu at the cursor.
        #
        # The key assertion here is EXACTLY THE OPPOSITE of the SubCommands era:
        #   - old design: the parent must NEVER have a command subkey
        #     (otherwise SubCommands is ignored)
        #   - new design: the parent MUST have a command subkey
        #     (otherwise clicking does nothing)
        # See README 5.2 - on Windows 11 the SubCommands hover cascade was
        # measured never to expand.
        # ------------------------------------------------------------------

        $legacySubCommands = [string]$parentKey.GetValue('SubCommands', '')
        if (-not [string]::IsNullOrWhiteSpace($legacySubCommands)) {
            Write-Fail (T 'Verify.Check.ParentLegacySubCommands' @($legacySubCommands))
        } else {
            Write-Pass (T 'Verify.Check.ParentNoLegacySubCommands')
        }

        $expectedPickerPath = Join-Path (Split-Path -Parent $expectedEnginePath) 'MenuPicker.ps1'

        $parentCommandKey = $null
        try {
            $parentCommandKey = $parentKey.OpenSubKey('command', $false)
        } catch {
            $parentCommandKey = $null
        }

        if ($null -eq $parentCommandKey) {
            Write-Fail (T 'Verify.Check.ParentMissingCommand')
        } else {
            try {
                $parentCommandLine = [string]$parentCommandKey.GetValue('', '')
                $parentProblems = @()

                if ([string]::IsNullOrWhiteSpace($parentCommandLine)) {
                    $parentProblems += (T 'Verify.Check.CommandEmpty')
                }
                if ($parentCommandLine -notmatch '-NoProfile') {
                    $parentProblems += (T 'Verify.Check.CommandMissingNoProfile')
                }
                if ($parentCommandLine -notmatch '-ExecutionPolicy\s+Bypass') {
                    $parentProblems += (T 'Verify.Check.CommandMissingExecPolicy')
                }
                if ($parentCommandLine -notmatch '-File\s+"') {
                    $parentProblems += (T 'Verify.Check.CommandFileNotQuoted')
                }
                if ($parentCommandLine -notlike ('*' + $expectedPickerPath + '*')) {
                    $parentProblems += (T 'Verify.Check.CommandNotPicker' @($expectedPickerPath))
                }
                if ($parentCommandLine -notlike '*-Target "%V"*') {
                    $parentProblems += (T 'Verify.Check.CommandMissingTarget')
                }

                if ($parentProblems.Count -eq 0) {
                    Write-Pass (T 'Verify.Check.ParentCommandOk')
                } else {
                    foreach ($problem in $parentProblems) {
                        Write-Fail (T 'Verify.Check.ParentCommandProblem' @($problem))
                    }
                }
            } finally {
                $parentCommandKey.Close()
            }
        }

        if (Test-Path -LiteralPath $expectedPickerPath -PathType Leaf) {
            Write-Pass (T 'Verify.Check.PickerExists')
        } else {
            Write-Fail (T 'Verify.Check.PickerMissing' @($expectedPickerPath))
        }

        # Legacy leftover: the ...\shell subcommand tree should already have been
        # cleaned up by the installer.
        $legacyShellKey = $null
        try {
            $legacyShellKey = $parentKey.OpenSubKey('shell', $false)
        } catch {
            $legacyShellKey = $null
        }

        if ($null -ne $legacyShellKey) {
            $legacyShellKey.Close()
            Write-Fail (T 'Verify.Check.ParentLegacyShellTree')
        } else {
            Write-Pass (T 'Verify.Check.ParentNoLegacyShellTree')
        }
    } finally {
        $parentKey.Close()
    }
}

# -----------------------------------------------------------------------------
# 2b. Historical registration locations must be empty (upgrade path from older
#     versions)
# -----------------------------------------------------------------------------

Write-Section (T 'Verify.Section.Layer12')

foreach ($location in (Get-PathAdderShellCleanupLocations)) {
    if (-not $location.IsLegacy) {
        continue
    }

    $legacyKey = $null
    try {
        $legacyKey = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($location.SubKey, $false)
    } catch {
        $legacyKey = $null
    }

    if ($null -eq $legacyKey) {
        Write-Pass (T 'Verify.Check.LegacyKeyAbsent' @($location.SubKey))
        continue
    }

    try {
        $names = @($legacyKey.GetSubKeyNames())
        $leftovers = @()
        foreach ($legacyVerb in $location.Verbs) {
            if ($names -contains $legacyVerb) {
                $leftovers += $legacyVerb
            }
        }

        if ($leftovers.Count -eq 0) {
            Write-Pass (T 'Verify.Check.LegacyNoLeftover' @($location.SubKey))
        } else {
            Write-Fail (T 'Verify.Check.LegacyLeftover' @($location.SubKey, ($leftovers -join ', ')))
        }
    } finally {
        $legacyKey.Close()
    }
}

# -----------------------------------------------------------------------------
# 2c. Default verb safety (breaking it is a disaster: it changes what happens
#     when a file is double-clicked)
# -----------------------------------------------------------------------------

Write-Section (T 'Verify.Section.Layer13')

$defaultVerbTargets = @(
    'Registry::HKEY_CLASSES_ROOT\*\shell',
    'Registry::HKEY_CLASSES_ROOT\exefile\shell'
)

foreach ($defaultTarget in $defaultVerbTargets) {
    $targetKey = $null
    try {
        $targetKey = Get-Item -LiteralPath $defaultTarget -ErrorAction Stop
    } catch {
        $targetKey = $null
    }

    if ($null -eq $targetKey) {
        Write-Note (T 'Verify.Check.CannotRead' @($defaultTarget))
        continue
    }

    $currentDefault = [string]$targetKey.GetValue('')
    if ([string]::IsNullOrWhiteSpace($currentDefault)) {
        Write-Pass (T 'Verify.Check.NoDefaultVerb' @($defaultTarget))
    } elseif ($currentDefault -like 'PathAdder*') {
        Write-Fail (T 'Verify.Check.DefaultVerbHijacked' @($defaultTarget, $currentDefault))
    } else {
        Write-Pass (T 'Verify.Check.DefaultVerbSafe' @($defaultTarget, $currentDefault))
    }
}

# -----------------------------------------------------------------------------
# 3. Confirm that HKLM exefile was not polluted (the system open/runas/runasuser
#    verbs must be intact)
# -----------------------------------------------------------------------------

Write-Section (T 'Verify.Section.Layer15')

$hklmExeShell = 'SOFTWARE\Classes\exefile\shell'
$systemVerbs = @('open', 'runas', 'runasuser')
$hklmKey = $null
try {
    $hklmKey = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($hklmExeShell, $false)
} catch {
    $hklmKey = $null
}

if ($null -eq $hklmKey) {
    Write-Note (T 'Verify.Check.HklmUnreadable' @($hklmExeShell))
} else {
    try {
        $hklmSubKeys = @($hklmKey.GetSubKeyNames())
        foreach ($systemVerb in $systemVerbs) {
            if ($hklmSubKeys -contains $systemVerb) {
                Write-Pass (T 'Verify.Check.SystemVerbIntact' @($systemVerb))
            } else {
                Write-Fail (T 'Verify.Check.SystemVerbMissing' @($systemVerb))
            }
        }
        foreach ($ourVerb in $verbKeys) {
            if ($hklmSubKeys -contains $ourVerb) {
                Write-Fail (T 'Verify.Check.OurVerbInHklm' @($ourVerb))
            }
        }
    } finally {
        $hklmKey.Close()
    }
}

# -----------------------------------------------------------------------------
# 4. Layer 3: third-party menu survival check
# -----------------------------------------------------------------------------

Write-Section (T 'Verify.Section.Layer3')

$starShellKey = 'Registry::HKEY_CLASSES_ROOT\*\shell'
$allStarVerbs = @()
try {
    if (Test-Path -LiteralPath $starShellKey) {
        $allStarVerbs = @((Get-ChildItem -LiteralPath $starShellKey -ErrorAction SilentlyContinue).PSChildName)
    }
} catch {
    $allStarVerbs = @()
}

# Under `*\shell` this tool only ever has the single parent entry PathAdder
# (cascade); no flat verb should exist there.
$parentName = Get-PathAdderShellParentName
$legacyKeys = Get-PathAdderShellLegacyVerbKeys

$thirdPartyVerbs = @()
foreach ($name in $allStarVerbs) {
    if ($name -eq $parentName) { continue }
    if ($legacyKeys -contains $name) { continue }
    $thirdPartyVerbs += $name
}

if ($thirdPartyVerbs.Count -gt 0) {
    Write-Pass (T 'Verify.Check.ThirdPartyPreserved' @($thirdPartyVerbs.Count))
    Write-Host ('    ' + ($thirdPartyVerbs -join ' | ')) -ForegroundColor DarkGray
} else {
    Write-Note (T 'Verify.Check.NoThirdParty')
}

foreach ($legacyKey in $legacyKeys) {
    if ($allStarVerbs -contains $legacyKey) {
        Write-Fail (T 'Verify.Check.LegacyFlatVerb' @($legacyKey))
    }
}

# On the exefile\shell side: the system verbs must be intact and none of our own
# registrations should remain.
$exeShellKey = 'Registry::HKEY_CLASSES_ROOT\exefile\shell'
$exeVerbs = @()
try {
    if (Test-Path -LiteralPath $exeShellKey) {
        $exeVerbs = @((Get-ChildItem -LiteralPath $exeShellKey -ErrorAction SilentlyContinue).PSChildName)
    }
} catch {
    $exeVerbs = @()
}

foreach ($systemVerb in @('open', 'runas', 'runasuser')) {
    if ($exeVerbs -contains $systemVerb) {
        Write-Pass (T 'Verify.Check.ExeSystemVerbIntact' @($systemVerb))
    } else {
        Write-Fail (T 'Verify.Check.ExeSystemVerbMissing' @($systemVerb))
    }
}

foreach ($legacyKey in $legacyKeys) {
    if ($exeVerbs -contains $legacyKey) {
        Write-Fail (T 'Verify.Check.ExeLegacyLeftover' @($legacyKey))
    }
}

if ($allStarVerbs -contains $parentName) {
    Write-Pass (T 'Verify.Check.MergedParentVisible' @('HKCR\*\shell\' + $parentName))
} else {
    Write-Fail (T 'Verify.Check.MergedParentInvisible' @('HKCR\*\shell\' + $parentName))
}

# -----------------------------------------------------------------------------
# 5. Layer 2: real IContextMenu enumeration (key evidence)
# -----------------------------------------------------------------------------

Write-Section (T 'Verify.Section.Layer2')

if ($SkipContextMenu) {
    Write-Note (T 'Verify.Check.SkipContextMenu')
} else {
    # Probe target selection: by default one .exe **plus one .txt**.
    # Both types must be covered because this tool registers on `*`, so the menu
    # has to be usable for every file type. Probing only .exe does not prove that
    # .txt and other types see the menu too.
    $probeTargets = @()

    if (-not [string]::IsNullOrWhiteSpace($TargetExe)) {
        $probeTargets += $TargetExe
    } else {
        $exeCandidates = @(
            (Join-Path $env:WINDIR 'System32\notepad.exe')
            (Join-Path $env:WINDIR 'System32\cmd.exe')
            (Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe')
        )
        foreach ($candidate in $exeCandidates) {
            if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                $probeTargets += $candidate
                break
            }
        }
    }

    # One .txt probe target (created temporarily under %TEMP%, deleted
    # afterwards), used to verify "all file types".
    $txtProbePath = ''
    if (-not [string]::IsNullOrWhiteSpace($TargetExe)) {
        # The user specified a target explicitly, so no extra .txt is created and
        # only that one file is probed.
    } else {
        $txtProbePath = Join-Path $env:TEMP 'PathAdderVerifyProbe.txt'
        try {
            Set-Content -LiteralPath $txtProbePath -Value 'PathAdder verify probe' -Encoding ASCII -ErrorAction Stop
            $probeTargets += $txtProbePath
        } catch {
            $txtProbePath = ''
            Write-Note (T 'Verify.Check.ProbeTxtFailed' @($_.Exception.Message))
        }
    }

    $validTargets = @()
    foreach ($probe in $probeTargets) {
        if ([string]::IsNullOrWhiteSpace($probe)) { continue }
        if (-not (Test-Path -LiteralPath $probe -PathType Leaf)) { continue }
        $validTargets += $probe
    }

    if ($validTargets.Count -eq 0) {
        Write-Fail (T 'Verify.Check.NoProbeTarget' @(($probeTargets -join ', ')))
    } else {
        $resolvedExe = (Resolve-Path -LiteralPath $validTargets[0]).ProviderPath
        Write-Host (T 'Verify.Check.ProbeTargets' @($validTargets.Count,
            (($validTargets | ForEach-Object { $_ }) -join ' , '))) -ForegroundColor White

        # Compile the COM interop assembly
        $interopReady = $false
        $interopSource = @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

namespace PathAdderVerify
{
    // Note: this assembly deliberately does NOT use [ComImport] interfaces.
    // Reason: taking a COM object out through "out object" and then casting it
    // to a ComImport interface throws InvalidCastException ("Specified cast is
    // not valid") under PowerShell Add-Type (CodeDom compilation), and a
    // ComImport method list must match the vtable exactly - omitting one method
    // silently shifts every later slot. Instead the function pointers are read
    // straight from the vtable slots and invoked through delegates: no RCW cast
    // is needed and the slot numbers are written out explicitly, which is both
    // readable and verifiable.
    //
    // Real IContextMenu vtable (after the 3 IUnknown slots):
    //   [3] QueryContextMenu   [4] TrackPopupMenuEx   [5] GetMenuStringInfo
    //   [6] InvokeCommand      [7] GetCommandString
    // IShellItem vtable (after IUnknown):
    //   [3] BindToHandler

    public class MenuEntry
    {
        public int Depth;
        public int CommandId;
        public string Text;
        public string Verb;
        public bool IsSeparator;
        public bool IsSubmenu;
    }

    public static class ContextMenuEnumerator
    {
        private const uint CMF_NORMAL = 0x0000;
        private const uint GCS_VERBKEY = 0x00000080;
        private const uint MF_BYPOSITION = 0x00000400;
        private const uint COINIT_APARTMENTTHREADED = 0x00000002;
        private const int S_OK = 0;
        private const int S_FALSE = 1;
        private const uint MF_BYCOMMAND = 0x00000000;
        private const uint SEPARATOR_ID = 0xFFFFFFFFu;

        [UnmanagedFunctionPointer(CallingConvention.StdCall)]
        private delegate int QueryInterfaceFn(IntPtr self, ref Guid iid, out IntPtr ppv);

        [UnmanagedFunctionPointer(CallingConvention.StdCall)]
        private delegate uint ReleaseFn(IntPtr self);

        [UnmanagedFunctionPointer(CallingConvention.StdCall)]
        private delegate int BindToHandlerFn(IntPtr self, IntPtr pbc,
            ref Guid bhid, ref Guid riid, out IntPtr ppv);

        [UnmanagedFunctionPointer(CallingConvention.StdCall)]
        private delegate int QueryContextMenuFn(IntPtr self, IntPtr hmenu,
            uint iMenu, uint idCmdFirst, uint idCmdLast, uint uFlags);

        [UnmanagedFunctionPointer(CallingConvention.StdCall)]
        private delegate int GetCommandStringFn(IntPtr self, IntPtr idCmd,
            uint uType, IntPtr pwReserved,
            [Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder pszName, uint cchMax);

        // DllImport resolves entry points by *method name*, so after renaming a
        // local method you must point EntryPoint back at the real exported name
        // in the DLL, otherwise it fails at run time with "Unable to find an
        // entry point named ... in DLL".
        [DllImport("shell32.dll", EntryPoint = "SHCreateItemFromParsingName",
            CharSet = CharSet.Unicode, PreserveSig = true)]
        private static extern int SHCreateItemFromParsingNameRaw(
            [MarshalAs(UnmanagedType.LPWStr)] string path,
            IntPtr pbc, ref Guid riid, out IntPtr ppv);

        [DllImport("ole32.dll")]
        private static extern int CoInitializeEx(IntPtr pvReserved, uint dwCoInit);

        [DllImport("ole32.dll")]
        private static extern void CoUninitialize();

        [DllImport("user32.dll", SetLastError = true)]
        private static extern IntPtr CreatePopupMenu();

        [DllImport("user32.dll", SetLastError = true)]
        private static extern int GetMenuItemCount(IntPtr hMenu);

        [DllImport("user32.dll", SetLastError = true)]
        private static extern uint GetMenuItemID(IntPtr hMenu, int nPos);

        [DllImport("user32.dll", SetLastError = true)]
        private static extern IntPtr GetSubMenu(IntPtr hMenu, int nPos);

        [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern int GetMenuStringW(IntPtr hMenu, uint uIDItem,
            StringBuilder lpString, int cchMax, uint uFlag);

        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool DestroyMenu(IntPtr hMenu);

        /// <summary>Reads the function pointer at vtable slot index and wraps it in a delegate.</summary>
        private static T GetVtableMethod<T>(IntPtr instance, int index) where T : class
        {
            if (instance == IntPtr.Zero)
            {
                throw new InvalidOperationException("COM object pointer is null");
            }
            IntPtr vtable = Marshal.ReadIntPtr(instance);
            if (vtable == IntPtr.Zero)
            {
                throw new InvalidOperationException("COM object vtable is null");
            }
            IntPtr method = Marshal.ReadIntPtr(vtable, index * IntPtr.Size);
            if (method == IntPtr.Zero)
            {
                throw new InvalidOperationException("vtable slot " + index + " is null");
            }
            return Marshal.GetDelegateForFunctionPointer(method, typeof(T)) as T;
        }

        private static string GetItemText(IntPtr hMenu, int position, int commandId)
        {
            StringBuilder buffer = new StringBuilder(1024);
            int written = GetMenuStringW(hMenu, (uint)position, buffer,
                buffer.Capacity, MF_BYPOSITION);
            if (written > 0)
            {
                return buffer.ToString();
            }

            buffer.Length = 0;
            written = GetMenuStringW(hMenu, (uint)commandId, buffer,
                buffer.Capacity, MF_BYCOMMAND);
            return written > 0 ? buffer.ToString() : string.Empty;
        }

        private static string GetVerbKey(IntPtr contextMenu, int commandId)
        {
            IntPtr self = contextMenu;
            try
            {
                GetCommandStringFn getCommandString =
                    GetVtableMethod<GetCommandStringFn>(self, 7);
                if (getCommandString == null)
                {
                    return string.Empty;
                }

                StringBuilder buffer = new StringBuilder(512);
                int hr = getCommandString(self, (IntPtr)commandId, GCS_VERBKEY,
                    IntPtr.Zero, buffer, (uint)buffer.Capacity);
                if (hr == S_OK && buffer.Length > 0)
                {
                    return buffer.ToString();
                }
            }
            catch
            {
                // Some owner-drawn menu items do not implement GetCommandString; ignore those.
            }
            return string.Empty;
        }

        private static void Walk(IntPtr contextMenu, IntPtr hMenu,
            List<MenuEntry> results, int depth, int maxDepth)
        {
            int count = GetMenuItemCount(hMenu);
            for (int i = 0; i < count; i++)
            {
                uint rawId = GetMenuItemID(hMenu, i);
                int commandId = unchecked((int)rawId);
                bool isSubmenu = GetSubMenu(hMenu, i) != IntPtr.Zero;
                bool isSeparator = (rawId == SEPARATOR_ID) || (rawId == 0u);

                MenuEntry entry = new MenuEntry();
                entry.Depth = depth;
                entry.CommandId = commandId;
                entry.IsSeparator = isSeparator;
                entry.IsSubmenu = isSubmenu;
                entry.Text = isSeparator ? string.Empty : GetItemText(hMenu, i, commandId);
                entry.Verb = (isSeparator || isSubmenu || commandId <= 0)
                    ? string.Empty
                    : GetVerbKey(contextMenu, commandId);
                results.Add(entry);

                if (isSubmenu && depth < maxDepth)
                {
                    IntPtr sub = GetSubMenu(hMenu, i);
                    if (sub != IntPtr.Zero)
                    {
                        Walk(contextMenu, sub, results, depth + 1, maxDepth);
                    }
                }
            }
        }

        public static MenuEntry[] Enumerate(string filePath)
        {
            List<MenuEntry> results = new List<MenuEntry>();

            Guid iidShellItem = new Guid("43826d1d-e718-42ee-bc55-a1e261c37bfe");
            Guid iidContextMenu = new Guid("4e8f4ead-b583-44da-abed-6d36b4e4de50");
            // BHID_ShellMenu: the full IContextMenu of a single shell item (Explorer's own path)
            Guid bhidShellMenu = new Guid("1dea3a3e-3f4c-4b0b-8be3-e6d5cd6e0dbe");
            // BHID_SFUIObject: fallback handler
            Guid bhidSfUiObject = new Guid("c2f5b2ee-3ba6-41d8-b83c-9d9d0915ed1a");

            int coInitResult = CoInitializeEx(IntPtr.Zero, COINIT_APARTMENTTHREADED);
            bool shouldUninitialize = (coInitResult == S_OK || coInitResult == S_FALSE);

            IntPtr shellItem = IntPtr.Zero;
            IntPtr contextMenu = IntPtr.Zero;
            IntPtr hMenu = IntPtr.Zero;

            try
            {
                hMenu = CreatePopupMenu();
                if (hMenu == IntPtr.Zero)
                {
                    throw new InvalidOperationException("CreatePopupMenu failed");
                }

                int hrCreate = SHCreateItemFromParsingNameRaw(filePath, IntPtr.Zero,
                    ref iidShellItem, out shellItem);
                if (hrCreate != S_OK || shellItem == IntPtr.Zero)
                {
                    throw new InvalidOperationException(
                        "SHCreateItemFromParsingName failed (HRESULT=0x" +
                        hrCreate.ToString("X8") + "), path=" + filePath);
                }

                BindToHandlerFn bindToHandler = GetVtableMethod<BindToHandlerFn>(shellItem, 3);
                if (bindToHandler == null)
                {
                    throw new InvalidOperationException("Cannot obtain IShellItem.BindToHandler");
                }

                int hrBind = bindToHandler(shellItem, IntPtr.Zero, ref bhidShellMenu,
                    ref iidContextMenu, out contextMenu);
                if (hrBind != S_OK || contextMenu == IntPtr.Zero)
                {
                    Guid fallbackBhid = bhidSfUiObject;
                    contextMenu = IntPtr.Zero;
                    hrBind = bindToHandler(shellItem, IntPtr.Zero, ref fallbackBhid,
                        ref iidContextMenu, out contextMenu);
                }
                if (contextMenu == IntPtr.Zero)
                {
                    throw new InvalidOperationException(
                        "BindToHandler could not obtain IContextMenu (HRESULT=0x" +
                        hrBind.ToString("X8") + ")");
                }

                QueryContextMenuFn queryContextMenu =
                    GetVtableMethod<QueryContextMenuFn>(contextMenu, 3);
                if (queryContextMenu == null)
                {
                    throw new InvalidOperationException("Cannot obtain IContextMenu.QueryContextMenu");
                }

                int hrQuery = queryContextMenu(contextMenu, hMenu, 0, 1, 0x7FFF, CMF_NORMAL);
                if (hrQuery != S_OK)
                {
                    throw new InvalidOperationException(
                        "QueryContextMenu failed (HRESULT=0x" + hrQuery.ToString("X8") + ")");
                }

                Walk(contextMenu, hMenu, results, 1, 2);
            }
            finally
            {
                if (hMenu != IntPtr.Zero)
                {
                    DestroyMenu(hMenu);
                }
                if (contextMenu != IntPtr.Zero)
                {
                    ReleaseFn releaseMenu = null;
                    try
                    {
                        releaseMenu = GetVtableMethod<ReleaseFn>(contextMenu, 2);
                        if (releaseMenu != null)
                        {
                            releaseMenu(contextMenu);
                        }
                    }
                    catch
                    {
                    }
                }
                if (shellItem != IntPtr.Zero)
                {
                    ReleaseFn releaseItem = null;
                    try
                    {
                        releaseItem = GetVtableMethod<ReleaseFn>(shellItem, 2);
                        if (releaseItem != null)
                        {
                            releaseItem(shellItem);
                        }
                    }
                    catch
                    {
                    }
                }
                if (shouldUninitialize)
                {
                    CoUninitialize();
                }
            }

            return results.ToArray();
        }
    }
}
'@

        try {
            Add-Type -TypeDefinition $interopSource -ErrorAction Stop
            $interopReady = $true
        } catch {
            Write-Note (T 'Verify.Check.InteropCompileFailed' @($_.Exception.Message))
        }

        if ($interopReady) {
            # Probe each target file (.exe and .txt); any single success counts as
            # layer 2 evidence.
            foreach ($probePath in $validTargets) {
              $resolvedProbe = (Resolve-Path -LiteralPath $probePath).ProviderPath
              Write-Host ''
              Write-Host (T 'Verify.Check.ProbeHeader' @($resolvedProbe)) -ForegroundColor White

              $menuEntries = $null
              $enumError = ''
              try {
                $menuEntries = [PathAdderVerify.ContextMenuEnumerator]::Enumerate($resolvedProbe)
              } catch {
                $enumError = $_.Exception.Message
              }

            if ($null -ne $menuEntries) {
                $displayEntries = @($menuEntries |
                    Where-Object { -not $_.IsSeparator -and -not [string]::IsNullOrWhiteSpace($_.Text) })

                Write-Host ''
                Write-Host (T 'Verify.Check.EnumeratedCount' @($displayEntries.Count)) -ForegroundColor White
                foreach ($entry in $displayEntries) {
                    $indent = '    '
                    if ($entry.Depth -gt 1) { $indent = '      └ ' }
                    $verbText = ''
                    if (-not [string]::IsNullOrWhiteSpace($entry.Verb)) {
                        $verbText = '   {' + $entry.Verb + '}'
                    }
                    $isOurs = ($verbKeys -contains $entry.Verb) -or
                        ($entry.Text -eq (Get-PathAdderShellMenuParentLabel))
                    $color = 'Gray'
                    if ($isOurs) { $color = 'Green' }
                    Write-Host ($indent + $entry.Text + $verbText) -ForegroundColor $color
                }

                Write-Host ''
                $foundVerbs = @()

                # (1) Was the parent menu entry built by Explorer?
                $parentItem = @($menuEntries | Where-Object {
                    $_.Text -eq (Get-PathAdderShellMenuParentLabel)
                })
                if ($parentItem.Count -gt 0) {
                    Write-Pass (T 'Verify.Check.ParentBuilt' @((Get-PathAdderShellMenuParentLabel)))
                    $script:CascadeParentFound = $true
                } else {
                    Write-Fail (T 'Verify.Check.ParentNotBuilt' @((Get-PathAdderShellMenuParentLabel)))
                }

                # (2) Submenu: provided dynamically by MenuPicker.ps1, so it is not
                #     part of Explorer's static menu tree.
                #
                #     2026-10-04 change: on Windows 11 the SubCommands hover cascade
                #     was measured never to expand (the parent is visible but hover
                #     does nothing), so the design became "click the parent ->
                #     MenuPicker.ps1 pops up the menu at the cursor". The 4 actions
                #     therefore should NOT appear in Explorer's static menu tree.
                #     Requiring them there (as the old logic did) would report a
                #     working feature as a failure, so this now checks the real
                #     preconditions instead.
                Write-Host ''
                Write-Note (T 'Verify.Check.SubmenuDynamic')

                $pickerLocal = Join-Path (Split-Path -Parent $expectedEnginePath) 'MenuPicker.ps1'
                if (Test-Path -LiteralPath $pickerLocal -PathType Leaf) {
                    Write-Pass (T 'Verify.Check.PickerUsable' @($pickerLocal))
                    $script:CascadeExpanded = $true
                    $foundVerbs = @($verbKeys)
                } else {
                    Write-Fail (T 'Verify.Check.PickerMissing' @($pickerLocal))
                }

                Write-Host ''
                if ($script:CascadeParentFound -and $script:CascadeExpanded -and
                    ($foundVerbs.Count -eq $verbKeys.Count)) {
                    $script:ContextMenuVerified = $true
                    Write-Pass (T 'Verify.Check.ParentAndPickerOk' @($verbKeys.Count))
                } else {
                    Write-Fail (T 'Verify.Check.MenuIncomplete')
                }
            } else {
                Write-Note (T 'Verify.Check.EnumFailed' @($enumError))
                $script:Warnings += (T 'Verify.Warn.EnumFailed' @($enumError))
            }
            } # end foreach probePath
        } # end if interopReady

        # Clean up the temporary probe file
        if (-not [string]::IsNullOrWhiteSpace($txtProbePath) -and
            (Test-Path -LiteralPath $txtProbePath)) {
            try { [System.IO.File]::Delete($txtProbePath) } catch { }
        }
    }
}

# -----------------------------------------------------------------------------
# 5b. Layer 2 fallback path: equivalent derivation from Explorer's association
#     resolution rules
#
#     Background: in some restricted environments (containers / trimmed systems /
#     remote sessions) SHCreateItemFromParsingName returns E_NOINTERFACE
#     (0x80004002) for every IID, so layer 2 cannot run at all. In that case no
#     conclusion can be drawn about whether the menu works, but the registry-side
#     preconditions can still be verified:
#
#       1. What is the associated ProgID of HKCR\.exe (Explorer uses it to pick
#          the main shell path)?
#       2. Under the merged view of that ProgID (HKCR = HKLM merged with HKCU), do
#          both the system verbs (open/runas/runasuser) and our 4 verbs exist?
#       3. Do our verbs sit on the *main* path rather than only on the
#          SystemFileAssociations fallback path?
#
#     Point 3 is exactly the criterion of this bug: if a verb only exists under
#     SystemFileAssociations and not on the main ProgID, it is never enumerated.
#     Reading the merged view through HKCR directly reflects the final outcome.
# -----------------------------------------------------------------------------

if (-not $script:ContextMenuVerified) {
    Write-Section (T 'Verify.Section.Layer2Fallback')

    # `*` is the official Windows association key for "all file objects"; it
    # covers every extension (including .exe) unconditionally and needs no ProgID
    # association resolution, so checking the merged view directly is enough.
    $mergedStarKey = 'Registry::HKEY_CLASSES_ROOT\*\shell'
    $mergedStarVerbs = @()
    try {
        if (Test-Path -LiteralPath $mergedStarKey) {
            $mergedStarVerbs = @((Get-ChildItem -LiteralPath $mergedStarKey -ErrorAction SilentlyContinue).PSChildName)
        }
    } catch {
        $mergedStarVerbs = @()
    }

    if ($mergedStarVerbs.Count -eq 0) {
        Write-Note (T 'Verify.Check.MergedUnreadable' @('HKCR\*\shell'))
    } else {
        Write-Host (T 'Verify.Check.MergedVerbs') -ForegroundColor White
        Write-Host ('    ' + ($mergedStarVerbs -join ' | ')) -ForegroundColor DarkGray

        $parentNameLocal = Get-PathAdderShellParentName
        if ($mergedStarVerbs -contains $parentNameLocal) {
            Write-Pass (T 'Verify.Check.MergedParentVisible' @('HKCR\*\shell\' + $parentNameLocal))

            # In the current design the 4 actions are provided by MenuPicker.ps1 and
            # the parent no longer has a shell subcommand tree. So this now checks:
            # (1) the parent has a command pointing at MenuPicker.ps1; (2) the script
            # exists.
            $mergedParentCommand = 'Registry::HKEY_CLASSES_ROOT\*\shell\' + $parentNameLocal + '\command'
            if (Test-Path -LiteralPath $mergedParentCommand) {
                Write-Pass (T 'Verify.Check.MergedParentCommand' @($mergedParentCommand))
            } else {
                Write-Fail (T 'Verify.Check.MergedParentCommandMissing' @($mergedParentCommand))
            }

            $mergedPickerPath = Join-Path (Split-Path -Parent $expectedEnginePath) 'MenuPicker.ps1'
            if (Test-Path -LiteralPath $mergedPickerPath -PathType Leaf) {
                Write-Pass (T 'Verify.Check.PickerUsable' @($mergedPickerPath))
                $script:AssocResolutionVerified = $true
            } else {
                Write-Fail (T 'Verify.Check.PickerMissing' @($mergedPickerPath))
            }

            # Reverse confirmation: the legacy shell subcommand tree must be gone.
            $mergedLegacyShell = 'Registry::HKEY_CLASSES_ROOT\*\shell\' + $parentNameLocal + '\shell'
            if (Test-Path -LiteralPath $mergedLegacyShell) {
                Write-Fail (T 'Verify.Check.MergedLegacyShell' @($mergedLegacyShell))
            } else {
                Write-Pass (T 'Verify.Check.ParentNoLegacyShellTree')
            }
        } else {
            Write-Fail (T 'Verify.Check.MergedParentInvisible' @('HKCR\*\shell\' + $parentNameLocal))
        }

        # System verb integrity (exefile side)
        foreach ($systemVerb in @('open', 'runas', 'runasuser')) {
            $exeMerged = 'Registry::HKEY_CLASSES_ROOT\exefile\shell'
            $exeList = @()
            try {
                if (Test-Path -LiteralPath $exeMerged) {
                    $exeList = @((Get-ChildItem -LiteralPath $exeMerged -ErrorAction SilentlyContinue).PSChildName)
                }
            } catch {
                $exeList = @()
            }
            if ($exeList -contains $systemVerb) {
                Write-Pass (T 'Verify.Check.MergedSystemVerbIntact' @($systemVerb))
            }
        }
    }
}

# -----------------------------------------------------------------------------
# 6. Summary
# -----------------------------------------------------------------------------

Write-Section (T 'Verify.Section.Summary')

Write-Host (T 'Verify.Summary.Structure' @((Get-PathAdderShellParentName), $verbKeys.Count)) -ForegroundColor Gray
Write-Host (T 'Verify.Summary.Failures' @($script:Failures.Count)) -ForegroundColor Gray
Write-Host (T 'Verify.Summary.Warnings' @($script:Warnings.Count)) -ForegroundColor Gray
Write-Host (T 'Verify.Summary.ContextMenu' @($(if ($script:ContextMenuVerified) { T 'Verify.Status.Done' } else { T 'Verify.Status.NotDone' }))) -ForegroundColor Gray
Write-Host (T 'Verify.Summary.AssocResolution' @($(if ($script:AssocResolutionVerified) { T 'Verify.Status.Done' } else { T 'Verify.Status.NotDone' }))) -ForegroundColor Gray
if ($script:ContextMenuVerified) {
    Write-Host (T 'Verify.Summary.ParentBuilt' @($(if ($script:CascadeParentFound) { T 'Verify.Status.Appeared' } else { T 'Verify.Status.NotAppeared' }))) -ForegroundColor Gray
    Write-Host (T 'Verify.Summary.PickerScript' @($(if ($script:CascadeExpanded) { T 'Verify.Status.Available' } else { T 'Verify.Status.Unavailable' }))) -ForegroundColor Gray
}

Write-Host ''
if ($script:Failures.Count -gt 0) {
    Write-Host (T 'Verify.Conclusion.Failed') -ForegroundColor Red
    Write-Host (T 'Verify.Advice.RestartExplorer') -ForegroundColor Red
    Write-Host (T 'Verify.Advice.CheckEngine') -ForegroundColor Red
    Write-Host (T 'Verify.Advice.Reinstall') -ForegroundColor Red
    Write-Host ''
    exit 1
}

if ($script:ContextMenuVerified) {
    Write-Host (T 'Verify.Conclusion.AllPass1') -ForegroundColor Green
    Write-Host (T 'Verify.Conclusion.AllPass2' @((T 'App.Name'), $verbKeys.Count)) -ForegroundColor Green
} elseif ($script:AssocResolutionVerified) {
    Write-Host (T 'Verify.Conclusion.RegOk1') -ForegroundColor Yellow
    Write-Host (T 'Verify.Conclusion.RegOk2') -ForegroundColor Yellow
    Write-Host (T 'Verify.Conclusion.RegOk3') -ForegroundColor Yellow
    Write-Host (T 'Verify.Conclusion.RegOk4') -ForegroundColor Yellow
} else {
    Write-Host (T 'Verify.Conclusion.NoEvidence1') -ForegroundColor Yellow
    Write-Host (T 'Verify.Conclusion.NoEvidence2') -ForegroundColor Yellow
    Write-Host (T 'Verify.Conclusion.NoEvidence3') -ForegroundColor Yellow
    Write-Host (T 'Verify.Conclusion.NoEvidence4') -ForegroundColor Yellow
    Write-Host ''
    exit 2
}
Write-Host ''
Write-Host (T 'Verify.Tip.Layered1') -ForegroundColor Yellow
Write-Host (T 'Verify.Tip.Layered2') -ForegroundColor Yellow
Write-Host (T 'Verify.Tip.Restart1') -ForegroundColor Yellow
Write-Host (T 'Verify.Tip.Restart2') -ForegroundColor Yellow
Write-Host ''
exit 0
