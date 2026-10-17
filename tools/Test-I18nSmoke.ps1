# -----------------------------------------------------------------------------
# PathAdder - i18n runtime smoke test (tools\Test-I18nSmoke.ps1)
#
# Target runtime: Windows PowerShell 5.1 (compatible with 3.0+).
# PowerShell 7-only syntax (?? / && / || / ternary / $PSStyle) is FORBIDDEN.
#
# WHY THIS FILE EXISTS - READ BEFORE MOVING ANYTHING BACK INTO ci.yml
#   GitHub Actions writes every `run:` block of a workflow into a BOM-LESS
#   temporary .ps1 and hands it to Windows PowerShell 5.1. PS 5.1 decodes a
#   BOM-less file with the active ANSI code page (GBK on a zh-CN runner), so
#   every non-ASCII literal written in the .yml arrives in the process as
#   mojibake. An assertion such as
#       if ($chinese -ne 'PATH <zh-CN text>') { ... }
#   then compares a CORRECT runtime value against a CORRUPTED literal, and the
#   step goes red while the product is perfectly healthy - precisely the
#   failure this file was created to eliminate.
#
#   The two halves of the repository encoding policy cannot be reconciled
#   inside the workflow file itself: .ps1/.cs/.md MUST carry a UTF-8 BOM,
#   .yml/.json MUST NOT (YAML and JSON parsers reject a BOM). So the literals
#   that have to survive the round trip live HERE, in a UTF-8-with-BOM .ps1,
#   and .github\workflows\ci.yml only invokes this script.
#
# WHAT IS CHECKED
#   1. App.Name resolves to the exact expected text in en-US and in zh-CN -
#      not to the raw key name, not to a fallback
#   2. Both languages load at least 500 strings
#   3. Both languages load the SAME number of strings. English is the base
#      layer, so a key missing from the zh-CN pack would otherwise be papered
#      over by its English text and stay invisible
#   4. An unsupported language (de-DE) still resolves to a real value: the
#      loader must fall back to a supported language, never to an empty string
#      and never to the raw key name
#
# USAGE
#   .\tools\Test-I18nSmoke.ps1            # exit 0 = pass, exit 1 = fail
#
# EXIT CODES
#   0 = every assertion passed
#   1 = at least one assertion failed, or the probe could not be run at all
#
#   The success path exits 0 EXPLICITLY. GitHub's PowerShell wrapper ends every
#   step with `exit $LASTEXITCODE`, so a stale non-zero $LASTEXITCODE would
#   otherwise turn a green run into a red one.
# -----------------------------------------------------------------------------

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

# -----------------------------------------------------------------------------
# 1. Locate the repository (this file lives in <repo>\tools\)
# -----------------------------------------------------------------------------

$script:Root = ''
if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
    $script:Root = Split-Path -Parent $PSScriptRoot
} else {
    $script:Root = (Get-Location).Path
}
$script:Root = [System.IO.Path]::GetFullPath($script:Root)

$script:I18nFile = Join-Path (Join-Path $script:Root 'lib') 'i18n.ps1'

# Expected values. These literals MUST stay in this BOM-carrying file - see the
# header. 'PATH Assistant' is ASCII and would survive, but keeping both
# expectations side by side in one place keeps them reviewable together.
$script:ProbeKey = 'App.Name'
$script:ExpectedEnglish = 'PATH Assistant'
$script:ExpectedChinese = 'PATH 助手'
$script:MinimumStringCount = 500
$script:UnsupportedLanguage = 'de-DE'

$script:Failures = New-Object System.Collections.ArrayList

<#
.SYNOPSIS
    Records a failed assertion and prints it immediately.
.PARAMETER Message
    One-line description of the failure.
#>
function Add-Failure {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )
    [void]$script:Failures.Add($Message)
    Write-Host ('FAIL  ' + $Message)
}

<#
.SYNOPSIS
    Prints a GitHub-Actions-friendly error annotation for a failure.
.PARAMETER Message
    One-line description of the failure.
#>
function Write-FailureAnnotation {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )
    # Escape characters that would break the workflow command syntax.
    $escaped = $Message.Replace('%', '%25').Replace("`r", '%0D').Replace("`n", '%0A')
    Write-Host ('::error title=i18n smoke::' + $escaped)
}

<#
.SYNOPSIS
    Returns the number of entries currently loaded in $global:PathAdderStrings.
.DESCRIPTION
    Read through Get-Variable so the probe reports 0 instead of throwing under
    Set-StrictMode when the loader could not populate the table.
.OUTPUTS
    Int32. 0 when the table is missing.
#>
function Get-LoadedStringCount {
    $table = Get-Variable -Name 'PathAdderStrings' -Scope 'Global' -ValueOnly -ErrorAction SilentlyContinue
    if ($null -eq $table) {
        return 0
    }
    return [int]$table.Count
}

<#
.SYNOPSIS
    Initialises i18n for one language and reports what the runtime resolved.
.PARAMETER Language
    Language tag handed to Initialize-PathAdderI18n.
.PARAMETER ClearCache
    Drop the cached language decision first, so an unsupported tag is really
    re-resolved instead of answered from the previous probe.
.OUTPUTS
    PSObject with Language (resolved tag), Text (App.Name), Count (strings).
#>
function Get-I18nProbe {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Language,

        [Parameter(Mandatory = $false)]
        [switch]$ClearCache
    )

    if ($ClearCache) {
        $global:PathAdderLanguage = $null
        $env:PATHADDER_LANG = ''
    }

    $resolved = Initialize-PathAdderI18n -Language $Language

    return (New-Object PSObject -Property @{
        Language = [string]$resolved
        Text     = [string](T $script:ProbeKey)
        Count    = Get-LoadedStringCount
    })
}

