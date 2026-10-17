<#
.SYNOPSIS
    Rebuilds and registers the COM extension while handling a locked PathAdderShellExt.dll.

.DESCRIPTION
    After a process such as explorer.exe loads a .NET assembly with LoadLibrary, Windows
    prevents other processes from overwriting it. This is expected COM loading behavior,
    not a script defect, and regsvr32 /u cannot release the lock.

    The script performs these operations:
      1. Checks whether the DLL is locked.
      2. If locked, restarts Explorer and checks again. This closes folder windows.
      3. If still locked, reports likely antivirus or synchronization scanning.
      4. Builds, registers, and prompts the user to restart Explorer for verification.

.NOTES
    Using regsvr32 /u with a .NET assembly is incorrect. The expected missing
    DllUnregisterServer entry-point error occurs because .NET assemblies do not export
    DllRegisterServer or DllUnregisterServer; mscoree.dll acts as their proxy. Use
    RegAsm.exe instead:
        Unregister: RegAsm.exe /unregister "path\to.dll"
        Register:   RegAsm.exe /codebase  "path\to.dll"
    This script invokes RegAsm through the registration script.

.EXAMPLE
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\rebuild.ps1
#>

[CmdletBinding()]
param(
    # Restart Explorer without prompting.
    [switch]$RestartExplorer,
    # Build without registering.
    [switch]$SkipRegister
)

$ErrorActionPreference = 'Stop'

$comDirectory = $PSScriptRoot
$scriptRoot = Split-Path -Parent $comDirectory
$global:PathAdderRootDirectory = $scriptRoot
. (Join-Path $scriptRoot 'lib\i18n.ps1')
Initialize-PathAdderI18n | Out-Null

$dllPath = Join-Path $PSScriptRoot 'PathAdderShellExt.dll'
$dllName = Split-Path -Leaf $dllPath

function Test-DllLocked {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    try {
        $stream = [System.IO.File]::Open($Path, 'Open', 'ReadWrite', 'None')
        $stream.Close()
        $stream.Dispose()
        return $false
    }
    catch {
        return $true
    }
}

function Get-DllHolder {
    param([string]$Name)

    # tasklist /m lists processes that loaded the module into their address spaces.
    $result = @()
    try {
        $raw = & tasklist.exe /m $Name 2>$null
        if ($raw) {
            foreach ($line in $raw) {
                if ($line -match '^\s*([^\s]+\.exe)\s+(\d+)') {
                    $result += ($matches[1] + ' (pid=' + $matches[2] + ')')
                }
            }
        }
    }
    catch { }
    return $result
}

Write-Host (T 'Com.Rebuild.StepCheck') -ForegroundColor Cyan

if (-not (Test-DllLocked -Path $dllPath)) {
    Write-Host (T 'Com.Rebuild.DllFree') -ForegroundColor Green
}
else {
    Write-Host (T 'Com.Rebuild.DllLocked') -ForegroundColor Yellow

    $holders = Get-DllHolder -Name $dllName
    if ($holders.Count -gt 0) {
        Write-Host (T 'Com.Rebuild.Holders') -ForegroundColor Yellow
        foreach ($h in $holders) { Write-Host (T 'Com.Rebuild.HolderItem' @($h)) -ForegroundColor Gray }
    }
    else {
        Write-Host (T 'Com.Rebuild.NoModuleHolder') -ForegroundColor Gray
        Write-Host (T 'Com.Rebuild.LikelyScanner') -ForegroundColor Gray
    }

    Write-Host ''
    Write-Host (T 'Com.Rebuild.RestartSolution') -ForegroundColor Yellow

    $go = $RestartExplorer
    if (-not $go) {
        Write-Host (T 'Com.Rebuild.WindowWarning') -ForegroundColor Yellow
        $ans = Read-Host (T 'Com.Rebuild.RestartPrompt')
        $go = ($ans -eq 'y' -or $ans -eq 'Y')
    }

    if ($go) {
        Get-Process explorer -ErrorAction SilentlyContinue | Stop-Process -Force
        Start-Sleep -Seconds 3
        Start-Process explorer.exe
        Start-Sleep -Seconds 4
        Write-Host (T 'Com.Rebuild.ExplorerRestarted') -ForegroundColor Green

        if (Test-DllLocked -Path $dllPath) {
            Write-Host ''
            Write-Host (T 'Com.Rebuild.StillLocked') -ForegroundColor Red
            Write-Host (T 'Com.Rebuild.HowToHandle') -ForegroundColor Yellow
            Write-Host (T 'Com.Rebuild.RetryWait') -ForegroundColor Gray
            Write-Host (T 'Com.Rebuild.MoveToAsciiPath') -ForegroundColor Gray
            Write-Host (T 'Com.Rebuild.AddAntivirusExclusion') -ForegroundColor Gray

            if (-not $SkipRegister) {
                Write-Host ''
                Write-Host (T 'Com.Rebuild.OldDllHint') -ForegroundColor Gray
                Write-Host (T 'Com.Common.RegisterComSkipBuildCommand') -ForegroundColor Gray
            }
            exit 1
        }
        Write-Host (T 'Com.Rebuild.LockReleased') -ForegroundColor Green
    }
    else {
        Write-Host (T 'Com.Rebuild.Cancelled') -ForegroundColor Yellow
        Write-Host (T 'Com.Common.RestartExplorerCommand') -ForegroundColor Gray
        exit 1
    }
}

# ---------------------------------------------------------------------------
Write-Host ''
Write-Host (T 'Com.Rebuild.StepBuild') -ForegroundColor Cyan
& (Join-Path $PSScriptRoot 'build.ps1')
if ($LASTEXITCODE -ne 0) {
    Write-Host (T 'Com.Rebuild.BuildFailed' @($LASTEXITCODE)) -ForegroundColor Red
    exit $LASTEXITCODE
}

# ---------------------------------------------------------------------------
if ($SkipRegister) {
    Write-Host ''
    Write-Host (T 'Com.Rebuild.SkipRegister') -ForegroundColor Gray
    exit 0
}

Write-Host ''
Write-Host (T 'Com.Rebuild.StepRegister') -ForegroundColor Cyan
& (Join-Path $PSScriptRoot 'register-com.ps1') -SkipBuild
if ($LASTEXITCODE -ne 0) {
    Write-Host (T 'Com.Rebuild.RegisterFailed' @($LASTEXITCODE)) -ForegroundColor Red
    exit $LASTEXITCODE
}

# ---------------------------------------------------------------------------
Write-Host ''
Write-Host (T 'Com.Rebuild.StepComplete') -ForegroundColor Cyan
Write-Host ''
Write-Host (T 'Com.Rebuild.RestartAndTest') -ForegroundColor White
Write-Host (T 'Com.Rebuild.ShareLog') -ForegroundColor White
Write-Host ''
Write-Host (T 'Com.Rebuild.RestoreHint') -ForegroundColor Gray
Write-Host (T 'Com.Common.RestoreMenuCommand') -ForegroundColor Gray
Write-Host ''
exit 0
