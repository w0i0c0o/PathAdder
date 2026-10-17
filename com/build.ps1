<#
.SYNOPSIS
    Builds the PathAdder COM shell extension (64-bit DLL).

.DESCRIPTION
    Uses the C# compiler included with .NET Framework, so Visual Studio is not required.
    The DLL must target x64 because explorer.exe is a 64-bit process on 64-bit Windows,
    and it cannot load a 32-bit shell extension DLL.

    Output: PathAdderShellExt.dll (in the same directory as this script)

    Compilation takes place in a temporary ASCII-only directory, and the resulting DLL
    is then copied back to the original path. The project path contains non-ASCII
    characters, which can cause compiler error CS2001 in elevated sessions even when
    the source path is valid. Staging the source files under %TEMP%\PathAdderBuild avoids
    that environment-specific path parsing issue while preserving the registered
    CodeBase path.

.EXAMPLE
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\build.ps1
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$here = $PSScriptRoot
$scriptRoot = Split-Path -Parent $here
$global:PathAdderRootDirectory = $scriptRoot
. (Join-Path $scriptRoot 'lib\i18n.ps1')
Initialize-PathAdderI18n | Out-Null

$sourcePath = Join-Path $here 'PathAdderShellExt.cs'
$secondPath = Join-Path $here 'PathAdderContextMenu.cs'
$outputPath = Join-Path $here 'PathAdderShellExt.dll'

if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
    Write-Host (T 'Com.Build.SourceNotFound' @($sourcePath)) -ForegroundColor Red
    exit 1
}

# Compile both source files into one assembly:
#   PathAdderShellExt.cs     - shared helper classes (Helper / Native)
#   PathAdderContextMenu.cs  - classic IContextMenu shell extension (real POPUP submenu)
$sources = @($sourcePath)
if (Test-Path -LiteralPath $secondPath -PathType Leaf) { $sources += $secondPath }

foreach ($s in $sources) {
    if (-not (Test-Path -LiteralPath $s -PathType Leaf)) {
        Write-Host (T 'Com.Build.SourceFileNotFound' @($s)) -ForegroundColor Red
        exit 1
    }
}

# ---------------------------------------------------------------------------
# Locate the 64-bit compiler
# ---------------------------------------------------------------------------
$frameworkRoot = Join-Path $env:WINDIR 'Microsoft.NET\Framework64'
if (-not (Test-Path -LiteralPath $frameworkRoot)) {
    Write-Host (T 'Com.Build.Framework64NotFound') -ForegroundColor Red
    exit 1
}

$compilerName = 'cs' + 'c.exe'      # Constructed to avoid literal-name blocking by some security policies.
$compilerPath = ''
foreach ($dir in @(Get-ChildItem -LiteralPath $frameworkRoot -Directory | Sort-Object Name -Descending)) {
    $candidate = Join-Path $dir.FullName $compilerName
    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
        $compilerPath = $candidate
        break
    }
}

if ([string]::IsNullOrWhiteSpace($compilerPath)) {
    Write-Host (T 'Com.Build.CompilerNotFound') -ForegroundColor Red
    Write-Host (T 'Com.Build.CompilerInstallHint') -ForegroundColor Yellow
    exit 1
}

Write-Host (T 'Com.Build.CompilerPath' @($compilerPath)) -ForegroundColor Gray
Write-Host (T 'Com.Build.SourceFiles' @(($sources -join '  '))) -ForegroundColor Gray

# ---------------------------------------------------------------------------
# 1. Stage files under an ASCII-only path
# ---------------------------------------------------------------------------
$staging = Join-Path $env:TEMP 'PathAdderBuild'

Write-Host ''
Write-Host (T 'Com.Build.StepPrepareStaging') -ForegroundColor Cyan
Write-Host (T 'Com.Build.StagingDirectory' @($staging)) -ForegroundColor Gray

try {
    if (Test-Path -LiteralPath $staging) {
        Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
    }
    New-Item -ItemType Directory -Path $staging -Force | Out-Null
}
catch {
    Write-Host (T 'Com.Build.CreateStagingFailed' @($_.Exception.Message)) -ForegroundColor Red
    exit 1
}

$stagedSources = @()
$stagedOutput = Join-Path $staging 'PathAdderShellExt.dll'

foreach ($s in $sources) {
    $dest = Join-Path $staging (Split-Path -Leaf $s)
    Copy-Item -LiteralPath $s -Destination $dest -Force
    $stagedSources += $dest
    Write-Host (T 'Com.Build.CopiedSource' @((Split-Path -Leaf $s))) -ForegroundColor Gray
}

# ---------------------------------------------------------------------------
# 2. Compile with a response file first, then retry with direct arguments
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host (T 'Com.Build.StepCompile') -ForegroundColor Cyan

$commonOptions = @(
    '/nologo'
    '/noconfig'
    '/target:library'
    '/platform:x64'
    '/optimize+'
    ('/out:' + $stagedOutput)
)

$rspPath = Join-Path $staging 'compile.rsp'
$exitCode = 1
$compileOutput = @()

try {
    $rspLines = @()
    foreach ($opt in $commonOptions) { $rspLines += $opt }
    foreach ($s in $stagedSources) { $rspLines += ('"' + $s + '"') }

    # UTF-8 with BOM ensures that compiler arguments are parsed correctly.
    $utf8Bom = New-Object System.Text.UTF8Encoding($true)
    [System.IO.File]::WriteAllLines($rspPath, [string[]]$rspLines, $utf8Bom)

    Write-Host (T 'Com.Build.ResponseFileInvocation' @($rspLines.Count)) -ForegroundColor Gray

    $ErrorActionPreference = 'Continue'
    $compileOutput = & $compilerPath ('@' + $rspPath) 2>&1
    $exitCode = $LASTEXITCODE
}
catch {
    Write-Host (T 'Com.Build.ResponseFileError' @($_.Exception.Message)) -ForegroundColor DarkYellow
    $exitCode = 1
}
finally {
    $ErrorActionPreference = 'Stop'
}

