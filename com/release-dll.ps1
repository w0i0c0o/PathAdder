<#
.SYNOPSIS
    Releases file locks on PathAdderShellExt.dll before building or re-registering it.

.DESCRIPTION
    After explorer.exe loads the DLL, it holds the file with
    FILE_SHARE_READ | FILE_SHARE_DELETE. This allows renaming but prevents writing or
    replacing the DLL at its current path.

    This script releases the lock rather than working around it:
      1. Uses tasklist /m to find processes that loaded the module.
      2. Terminates each holder except System, the Idle process, and this script.
      3. Restarts Explorer immediately if it was terminated.
      4. Polls for write access for up to 12 seconds.

    Do not use regsvr32 /u to unload this DLL. It is a .NET assembly without a
    DllUnregisterServer export, so regsvr32 reports a missing entry point and does not
    release the file lock.

.EXAMPLE
    # Release the DLL and restart Explorer when needed.
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\release-dll.ps1

    # Release the DLL without restarting Explorer.
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\release-dll.ps1 -NoRestartExplorer
#>

[CmdletBinding()]
param(
    [switch]$NoRestartExplorer
)

$ErrorActionPreference = 'Continue'

$comDirectory = $PSScriptRoot
$scriptRoot = Split-Path -Parent $comDirectory
$global:PathAdderRootDirectory = $scriptRoot
. (Join-Path $scriptRoot 'lib\i18n.ps1')
Initialize-PathAdderI18n | Out-Null

$dllPath = Join-Path $PSScriptRoot 'PathAdderShellExt.dll'
$moduleName = 'PathAdderShellExt'

function Test-DllFree {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $true }
    try {
        $stream = [System.IO.File]::Open($Path, 'Open', 'ReadWrite', 'None')
        $stream.Close()
        $stream.Dispose()
        return $true
    }
    catch {
        return $false
    }
}

# ---------------------------------------------------------------------------
Write-Host (T 'Com.Release.CheckHeader') -ForegroundColor Cyan

if (-not (Test-Path -LiteralPath $dllPath -PathType Leaf)) {
    Write-Host (T 'Com.Release.DllMissing' @($dllPath)) -ForegroundColor Gray
    Write-Host (T 'Com.Release.NothingToRelease') -ForegroundColor Green
    exit 0
}

if (Test-DllFree $dllPath) {
    Write-Host (T 'Com.Release.DllFree') -ForegroundColor Green
    exit 0
}

Write-Host (T 'Com.Release.Releasing') -ForegroundColor Yellow

# ---------------------------------------------------------------------------
# 1. Find processes that loaded the module
# ---------------------------------------------------------------------------
$holderPids = @()

try {
    $tasklist = Join-Path $env:WINDIR 'System32\tasklist.exe'
    if (Test-Path -LiteralPath $tasklist -PathType Leaf) {
        # /m <module> is faster than enumerating every loaded module.
        $lines = & $tasklist /m $moduleName /fo csv /nh 2>$null

        foreach ($line in $lines) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            if ($line -notmatch $moduleName) { continue }

            # CSV example: "explorer.exe","2096","PathAdderShellExt.dll, ..."
            $fields = $line.Split(',')
            if ($fields.Count -lt 2) { continue }

            $pidText = $fields[1].Trim().Trim('"')
            $candidate = 0
            if ([int]::TryParse($pidText, [ref]$candidate)) {
                if ($candidate -gt 4 -and $candidate -ne $PID) { $holderPids += $candidate }
            }
        }
    }
}
catch {
    Write-Host (T 'Com.Release.EnumerateFailed' @($_.Exception.Message)) -ForegroundColor DarkYellow
}

$holderPids = @($holderPids | Sort-Object -Unique)

if ($holderPids.Count -eq 0) {
    Write-Host (T 'Com.Release.NoHolderFound') -ForegroundColor Gray
    Write-Host (T 'Com.Release.AssumeExplorer') -ForegroundColor Gray
}
else {
    foreach ($p in $holderPids) {
        $procName = T 'Com.Release.UnknownProcess'
        try { $procName = (Get-Process -Id $p -ErrorAction Stop).ProcessName } catch { }
        Write-Host (T 'Com.Release.Holder' @($procName, $p)) -ForegroundColor Gray
    }
}

# ---------------------------------------------------------------------------
# 2. Terminate holders
# ---------------------------------------------------------------------------
$killedAny = $false
foreach ($p in $holderPids) {
    try {
        Stop-Process -Id $p -Force -ErrorAction Stop
        Write-Host (T 'Com.Release.TerminatedPid' @($p)) -ForegroundColor Gray
        $killedAny = $true
    }
    catch {
        Write-Host (T 'Com.Release.TerminatePidFailed' @($p, $_.Exception.Message)) -ForegroundColor DarkYellow
    }
}

# Explorer is the holder in most cases, so restart it regardless of the module query.
$explorerWasRunning = $false
try { $explorerWasRunning = ($null -ne (Get-Process -Name explorer -ErrorAction Stop)) } catch { $explorerWasRunning = $false }

if ($explorerWasRunning) {
    try {
        Get-Process -Name explorer -ErrorAction Stop | Stop-Process -Force -ErrorAction Stop
        Write-Host (T 'Com.Release.TerminatedExplorer') -ForegroundColor Gray
        $killedAny = $true
    }
    catch {
        Write-Host (T 'Com.Release.TerminateExplorerFailed' @($_.Exception.Message)) -ForegroundColor DarkYellow
    }
}

# ---------------------------------------------------------------------------
# 3. Restart Explorer so the desktop returns
# ---------------------------------------------------------------------------
if ($killedAny -and $explorerWasRunning -and (-not $NoRestartExplorer)) {
    Start-Sleep -Milliseconds 800
    try {
        Start-Process -FilePath 'explorer.exe' | Out-Null
        Write-Host (T 'Com.Release.ExplorerRestarted') -ForegroundColor Gray
    }
    catch {
        Write-Host (T 'Com.Release.ExplorerRestartFailed') -ForegroundColor Yellow
    }
}
elseif ($killedAny -and $explorerWasRunning) {
    Write-Host (T 'Com.Release.ExplorerRestartSkipped') -ForegroundColor Yellow
}

# ---------------------------------------------------------------------------
# 4. Wait until the file is writable
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host (T 'Com.Release.WaitHeader') -ForegroundColor Cyan

$elapsed = 0.0
while ($elapsed -lt 12.0) {
    if (Test-DllFree $dllPath) { break }
    Start-Sleep -Milliseconds 400
    $elapsed = $elapsed + 0.4
}

if (Test-DllFree $dllPath) {
    Write-Host (T 'Com.Release.ReleasedAfterSeconds' @([math]::Round($elapsed, 1))) -ForegroundColor Green
    exit 0
}

Write-Host ''
Write-Host (T 'Com.Release.StillLocked') -ForegroundColor Red
Write-Host (T 'Com.Release.AntivirusCause') -ForegroundColor Gray
Write-Host (T 'Com.Release.OtherHostCause') -ForegroundColor Gray
Write-Host (T 'Com.Release.SignOutCause') -ForegroundColor Gray
Write-Host ''
exit 1
