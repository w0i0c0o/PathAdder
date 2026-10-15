<#
.SYNOPSIS
    Diagnoses a cascading submenu that does not expand on hover.

.DESCRIPTION
    Rebuilds the logging DLL, registers it, switches the menu, and prints the runtime log
    after the user tests hover expansion. The log distinguishes these cases:
      A. Explorer never creates the COM object because the handler is ignored.
      B. Explorer creates the object but never calls EnumSubCommands.
      C. Explorer creates the enumerator but submenu construction fails.

    This script restarts Explorer unless -NoRestart is specified. All open folder windows
    are closed during the restart.

.EXAMPLE
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\diag-cascade.ps1
#>

[CmdletBinding()]
param(
    # Do not restart Explorer automatically; the caller must restart it before testing.
    [switch]$NoRestart
)

$ErrorActionPreference = 'Stop'

$comDirectory = $PSScriptRoot
$scriptRoot = Split-Path -Parent $comDirectory
$global:PathAdderRootDirectory = $scriptRoot
. (Join-Path $scriptRoot 'lib\i18n.ps1')
Initialize-PathAdderI18n | Out-Null

$logPath = Join-Path $env:TEMP 'PathAdderShellExt.log'

# ---------------------------------------------------------------------------
Write-Host (T 'Com.Diag.StepClearLog') -ForegroundColor Cyan
if (Test-Path -LiteralPath $logPath -PathType Leaf) {
    Remove-Item -LiteralPath $logPath -Force
    Write-Host (T 'Com.Diag.OldLogDeleted' @($logPath)) -ForegroundColor Gray
}
else {
    Write-Host (T 'Com.Diag.NoOldLog') -ForegroundColor Gray
}

# ---------------------------------------------------------------------------
Write-Host ''
Write-Host (T 'Com.Diag.StepBuildRegister') -ForegroundColor Cyan
& (Join-Path $PSScriptRoot 'register-com.ps1')
if ($LASTEXITCODE -ne 0) {
    Write-Host (T 'Com.Diag.RegisterFailed' @($LASTEXITCODE)) -ForegroundColor Red
    exit $LASTEXITCODE
}

# ---------------------------------------------------------------------------
Write-Host ''
Write-Host (T 'Com.Diag.StepRestartExplorer') -ForegroundColor Cyan

if ($NoRestart) {
    Write-Host (T 'Com.Diag.RestartSkipped') -ForegroundColor Yellow
    Write-Host (T 'Com.Common.RestartExplorerCommand') -ForegroundColor Gray
}
else {
    Write-Host (T 'Com.Diag.RestartWarning') -ForegroundColor Yellow
    $null = Read-Host (T 'Com.Diag.ContinuePrompt')
    Get-Process explorer -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Seconds 2
    Start-Process explorer.exe
    Start-Sleep -Seconds 3
    Write-Host (T 'Com.Diag.ExplorerRestarted') -ForegroundColor Green
}

# ---------------------------------------------------------------------------
Write-Host ''
Write-Host (T 'Com.Diag.StepTestAndReadLog') -ForegroundColor Cyan
Write-Host ''
Write-Host (T 'Com.Diag.TestInstruction1') -ForegroundColor White
Write-Host (T 'Com.Diag.TestInstruction2' @((T 'App.Name'))) -ForegroundColor White
Write-Host ''
$null = Read-Host (T 'Com.Diag.TestDonePrompt')

Write-Host ''
Write-Host (T 'Com.Diag.LogPath' @($logPath)) -ForegroundColor Gray
Write-Host ''

if (Test-Path -LiteralPath $logPath -PathType Leaf) {
    $lines = Get-Content -LiteralPath $logPath
    Write-Host (T 'Com.Diag.LogCount' @($lines.Count)) -ForegroundColor Green
    Write-Host (T 'Com.Diag.Separator') -ForegroundColor Gray
    $lines | ForEach-Object { Write-Host (T 'Com.Diag.LogLine' @($_)) }
    Write-Host (T 'Com.Diag.Separator') -ForegroundColor Gray
    Write-Host ''

    # These patterns are matched against the text that Helper.Log writes from
    # PathAdderShellExt.cs, so they MUST stay in sync with those log strings.
    # The C# log messages are in English now; keep these patterns English too.
    $hasCtor = ($lines | Where-Object { $_ -like '*PathAdderCommand ctor*' }).Count -gt 0
    $hasEnum = ($lines | Where-Object { $_ -like '*EnumSubCommands called*' }).Count -gt 0
    $hasNext = ($lines | Where-Object { $_ -like '*SubCommandEnum.Next*' }).Count -gt 0

    Write-Host (T 'Com.Diag.AnalysisLabel') -ForegroundColor Cyan
    if (-not $hasCtor) {
        Write-Host (T 'Com.Diag.CaseA') -ForegroundColor Red
        Write-Host (T 'Com.Diag.CaseACheck') -ForegroundColor Yellow
    }
    elseif (-not $hasEnum) {
        Write-Host (T 'Com.Diag.CaseB') -ForegroundColor Red
        Write-Host (T 'Com.Diag.CaseBReason') -ForegroundColor Yellow
    }
    elseif (-not $hasNext) {
        Write-Host (T 'Com.Diag.CaseC') -ForegroundColor Red
        Write-Host (T 'Com.Diag.CaseCReason') -ForegroundColor Yellow
    }
    else {
        Write-Host (T 'Com.Diag.Normal') -ForegroundColor Green
        Write-Host (T 'Com.Diag.RenderIssue') -ForegroundColor Yellow
    }
}
else {
    Write-Host (T 'Com.Diag.NoLog') -ForegroundColor Red
}

Write-Host ''
Write-Host (T 'Com.Diag.RestoreHint') -ForegroundColor Gray
Write-Host (T 'Com.Common.RestoreMenuCommand') -ForegroundColor Gray
Write-Host ''
exit 0
