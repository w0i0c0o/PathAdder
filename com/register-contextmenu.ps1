<#
.SYNOPSIS
    Registers the classic IContextMenu shell extension for a hover-expandable submenu.

.DESCRIPTION
    The IExplorerCommand + ECF_HASSUBCOMMANDS approach does not work reliably on the
    tested Explorer version. Diagnostics show Explorer calling GetFlags, GetTitle, and
    EnumSubCommands, constructing the enumerator, but never calling
    IEnumExplorerCommand::Next. It creates another object, calls only GetState, and stops.
    This is Explorer behavior rather than a defect in the extension implementation.

    This script registers PathAdderContextMenu instead. It implements IShellExtInit and
    IContextMenu, creates an HMENU submenu with CreatePopupMenu in QueryContextMenu, and
    inserts its parent item with MF_POPUP. USER32 then provides standard hover expansion
    without relying on Explorer's command-extension policy.

    The script performs five operations:
      1. Builds the assembly, including PathAdderContextMenu.cs.
      2. Registers the COM class with RegAsm /codebase.
      3. Removes every old *\shell\PathAdder IExplorerCommand registration.
      4. Registers *\shellex\ContextMenuHandlers\PathAdder with the menu CLSID and adds
         the extension to the Shell Extensions Approved list.
      5. Reads the registration back for verification.

    The command appears in the classic context menu (Show more options / Shift+F10).

.EXAMPLE
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\register-contextmenu.ps1
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\register-contextmenu.ps1 -Unregister
#>

[CmdletBinding()]
param(
    [switch]$SkipBuild,
    [switch]$Unregister
)

$ErrorActionPreference = 'Stop'

$comDirectory = $PSScriptRoot
$scriptRoot = Split-Path -Parent $comDirectory
$global:PathAdderRootDirectory = $scriptRoot
. (Join-Path $scriptRoot 'lib\i18n.ps1')
Initialize-PathAdderI18n | Out-Null

$menuClsid = '{9B3E5D2A-7C41-4F8B-A1D6-2E5C8F40B7A3}'
$handlerKey = 'Software\Classes\*\shellex\ContextMenuHandlers\PathAdder'
$approved = 'Software\Microsoft\Windows\CurrentVersion\Shell Extensions\Approved'

# ---------------------------------------------------------------------------
# 0. Administrator check
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

$scopes = @(
    @{ Label = 'HKLM'; Root = ([Microsoft.Win32.Registry]::LocalMachine) },
    @{ Label = 'HKCU'; Root = ([Microsoft.Win32.Registry]::CurrentUser) }
)

# ---------------------------------------------------------------------------
# Unregister branch
# ---------------------------------------------------------------------------
if ($Unregister) {
    Write-Host (T 'Com.RegisterClassic.UnregisterHeader') -ForegroundColor Cyan
    foreach ($scope in $scopes) {
        foreach ($rel in @($handlerKey)) {
            try {
                $k = $scope.Root.OpenSubKey($rel)
                if ($null -eq $k) { continue }
                $k.Close()
            }
            catch { continue }
            try { $scope.Root.DeleteSubKeyTree($rel, $false) } catch { }
            Write-Host (T 'Com.RegisterClassic.DeletedRegistryKey' @($scope.Label, $rel)) -ForegroundColor Gray
        }
    }
    try {
        $ak = $scopes[0].Root.OpenSubKey($approved, $true)
        if ($null -ne $ak) {
            if (@($ak.GetValueNames()) -contains $menuClsid) { $ak.DeleteValue($menuClsid, $false) }
            $ak.Close()
        }
    }
    catch { }
    Write-Host (T 'Com.RegisterClassic.UnregisteredRestart') -ForegroundColor Green
    Write-Host (T 'Com.Common.RestartExplorerCommand') -ForegroundColor Gray
    exit 0
}

# ---------------------------------------------------------------------------
# 0.5 Release the DLL before building or registering it.
#     release-dll.ps1 terminates holders and restarts Explorer; it returns 0 immediately
#     when the DLL is already writable.
# ---------------------------------------------------------------------------
Write-Host (T 'Com.RegisterClassic.StepRelease') -ForegroundColor Cyan

$releaser = Join-Path $PSScriptRoot 'release-dll.ps1'
if (Test-Path -LiteralPath $releaser -PathType Leaf) {
    & $releaser
    if ($LASTEXITCODE -ne 0) {
        Write-Host (T 'Com.RegisterClassic.ReleaseStillLocked') -ForegroundColor Yellow
    }
}
else {
    Write-Host (T 'Com.RegisterClassic.ReleaseScriptMissing') -ForegroundColor Gray
}

# ---------------------------------------------------------------------------
# 1. Build
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host (T 'Com.RegisterClassic.StepBuild') -ForegroundColor Cyan

$dllPath = Join-Path $PSScriptRoot 'PathAdderShellExt.dll'

