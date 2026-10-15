<#
.SYNOPSIS
    Restores command-based MenuPicker mode after register-com.ps1 was used.

.DESCRIPTION
    Performs three operations:
      1. Removes the ExplorerCommandHandler value from *\shell\PathAdder.
      2. Unregisters the COM class with RegAsm /unregister when elevated.
      3. Restores the command subkey that launches MenuPicker.ps1.

    After completion, clicking the PathAdder context-menu item opens the popup menu at
    the pointer, restoring the behavior that existed before register-com.ps1 was run.

.EXAMPLE
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\restore-menu.ps1
#>

[CmdletBinding()]
param(
    # Switch the menu without unregistering COM, which is useful while Explorer holds the DLL.
    [switch]$KeepComRegistration
)

$ErrorActionPreference = 'Stop'

$comDirectory = $PSScriptRoot
$scriptRoot = Split-Path -Parent $comDirectory
$global:PathAdderRootDirectory = $scriptRoot
. (Join-Path $scriptRoot 'lib\i18n.ps1')
Initialize-PathAdderI18n | Out-Null

$verbKey = 'Software\Classes\*\shell\PathAdder'
$dllPath = Join-Path $PSScriptRoot 'PathAdderShellExt.dll'

Write-Host (T 'Com.Restore.StepClearHandler') -ForegroundColor Cyan

$key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($verbKey, $true)
if ($null -ne $key) {
    try {
        if ($key.GetValueNames() -contains 'ExplorerCommandHandler') {
            $key.DeleteValue('ExplorerCommandHandler', $false)
            Write-Host (T 'Com.Restore.HandlerDeleted') -ForegroundColor Green
        }
        else {
            Write-Host (T 'Com.Restore.HandlerAbsent') -ForegroundColor Gray
        }
    }
    finally { $key.Close() }
}
else {
    Write-Host (T 'Com.Restore.MenuKeyAbsent') -ForegroundColor Gray
}

# ---------------------------------------------------------------------------
Write-Host ''
Write-Host (T 'Com.Restore.StepUnregisterCom') -ForegroundColor Cyan

if ($KeepComRegistration) {
    Write-Host (T 'Com.Restore.KeepRegistration') -ForegroundColor Gray
}
else {
    $isAdmin = $false
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        $isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch { $isAdmin = $false }

    if (-not $isAdmin) {
        Write-Host (T 'Com.Restore.NotAdminSkip') -ForegroundColor Yellow
        Write-Host (T 'Com.Restore.AdminCleanupHint') -ForegroundColor Yellow
    }
    else {
        $regasmPath = ''
        $frameworkRoot = Join-Path $env:WINDIR 'Microsoft.NET\Framework64'
        foreach ($dir in @(Get-ChildItem -LiteralPath $frameworkRoot -Directory | Sort-Object Name -Descending)) {
            $candidate = Join-Path $dir.FullName 'RegAsm.exe'
            if (Test-Path -LiteralPath $candidate -PathType Leaf) { $regasmPath = $candidate; break }
        }

        if ((-not [string]::IsNullOrWhiteSpace($regasmPath)) -and (Test-Path -LiteralPath $dllPath -PathType Leaf)) {
            & $regasmPath /unregister /nologo "$dllPath"
            Write-Host (T 'Com.Restore.ComUnregistered') -ForegroundColor Green
        }
        else {
            Write-Host (T 'Com.Restore.UnregisterFilesMissing') -ForegroundColor Gray
        }
    }
}

# ---------------------------------------------------------------------------
Write-Host ''
Write-Host (T 'Com.Restore.StepRestoreCommand') -ForegroundColor Cyan

$parentDir = Split-Path -Parent $PSScriptRoot
$pickerPath = Join-Path $parentDir 'MenuPicker.ps1'

if (-not (Test-Path -LiteralPath $pickerPath -PathType Leaf)) {
    Write-Host (T 'Com.Restore.PickerNotFound' @($pickerPath)) -ForegroundColor Red
    Write-Host (T 'Com.Restore.UseInstaller') -ForegroundColor Yellow
    exit 1
}

$psPath = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
if (-not (Test-Path -LiteralPath $psPath -PathType Leaf)) {
    $cmd = Get-Command -Name 'powershell.exe' -ErrorAction SilentlyContinue
    if ($null -ne $cmd) { $psPath = $cmd.Source } else { $psPath = 'powershell.exe' }
}

$commandLine = '"' + $psPath + '" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' +
               $pickerPath + '" -Target "%V"'

$cmdKey = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($verbKey + '\command')
try {
    $cmdKey.SetValue('', $commandLine, [Microsoft.Win32.RegistryValueKind]::String)
    Write-Host (T 'Com.Restore.CommandRestored') -ForegroundColor Green
    Write-Host (T 'Com.Restore.CommandLine' @($commandLine)) -ForegroundColor Gray
}
finally { $cmdKey.Close() }

# Restore the parent display value if a previous operation cleared it.
$key2 = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($verbKey)
try {
    if ([string]::IsNullOrWhiteSpace([string]$key2.GetValue('MUIVerb', ''))) {
        $key2.SetValue('MUIVerb', (T 'App.Name'), [Microsoft.Win32.RegistryValueKind]::String)
    }
}
finally { $key2.Close() }

Write-Host ''
Write-Host (T 'Com.Restore.Complete') -ForegroundColor Green
Write-Host ''
Write-Host (T 'Com.Restore.RestartPrompt') -ForegroundColor Yellow
Write-Host (T 'Com.Common.RestartExplorerCommand') -ForegroundColor Gray
Write-Host ''

exit 0