# -----------------------------------------------------------------------------
# 2. Load the module under test
# -----------------------------------------------------------------------------

Write-Host '========================================================='
Write-Host ' PathAdder - i18n runtime smoke test'
Write-Host '========================================================='
Write-Host ('Repo root   : ' + $script:Root)
Write-Host ('i18n module : ' + $script:I18nFile)
Write-Host ''

if (-not (Test-Path -LiteralPath $script:I18nFile -PathType Leaf)) {
    Add-Failure ('lib\i18n.ps1 not found at: ' + $script:I18nFile)
    Write-FailureAnnotation ('lib\i18n.ps1 not found at: ' + $script:I18nFile)
    exit 1
}

# Seed every global that lib\i18n.ps1 reads at load time. Under Set-StrictMode
# the module's own top-level test of $global:PathAdderRootDirectory would throw
# a "variable is not set" error when the variable does not exist yet. Seeding
# also states this probe's starting conditions out loud: no language decision
# and no string table are inherited from whoever called us.
$global:PathAdderRootDirectory = ''
$global:PathAdderLanguage = $null
$global:PathAdderStrings = $null

# A persisted preference must never be able to leak into this probe.
$env:PATHADDER_LANG = ''

try {
    . $script:I18nFile
} catch {
    Add-Failure ('Cannot dot-source lib\i18n.ps1: ' + $_.Exception.Message)
    Write-FailureAnnotation ('Cannot dot-source lib\i18n.ps1: ' + $_.Exception.Message)
    exit 1
}

# -----------------------------------------------------------------------------
# 3. Probe: English, Chinese, and one unsupported language
# -----------------------------------------------------------------------------

# Register the application root explicitly, so the loader never has to guess
# the lang directory by walking up from the current working directory -
# i18n.ps1's own comment says the same about this variable. This keeps the
# probe correct no matter which directory CI happens to start the step in.
$global:PathAdderRootDirectory = $script:Root

$english = Get-I18nProbe -Language 'en-US'
$chinese = Get-I18nProbe -Language 'zh-CN'
$fallback = Get-I18nProbe -Language $script:UnsupportedLanguage -ClearCache

Write-Host ('en-US     -> resolved ' + $english.Language + ' | ' + $script:ProbeKey +
            ' = "' + $english.Text + '" | strings = ' + $english.Count)
Write-Host ('zh-CN     -> resolved ' + $chinese.Language + ' | ' + $script:ProbeKey +
            ' = "' + $chinese.Text + '" | strings = ' + $chinese.Count)
Write-Host ($script:UnsupportedLanguage + '     -> resolved ' + $fallback.Language + ' | ' + $script:ProbeKey +
            ' = "' + $fallback.Text + '" | strings = ' + $fallback.Count)
Write-Host ''

# --- 3a. Exact expected text ------------------------------------------------
if ($english.Text -cne $script:ExpectedEnglish) {
    Add-Failure ("App.Name in en-US is '" + $english.Text + "', expected '" + $script:ExpectedEnglish + "'")
}
if ($chinese.Text -cne $script:ExpectedChinese) {
    Add-Failure ("App.Name in zh-CN is '" + $chinese.Text + "', expected '" + $script:ExpectedChinese + "'")
}

# --- 3b. Both languages must be fully populated and identical in size -------
if ($english.Count -lt $script:MinimumStringCount) {
    Add-Failure ('Only ' + $english.Count + ' strings loaded for en-US, expected at least ' + $script:MinimumStringCount)
}
if ($chinese.Count -lt $script:MinimumStringCount) {
    Add-Failure ('Only ' + $chinese.Count + ' strings loaded for zh-CN, expected at least ' + $script:MinimumStringCount)
}
if ($english.Count -ne $chinese.Count) {
    Add-Failure ('String counts differ: en-US has ' + $english.Count + ', zh-CN has ' + $chinese.Count)
}

# --- 3c. Never silently degrade to the raw key name -------------------------
if ($english.Text -ceq $script:ProbeKey) {
    Add-Failure ('en-US resolved ' + $script:ProbeKey + ' to the raw key name - no language pack was loaded')
}
if ($chinese.Text -ceq $script:ProbeKey) {
    Add-Failure ('zh-CN resolved ' + $script:ProbeKey + ' to the raw key name - no language pack was loaded')
}

# --- 3d. An unsupported tag must still land on a supported language ---------
if ([string]::IsNullOrWhiteSpace($fallback.Text)) {
    Add-Failure ($script:UnsupportedLanguage + ' resolved ' + $script:ProbeKey + ' to an empty string')
} elseif ($fallback.Text -ceq $script:ProbeKey) {
    Add-Failure ($script:UnsupportedLanguage + ' resolved ' + $script:ProbeKey + ' to the raw key name')
} elseif (($fallback.Text -cne $english.Text) -and ($fallback.Text -cne $chinese.Text)) {
    Add-Failure ($script:UnsupportedLanguage + ' resolved ' + $script:ProbeKey + " to '" + $fallback.Text +
                 "', which is neither the en-US nor the zh-CN value")
}

# -----------------------------------------------------------------------------
# 4. Verdict
# -----------------------------------------------------------------------------

if ($script:Failures.Count -eq 0) {
    Write-Host ('RESULT: PASS - en-US and zh-CN resolve ' + $script:ProbeKey + ' correctly with ' +
                $english.Count + ' strings each; ' + $script:UnsupportedLanguage + ' falls back to ' +
                $fallback.Language + '.')
    Write-Host 'i18n smoke test OK.'
    exit 0
}

Write-Host ('RESULT: FAIL - ' + $script:Failures.Count + ' assertion(s) failed.')
foreach ($failure in $script:Failures) {
    Write-FailureAnnotation $failure
}
exit 1