if ($SkipBuild) {
    Write-Host (T 'Com.Common.SkipBuild') -ForegroundColor Gray
}
else {
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
Write-Host (T 'Com.RegisterClassic.StepRegAsm') -ForegroundColor Cyan

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
# 3. Remove old IExplorerCommand menu keys to avoid duplicate commands
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host (T 'Com.RegisterClassic.StepRemoveStale') -ForegroundColor Cyan

$stalePaths = @(
    'Software\Classes\*\shell\PathAdder',
    'Software\Classes\exefile\shell\PathAdder',
    'Software\Classes\Directory\shell\PathAdder',
    'Software\Classes\AllFilesystemObjects\shell\PathAdder'
)

foreach ($scope in $scopes) {
    foreach ($rel in $stalePaths) {
        $hit = $false
        try {
            $p = $scope.Root.OpenSubKey($rel)
            if ($null -ne $p) { $p.Close(); $hit = $true }
        }
        catch { $hit = $false }
        if (-not $hit) { continue }
        try { $scope.Root.DeleteSubKeyTree($rel, $false) } catch { }
        Write-Host (T 'Com.RegisterClassic.DeletedRegistryKey' @($scope.Label, $rel)) -ForegroundColor Gray
    }
}

# ---------------------------------------------------------------------------
# 4. Register ContextMenuHandlers
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host (T 'Com.RegisterClassic.StepRegisterClassic') -ForegroundColor Cyan

try {
    $k = $scopes[0].Root.CreateSubKey($handlerKey)
    $name = $k.GetValue('')          # The default value may contain a different CLSID.
    $k.SetValue('', $menuClsid, [Microsoft.Win32.RegistryValueKind]::String)
    $k.Close()
    if (($null -ne $name) -and ($name -ne '')) {
        Write-Host (T 'Com.RegisterClassic.DefaultOverwritten' @($name)) -ForegroundColor Gray
    }
    Write-Host (T 'Com.RegisterClassic.HandlerWritten' @($handlerKey, $menuClsid)) -ForegroundColor Green
}
catch {
    Write-Host (T 'Com.RegisterClassic.RegistryWriteFailed' @($_.Exception.Message)) -ForegroundColor Red
    exit 1
}

# Some policies require the Approved entry; adding it is harmless elsewhere.
try {
    $ak = $scopes[0].Root.OpenSubKey($approved, $true)
    if ($null -eq $ak) { $ak = $scopes[0].Root.CreateSubKey($approved) }
    if ($null -ne $ak) {
        $ak.SetValue($menuClsid, (T 'App.Name'), [Microsoft.Win32.RegistryValueKind]::String)
        $ak.Close()
        Write-Host (T 'Com.RegisterClassic.ApprovedAdded') -ForegroundColor Gray
    }
}
catch {
    Write-Host (T 'Com.RegisterClassic.ApprovedSkipped' @($_.Exception.Message)) -ForegroundColor DarkYellow
}

# ---------------------------------------------------------------------------
# 5. Read-back verification
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host (T 'Com.RegisterClassic.StepSelfCheck') -ForegroundColor Cyan

$check = $scopes[0].Root.OpenSubKey($handlerKey)
if ($null -eq $check) {
    Write-Host (T 'Com.RegisterClassic.RegistrationKeyMissing' @($handlerKey)) -ForegroundColor Red
    exit 1
}
$actual = [string]$check.GetValue('', '')
$check.Close()

if ($actual -ne $menuClsid) {
    Write-Host (T 'Com.RegisterClassic.HandlerValueWrong' @($actual)) -ForegroundColor Red
    exit 1
}
Write-Host (T 'Com.RegisterClassic.RegisteredSuccessfully') -ForegroundColor Green

Write-Host ''
Write-Host (T 'Com.RegisterClassic.Complete') -ForegroundColor Green
Write-Host ''
Write-Host (T 'Com.RegisterClassic.MustRestart') -ForegroundColor Yellow
Write-Host (T 'Com.Common.RestartExplorerCommand') -ForegroundColor Gray
Write-Host ''
Write-Host (T 'Com.RegisterClassic.VerifyLabel') -ForegroundColor Cyan
Write-Host (T 'Com.RegisterClassic.VerifyContextMenu') -ForegroundColor Gray
Write-Host (T 'Com.RegisterClassic.VerifyAppName' @((T 'App.Name'))) -ForegroundColor Gray
Write-Host (T 'Com.RegisterClassic.VerifyHover') -ForegroundColor Gray
Write-Host ''
Write-Host (T 'Com.RegisterClassic.DiagnosticLogLabel') -ForegroundColor Gray
Write-Host (T 'Com.Common.DiagnosticLogCommand') -ForegroundColor Gray
Write-Host (T 'Com.RegisterClassic.DiagnosticExpected') -ForegroundColor Cyan
Write-Host ''
Write-Host (T 'Com.RegisterClassic.UninstallLabel') -ForegroundColor Gray
Write-Host (T 'Com.RegisterClassic.UninstallCommand') -ForegroundColor Gray
Write-Host ''

exit 0
