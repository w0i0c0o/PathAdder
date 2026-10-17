<#
.SYNOPSIS
    Registers the PathAdder COM shell extension in native hover-cascade mode.

.DESCRIPTION
    Performs four operations:
      1. Builds the DLL when it is missing or older than the source.
      2. Registers the COM class with RegAsm /codebase under HKLM.
      3. Converts *\shell\PathAdder from a command-based popup into an
         ExplorerCommandHandler backed by the parent CLSID.
      4. Notifies Explorer that shell associations changed.

    The change is reversible. Run restore-menu.ps1 to return to MenuPicker mode.

    On Windows 11, this handler appears only in the classic context menu (Show more
    options / Shift+F10). Displaying it in the first-level compact menu requires an MSIX
    package with desktop4:FileExplorerContextMenus declared in Package.appxmanifest.
    See README-COM.md for details.

.EXAMPLE
    # Run as administrator.
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\register-com.ps1
#>

[CmdletBinding()]
param(
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'

$comDirectory = $PSScriptRoot
$scriptRoot = Split-Path -Parent $comDirectory
$global:PathAdderRootDirectory = $scriptRoot
. (Join-Path $scriptRoot 'lib\i18n.ps1')
Initialize-PathAdderI18n | Out-Null

# Parent command CLSID; it matches PathAdderCommand in PathAdderShellExt.cs.
$parentClsid = '{1C789ABD-65D1-5FAD-8B98-52595EBB290B}'
$verbKey = 'Software\Classes\*\shell\PathAdder'

# ---------------------------------------------------------------------------
# 0. Administrator check (RegAsm writes to HKLM)
# ---------------------------------------------------------------------------
$isAdmin = $false
try {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    $isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
catch { $isAdmin = $false }

if (-not $isAdmin) {
    Write-Host (T 'App.Msg.AdminRequired') -ForegroundColor Red
    Write-Host (T 'Com.Common.RunAsAdministrator') -ForegroundColor Yellow
    exit 1
}

# ---------------------------------------------------------------------------
# 1. Build
# ---------------------------------------------------------------------------
$dllPath = Join-Path $PSScriptRoot 'PathAdderShellExt.dll'
$sourcePath = Join-Path $PSScriptRoot 'PathAdderShellExt.cs'

if ($SkipBuild) {
    Write-Host (T 'Com.Common.SkipBuild') -ForegroundColor Gray
}
else {
    Write-Host (T 'Com.Register.StepBuild') -ForegroundColor Cyan
    & (Join-Path $PSScriptRoot 'build.ps1')
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

if (-not (Test-Path -LiteralPath $dllPath -PathType Leaf)) {
    Write-Host (T 'Com.Common.DllNotFound' @($dllPath)) -ForegroundColor Red
    exit 1
}

# ---------------------------------------------------------------------------
# 2. Register with RegAsm
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host (T 'Com.Register.StepRegAsm') -ForegroundColor Cyan

$regasmPath = ''
$frameworkRoot = Join-Path $env:WINDIR 'Microsoft.NET\Framework64'
foreach ($dir in @(Get-ChildItem -LiteralPath $frameworkRoot -Directory | Sort-Object Name -Descending)) {
    $candidate = Join-Path $dir.FullName 'RegAsm.exe'
    if (Test-Path -LiteralPath $candidate -PathType Leaf) { $regasmPath = $candidate; break }
}

if ([string]::IsNullOrWhiteSpace($regasmPath)) {
    Write-Host (T 'Com.Common.RegAsmNotFound') -ForegroundColor Red
    exit 1
}

& $regasmPath /codebase /nologo "$dllPath"
if ($LASTEXITCODE -ne 0) {
    Write-Host (T 'Com.Common.RegAsmFailed' @($LASTEXITCODE)) -ForegroundColor Red
    exit $LASTEXITCODE
}
Write-Host (T 'Com.Common.ComClassRegistered') -ForegroundColor Green

# ---------------------------------------------------------------------------
# 3. Switch to ExplorerCommandHandler
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host (T 'Com.Register.StepSwitchHandler') -ForegroundColor Cyan

# ---------------------------------------------------------------------------
# 3.1 Remove every historical PathAdder menu registration.
#
# Important diagnostic conclusion:
# If one menu key contains both a command subkey and an ExplorerCommandHandler value,
# Explorer instantiates the same CLSID twice: once as a normal verb (GetState / Invoke)
# and once as a cascading parent (GetFlags / GetTitle / EnumSubCommands). In testing,
# the parent item remained visible but never expanded because the enumeration path did
# not receive its results. The key must therefore be cleaned before one authoritative
# registration is written; the two mechanisms must never coexist.
# ---------------------------------------------------------------------------
$stalePaths = @(
    'Software\Classes\*\shell\PathAdder',
    'Software\Classes\exefile\shell\PathAdder',
    'Software\Classes\Directory\shell\PathAdder',
    'Software\Classes\AllFilesystemObjects\shell\PathAdder'
)
$scopes = @(
    @{ Label = 'HKLM'; Root = ([Microsoft.Win32.Registry]::LocalMachine) },
    @{ Label = 'HKCU'; Root = ([Microsoft.Win32.Registry]::CurrentUser) }
)

foreach ($scope in $scopes) {
    foreach ($rel in $stalePaths) {
        $exists = $false
        try {
            $probe = $scope.Root.OpenSubKey($rel)
            if ($null -ne $probe) { $probe.Close(); $exists = $true }
        }
        catch { $exists = $false }

        if (-not $exists) { continue }

        Write-Host (T 'Com.Register.StaleKeyFound' @($scope.Label, $rel)) -ForegroundColor DarkYellow

        try {
            $k = $scope.Root.OpenSubKey($rel, $true)

            $names = @($k.GetValueNames())
            if ($names -contains 'ExplorerCommandHandler') {
                $k.DeleteValue('ExplorerCommandHandler', $false)
                Write-Host (T 'Com.Register.HandlerValueDeleted') -ForegroundColor Gray
            }

            $subs = @($k.GetSubKeyNames())
            if ($subs -contains 'command') {
                $k.DeleteSubKeyTree('command')
                Write-Host (T 'Com.Register.CommandSubkeyDeleted') -ForegroundColor Gray
            }

            $remainSubs = @($k.GetSubKeyNames()).Count
            $remainVals = @($k.GetValueNames()).Count
            $k.Close()

            if (($remainSubs -eq 0) -and ($remainVals -eq 0)) {
                $scope.Root.DeleteSubKeyTree($rel, $false)
                Write-Host (T 'Com.Register.EmptyKeyRemoved') -ForegroundColor Gray
            }
        }
        catch {
            Write-Host (T 'Com.Register.CleanupSkipped' @($_.Exception.Message)) -ForegroundColor DarkYellow
        }
    }
}

# ---------------------------------------------------------------------------
# 3.2 Write one authoritative key under HKLM. RegAsm already requires elevation.
# ---------------------------------------------------------------------------
$newKey = $null
try { $newKey = $scopes[0].Root.CreateSubKey($verbKey) } catch { $newKey = $null }
if ($null -eq $newKey) { $newKey = $scopes[1].Root.CreateSubKey($verbKey) }

if ($null -eq $newKey) {
    Write-Host (T 'Com.Register.MenuKeyCreateFailed') -ForegroundColor Red
    exit 1
}

try {
    $newKey.SetValue('', (T 'App.Name'), [Microsoft.Win32.RegistryValueKind]::String)
    $newKey.SetValue('MUIVerb', (T 'App.Name'), [Microsoft.Win32.RegistryValueKind]::String)
    $newKey.SetValue('ExplorerCommandHandler', $parentClsid, [Microsoft.Win32.RegistryValueKind]::String)
    $newKey.SetValue('Position', 'Bottom', [Microsoft.Win32.RegistryValueKind]::String)
    Write-Host (T 'Com.Register.HandlerWritten' @($parentClsid)) -ForegroundColor Green
}
finally {
    $newKey.Close()
}

# 3.3 Read the key back and fail immediately if any required condition is not met.
Write-Host ''
Write-Host (T 'Com.Register.SelfCheckHeader') -ForegroundColor Cyan
$check = $scopes[0].Root.OpenSubKey($verbKey)
if ($null -eq $check) {
    Write-Host (T 'Com.Register.MenuKeyMissing') -ForegroundColor Red
    exit 1
}
$actualHandler = $check.GetValue('ExplorerCommandHandler', '')
$actualCommand = ''
try { $actualCommand = $check.OpenSubKey('command', $false) } catch { }
$check.Close()

if ($actualHandler -ne $parentClsid) {
    Write-Host (T 'Com.Register.HandlerValueWrong' @($actualHandler)) -ForegroundColor Red
    exit 1
}
if ($null -ne $actualCommand) {
    Write-Host (T 'Com.Register.CommandSubkeyRemains') -ForegroundColor Red
    exit 1
}
Write-Host (T 'Com.Register.MenuKeyValid') -ForegroundColor Green

# ---------------------------------------------------------------------------
# 4. Notify Explorer
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host (T 'Com.Register.StepNotifyExplorer') -ForegroundColor Cyan

$refreshed = $false
try {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class PathAdderNotify {
    [DllImport("shell32.dll", CharSet=CharSet.Auto)]
    public static extern void SHChangeNotify(uint wEventId, uint uFlags, IntPtr dwItem1, IntPtr dwItem2);
    public const uint SHCNE_ASSOCCHANGED = 0x08000000;
    public const uint SHCNF_IDLIST = 0x0000;
}
'@ -ErrorAction Stop
    [PathAdderNotify]::SHChangeNotify([PathAdderNotify]::SHCNE_ASSOCCHANGED, [PathAdderNotify]::SHCNF_IDLIST, [IntPtr]::Zero, [IntPtr]::Zero)
    $refreshed = $true
}
catch {
    Write-Host (T 'Com.Register.RefreshFailed' @($_.Exception.Message)) -ForegroundColor Yellow
}

Write-Host ''
Write-Host (T 'Com.Register.Complete') -ForegroundColor Green
Write-Host ''
Write-Host (T 'Com.Register.MustRestart') -ForegroundColor Yellow
Write-Host (T 'Com.Common.RestartExplorerCommand') -ForegroundColor Gray
Write-Host ''
Write-Host (T 'Com.Register.VerifyLabel') -ForegroundColor Cyan
Write-Host (T 'Com.Register.VerifyStep1' @((T 'App.Name'))) -ForegroundColor Gray
Write-Host (T 'Com.Register.VerifyStep2') -ForegroundColor Gray
Write-Host (T 'Com.Register.VerifyStep3') -ForegroundColor Gray
Write-Host (T 'Com.Common.DiagnosticLogCommand') -ForegroundColor Gray
Write-Host ''
Write-Host (T 'Com.Register.LogInterpretationLabel') -ForegroundColor Cyan
Write-Host (T 'Com.Register.LogHasNext') -ForegroundColor Gray
Write-Host (T 'Com.Register.LogNoNext') -ForegroundColor Gray
Write-Host (T 'Com.Register.LogDuplicateObject') -ForegroundColor Gray
Write-Host (T 'Com.Register.LogCleanupExplanation') -ForegroundColor Gray
Write-Host (T 'Com.Register.LogEmpty') -ForegroundColor Gray
Write-Host ''
Write-Host (T 'Com.Register.RestoreHint') -ForegroundColor Gray
Write-Host (T 'Com.Common.RestoreMenuCommand') -ForegroundColor Gray
Write-Host ''

exit 0