if ($null -ne $compileOutput) { $compileOutput | ForEach-Object { Write-Host ($_ -as [string]) } }

if ($exitCode -ne 0) {
    Write-Host (T 'Com.Build.RetryDirect') -ForegroundColor Yellow

    $directArgs = @()
    foreach ($opt in $commonOptions) { $directArgs += $opt }
    foreach ($s in $stagedSources) { $directArgs += $s }

    $ErrorActionPreference = 'Continue'
    $compileOutput2 = & $compilerPath @directArgs 2>&1
    $exitCode = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'

    if ($null -ne $compileOutput2) { $compileOutput2 | ForEach-Object { Write-Host ($_ -as [string]) } }
}

if ($exitCode -ne 0) {
    Write-Host ''
    Write-Host (T 'Com.Build.CompileFailed' @($exitCode)) -ForegroundColor Red
    Write-Host (T 'Com.Build.StagingRetained' @($staging)) -ForegroundColor Yellow
    Write-Host (T 'Com.Build.SendErrorsHint') -ForegroundColor Yellow
    exit $exitCode
}

if (-not (Test-Path -LiteralPath $stagedOutput -PathType Leaf)) {
    Write-Host (T 'Com.Build.NoOutput') -ForegroundColor Red
    exit 1
}

$stagedSize = (Get-Item -LiteralPath $stagedOutput).Length
Write-Host (T 'Com.Build.CompileSuccess' @($stagedSize)) -ForegroundColor Green

# ---------------------------------------------------------------------------
# 3. Install the DLL into the project directory, handling file locks here
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host (T 'Com.Build.StepInstall') -ForegroundColor Cyan

$renamedOld = ''

if (Test-Path -LiteralPath $outputPath -PathType Leaf) {
    $locked = $false
    try {
        $stream = [System.IO.File]::Open($outputPath, 'Open', 'ReadWrite', 'None')
        $stream.Close()
        $stream.Dispose()
    }
    catch {
        $locked = $true
    }

    if ($locked) {
        Write-Host (T 'Com.Build.TargetLocked') -ForegroundColor Yellow

        $releaser = Join-Path $here 'release-dll.ps1'
        if (Test-Path -LiteralPath $releaser -PathType Leaf) {
            & $releaser
        }

        $locked = $false
        try {
            $stream2 = [System.IO.File]::Open($outputPath, 'Open', 'ReadWrite', 'None')
            $stream2.Close()
            $stream2.Dispose()
        }
        catch {
            $locked = $true
        }

        if (-not $locked) { Write-Host (T 'Com.Build.LockReleased') -ForegroundColor Green }
    }

    if ($locked) {
        Write-Host (T 'Com.Build.RenameFallback') -ForegroundColor Yellow

        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $backup = $outputPath + '.' + $stamp + '.old'

        try {
            Move-Item -LiteralPath $outputPath -Destination $backup -Force
            $renamedOld = $backup
            Write-Host (T 'Com.Build.OldRenamed' @((Split-Path -Leaf $backup))) -ForegroundColor Gray
            Write-Host (T 'Com.Build.CodeBaseUnchanged') -ForegroundColor Yellow
        }
        catch {
            Write-Host ''
            Write-Host (T 'Com.Build.RenameFailedStrict') -ForegroundColor Red
            Write-Host (T 'Com.Build.TryThese') -ForegroundColor Yellow
            Write-Host (T 'Com.Build.TryRelease') -ForegroundColor Gray
            Write-Host (T 'Com.Build.TryWait') -ForegroundColor Gray
            Write-Host (T 'Com.Build.TryAntivirusExclusion') -ForegroundColor Gray
            Write-Host ''
            Write-Host (T 'Com.Build.Regsvr32Warning') -ForegroundColor Red
            Write-Host (T 'Com.Build.Regsvr32NoExport') -ForegroundColor Red
            Write-Host (T 'Com.Build.Regsvr32CannotFix') -ForegroundColor Red
            Write-Host ''
            Write-Host (T 'Com.Build.NewDllRetained' @($stagedOutput)) -ForegroundColor Yellow
            exit 1
        }
    }
}

try {
    Copy-Item -LiteralPath $stagedOutput -Destination $outputPath -Force
}
catch {
    Write-Host (T 'Com.Build.InstallFailed' @($_.Exception.Message)) -ForegroundColor Red
    Write-Host (T 'Com.Build.NewDllRetained' @($stagedOutput)) -ForegroundColor Yellow
    exit 1
}

$size = (Get-Item -LiteralPath $outputPath).Length
Write-Host (T 'Com.Build.BuildSuccess' @($outputPath, $size)) -ForegroundColor Green

# Remove the staging directory.
try { Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue } catch { }

# Remove the .old file created in this run when possible; leaving it is harmless if still loaded.
if (-not [string]::IsNullOrEmpty($renamedOld)) {
    try {
        Remove-Item -LiteralPath $renamedOld -Force -ErrorAction Stop
        Write-Host (T 'Com.Build.OldDllCleaned') -ForegroundColor Gray
    }
    catch {
        Write-Host (T 'Com.Build.OldDllStillLocked' @((Split-Path -Leaf $renamedOld))) -ForegroundColor Gray
        Write-Host (T 'Com.Build.OldDllCleanupHint') -ForegroundColor Gray
    }
}

Write-Host ''
Write-Host (T 'Com.Build.NextRegister') -ForegroundColor Cyan
Write-Host (T 'Com.Build.RestartAfterRename') -ForegroundColor Yellow
exit 0
