# -----------------------------------------------------------------------------
# PathAdder - Language pack parity checker (tools\Test-LanguagePacks.ps1)
#
# Target runtime: Windows PowerShell 5.1 (compatible with 3.0+).
# PowerShell 7-only syntax (?? / && / || / ternary / $PSStyle) is FORBIDDEN.
#
# PURPOSE
#   Every language pack under lang\<language>\ consists of the same set of
#   shards (core, shell, picker, gui, cli, setup, verify, com). If a translator
#   adds a key to one language but forgets another, the missing language
#   silently falls back to English at runtime - a bug nobody notices until a
#   user reports a screen that is half English.
#
#   This tool compares, SHARD BY SHARD, the key set of every supported language
#   against the reference language (en-US) and prints the EXACT key names that
#   are missing or extra. It is a verification tool, not a runtime dependency:
#   it lives in tools\ and is never shipped in the release zip.
#
# WHAT IS COMPARED
#   1. Language directories present on disk  <->  $script:PathAdderSupportedLanguages
#      read from lib\i18n.ps1 (never hardcoded here, so adding a language only
#      requires editing i18n.ps1)
#   2. Shard file sets: all languages must provide the same shard files as the
#      reference language
#   3. Per-shard key sets: all languages must provide the same keys as the
#      reference language
#   4. Duplicate keys inside a single shard (a duplicate means one of the two
#      translations is lost - usually a merge accident)
#
# HOW THE PACKS ARE READ
#   Each shard is executed in an isolated child scope where $PathAdderStrings is
#   pre-set to an EMPTY hashtable; the shard assigns its own hashtable and we
#   read the keys back. This is exactly how lib\i18n.ps1 loads them, so the
#   check sees the same key set the product sees. Shards are never dot-sourced
#   into the caller's scope: no global state is polluted, no function from a
#   pack can leak out.
#
# USAGE
#   .\tools\Test-LanguagePacks.ps1                 # report only, always exit 0
#   .\tools\Test-LanguagePacks.ps1 -Strict         # exit 1 when a problem is found
#   .\tools\Test-LanguagePacks.ps1 -Verbose        # also print per-shard counts
#   .\tools\Test-LanguagePacks.ps1 -ReferenceLanguage en-US -RepoRoot <path>
#
# EXIT CODES
#   0 = consistent (or problems found but -Strict was not given)
#   1 = problems found and -Strict was given, or the check itself failed
# -----------------------------------------------------------------------------

[CmdletBinding()]
param(
    # Repository root. Defaults to the parent directory of this script (tools\).
    [Parameter(Mandatory = $false)]
    [string]$RepoRoot = '',

    # Language used as the baseline. Must be a supported language.
    [Parameter(Mandatory = $false)]
    [string]$ReferenceLanguage = 'en-US',

    # When set, any inconsistency makes the script exit with code 1.
    [Parameter(Mandatory = $false)]
    [switch]$Strict
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

# -----------------------------------------------------------------------------
# 1. Locate the repository and the lang directory
# -----------------------------------------------------------------------------

$script:Root = $RepoRoot
if ([string]::IsNullOrWhiteSpace($script:Root)) {
    if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
        $script:Root = Split-Path -Parent $PSScriptRoot
    } else {
        $script:Root = (Get-Location).Path
    }
}
$script:Root = [System.IO.Path]::GetFullPath($script:Root)

$script:LangRoot = Join-Path $script:Root 'lang'
$script:I18nFile = Join-Path (Join-Path $script:Root 'lib') 'i18n.ps1'

# Collected problems; drives the exit code in -Strict mode.
$script:Problems = New-Object System.Collections.ArrayList
$script:ShardSummaries = New-Object System.Collections.ArrayList

<#
.SYNOPSIS
    Records a problem and prints it immediately.
.PARAMETER Message
    One-line description of the problem.
#>
function Add-Problem {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )
    [void]$script:Problems.Add($Message)
    Write-Host ('FAIL  ' + $Message)
}

<#
.SYNOPSIS
    Prints a GitHub-Actions-friendly error annotation for a problem.
.PARAMETER Message
    One-line description of the problem.
#>
function Write-ProblemAnnotation {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )
    # Escape characters that would break the workflow command syntax.
    $escaped = $Message.Replace('%', '%25').Replace("`r", '%0D').Replace("`n", '%0A')
    Write-Host ('::error title=Language pack parity::' + $escaped)
}

# -----------------------------------------------------------------------------
# 2. Read the supported language list from lib\i18n.ps1
# -----------------------------------------------------------------------------

<#
.SYNOPSIS
    Reads $script:PathAdderSupportedLanguages from lib\i18n.ps1.
.DESCRIPTION
    The list is parsed with the AST (not by executing the file) so the check
    cannot be influenced by the environment. If the AST approach fails for any
    reason we fall back to executing i18n.ps1 in a child scope.
.OUTPUTS
    String array of canonical language names, e.g. @('en-US', 'zh-CN').
#>
function Get-SupportedLanguages {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw ("lib\i18n.ps1 not found at: " + $Path)
    }

    # --- a. Preferred: static AST extraction --------------------------------
    try {
        $tokens = $null
        $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile(
            $Path, [ref]$tokens, [ref]$parseErrors)
        if ($null -ne $parseErrors -and $parseErrors.Count -gt 0) {
            throw ("lib\i18n.ps1 has " + $parseErrors.Count + ' parse error(s)')
        }

        $assignments = $ast.FindAll({
                param($node)
                if ($node -isnot [System.Management.Automation.Language.AssignmentStatementAst]) {
                    return $false
                }
                return ($node.Left.Extent.Text -match 'PathAdderSupportedLanguages')
            }, $true)

        foreach ($assignment in $assignments) {
            $right = $assignment.Right
            $arrayLiterals = $right.FindAll({
                    param($node)
                    return ($node -is [System.Management.Automation.Language.ArrayLiteralAst])
                }, $true)

            foreach ($arrayLiteral in $arrayLiterals) {
                $names = New-Object System.Collections.ArrayList
                foreach ($element in $arrayLiteral.Elements) {
                    if ($element -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
                        [void]$names.Add($element.Value)
                    }
                }
                if ($names.Count -gt 0) {
                    return $names.ToArray()
                }
            }
        }
    } catch {
        Write-Verbose ('AST extraction failed, falling back to execution: ' + $_.Exception.Message)
    }

    # --- b. Fallback: execute i18n.ps1 in an isolated scope -----------------
    $fromExecution = & {
        . $Path
        return @($script:PathAdderSupportedLanguages)
    }
    if ($null -ne $fromExecution -and @($fromExecution).Count -gt 0) {
        return @($fromExecution)
    }

    throw 'Could not determine the supported languages from lib\i18n.ps1'
}

# -----------------------------------------------------------------------------
# 3. Read a single shard file into a key/value table
# -----------------------------------------------------------------------------

<#
.SYNOPSIS
    Loads one language shard file and returns its entries.
.DESCRIPTION
    The shard is executed in a child scope with $PathAdderStrings pre-set to an
    empty hashtable, mirroring lib\i18n.ps1. The returned object records both
    the entries and any duplicate keys detected inside the file.
.OUTPUTS
    PSObject with properties: Entries (hashtable), Duplicates (string[]), Error (string)
#>
function Read-LanguageShard {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $result = New-Object PSObject -Property @{
        Entries    = @{}
        Duplicates = @()
        Error      = $null
    }

    try {
        $entries = & {
            $PathAdderStrings = @{}
            . $Path
            if ($null -eq $PathAdderStrings) {
                $PathAdderStrings = @{}
            }
            return $PathAdderStrings
        }

        if ($null -eq $entries) {
            $result.Error = 'the shard did not assign $PathAdderStrings'
            return $result
        }

        $table = @{}
        $seen = New-Object System.Collections.ArrayList
        $duplicates = New-Object System.Collections.ArrayList
        foreach ($key in $entries.Keys) {
            $name = [string]$key
            if ($table.ContainsKey($name)) {
                [void]$duplicates.Add($name)
            }
            $table[$name] = [string]$entries[$key]
        }

        $result.Entries = $table
        $result.Duplicates = $duplicates.ToArray()
        return $result
    } catch {
        $result.Error = $_.Exception.Message
        return $result
    }
}

# -----------------------------------------------------------------------------
# 4. Main
# -----------------------------------------------------------------------------

Write-Host '========================================================='
Write-Host ' PathAdder - language pack parity check'
Write-Host '========================================================='
Write-Host ('Repo root        : ' + $script:Root)
Write-Host ('Language root    : ' + $script:LangRoot)
Write-Host ('Reference language: ' + $ReferenceLanguage)
Write-Host ('Strict mode      : ' + [bool]$Strict)
Write-Host ''

if (-not (Test-Path -LiteralPath $script:LangRoot -PathType Container)) {
    Add-Problem ('lang directory not found: ' + $script:LangRoot)
    Write-ProblemAnnotation ('lang directory not found: ' + $script:LangRoot)
    exit 1
}

# --- 4a. Supported languages (from i18n.ps1) -------------------------------
try {
    $supported = @(Get-SupportedLanguages -Path $script:I18nFile)
} catch {
    Add-Problem ('Cannot read supported languages: ' + $_.Exception.Message)
    Write-ProblemAnnotation ('Cannot read supported languages: ' + $_.Exception.Message)
    exit 1
}
Write-Host ('Supported languages (lib\i18n.ps1): ' + ($supported -join ', '))

if (-not ($supported -contains $ReferenceLanguage)) {
    Add-Problem ('Reference language ''' + $ReferenceLanguage + ''' is not listed in lib\i18n.ps1')
    Write-ProblemAnnotation ('Reference language ''' + $ReferenceLanguage + ''' is not listed in lib\i18n.ps1')
    exit 1
}

# --- 4b. Language directories on disk vs supported list --------------------
$diskLanguages = @(Get-ChildItem -LiteralPath $script:LangRoot -Directory -ErrorAction SilentlyContinue |
    Sort-Object -Property Name |
    ForEach-Object { $_.Name })

Write-Host ('Language directories on disk    : ' + ($diskLanguages -join ', '))
Write-Host ''

foreach ($language in $supported) {
    if (-not ($diskLanguages -contains $language)) {
        Add-Problem ('Language ''' + $language + ''' is declared in lib\i18n.ps1 but lang\' + $language + '\ does not exist')
    }
}
foreach ($language in $diskLanguages) {
    if (-not ($supported -contains $language)) {
        Add-Problem ('Language directory lang\' + $language + '\ exists but ''' + $language + ''' is not declared in lib\i18n.ps1')
    }
}

# Only languages that exist on disk can be compared.
$comparable = @()
foreach ($language in $supported) {
    if ($diskLanguages -contains $language) {
        $comparable += $language
    }
}

if ($comparable.Count -lt 2) {
    Write-Host ''
    Write-Host 'Only one language available - nothing to compare, but see the messages above.'
    Write-Host ''
    Write-Host ('Problems: ' + $script:Problems.Count)
    if ($Strict -and $script:Problems.Count -gt 0) { exit 1 }
    exit 0
}

# --- 4c. Reference shard set ------------------------------------------------
$referenceDir = Join-Path $script:LangRoot $ReferenceLanguage
$referenceShards = @(Get-ChildItem -LiteralPath $referenceDir -Filter '*.ps1' -File -ErrorAction SilentlyContinue |
    Sort-Object -Property Name |
    ForEach-Object { $_.BaseName })

if ($referenceShards.Count -eq 0) {
    Add-Problem ('Reference language ''' + $ReferenceLanguage + ''' has no shard files')
    exit 1
}

Write-Host ('Reference shards (' + $referenceShards.Count + '): ' + ($referenceShards -join ', '))
Write-Host ''

# --- 4d. Load the reference shards once ------------------------------------
$referenceKeys = @{}
foreach ($shard in $referenceShards) {
    $file = Join-Path $referenceDir ($shard + '.ps1')
    $loaded = Read-LanguageShard -Path $file
    if (-not [string]::IsNullOrWhiteSpace($loaded.Error)) {
        Add-Problem ('Cannot load ' + $ReferenceLanguage + '\' + $shard + '.ps1: ' + $loaded.Error)
        continue
    }
    foreach ($duplicate in $loaded.Duplicates) {
        Add-Problem ($ReferenceLanguage + '\' + $shard + '.ps1: duplicate key ''' + $duplicate + ''' inside the same shard')
    }
    $referenceKeys[$shard] = $loaded.Entries
}

# --- 4e. Compare every other language against the reference ----------------
$otherLanguages = @($comparable | Where-Object { $_ -ne $ReferenceLanguage })

foreach ($language in $otherLanguages) {
    $languageDir = Join-Path $script:LangRoot $language

    # Shard file set parity
    $languageShards = @(Get-ChildItem -LiteralPath $languageDir -Filter '*.ps1' -File -ErrorAction SilentlyContinue |
        Sort-Object -Property Name |
        ForEach-Object { $_.BaseName })

    foreach ($shard in $referenceShards) {
        if (-not ($languageShards -contains $shard)) {
            Add-Problem ('Missing shard file: ' + $language + '\' + $shard + '.ps1 (' + $referenceShards.Count + ' shards expected)')
        }
    }
    foreach ($shard in $languageShards) {
        if (-not ($referenceShards -contains $shard)) {
            Add-Problem ('Extra shard file: ' + $language + '\' + $shard + '.ps1 (not present in ' + $ReferenceLanguage + ')')
        }
    }

    # Per-shard key set parity
    foreach ($shard in $referenceShards) {
        $baseTable = $referenceKeys[$shard]
        if ($null -eq $baseTable) { continue }
        if (-not ($languageShards -contains $shard)) { continue }

        $file = Join-Path $languageDir ($shard + '.ps1')
        $loaded = Read-LanguageShard -Path $file
        if (-not [string]::IsNullOrWhiteSpace($loaded.Error)) {
            Add-Problem ('Cannot load ' + $language + '\' + $shard + '.ps1: ' + $loaded.Error)
            continue
        }
        foreach ($duplicate in $loaded.Duplicates) {
            Add-Problem ($language + '\' + $shard + '.ps1: duplicate key ''' + $duplicate + ''' inside the same shard')
        }

        $translatedTable = $loaded.Entries

        $missing = @($baseTable.Keys | Where-Object { -not $translatedTable.ContainsKey($_) } | Sort-Object)
        $extra = @($translatedTable.Keys | Where-Object { -not $baseTable.ContainsKey($_) } | Sort-Object)

        if ($missing.Count -gt 0) {
            Add-Problem ($language + '\' + $shard + '.ps1: ' + $missing.Count + ' missing key(s)')
            foreach ($key in $missing) {
                Write-Host ('        - missing: ' + $key + '  [present in ' + $ReferenceLanguage + ']')
            }
        }
        if ($extra.Count -gt 0) {
            Add-Problem ($language + '\' + $shard + '.ps1: ' + $extra.Count + ' extra key(s)')
            foreach ($key in $extra) {
                Write-Host ('        + extra  : ' + $key + '  [absent from ' + $ReferenceLanguage + ']')
            }
        }

        [void]$script:ShardSummaries.Add((New-Object PSObject -Property @{
            Language = $language
            Shard    = $shard
            Keys     = $translatedTable.Count
            Missing  = $missing.Count
            Extra    = $extra.Count
        }))

        Write-Verbose ($language + '\' + $shard + ': ' + $translatedTable.Count + ' keys, ' +
            $missing.Count + ' missing, ' + $extra.Count + ' extra')
    }
}

# --- 4f. Summary ------------------------------------------------------------
Write-Host ''
Write-Host '--- Per-shard key counts ---------------------------------------------'
$header = '{0,-10} {1,-9} {2,7} {3,9} {4,7}' -f 'Language', 'Shard', 'Keys', 'Missing', 'Extra'
Write-Host $header
foreach ($summary in $script:ShardSummaries) {
    Write-Host ('{0,-10} {1,-9} {2,7} {3,9} {4,7}' -f
        $summary.Language, $summary.Shard, $summary.Keys, $summary.Missing, $summary.Extra)
}
Write-Host ''

$referenceTotal = 0
foreach ($shard in $referenceKeys.Keys) {
    $referenceTotal += $referenceKeys[$shard].Count
}
Write-Host ('Total keys in ' + $ReferenceLanguage + ': ' + $referenceTotal)
Write-Host ''

if ($script:Problems.Count -eq 0) {
    Write-Host 'RESULT: PASS - all language packs have identical shard and key sets.'
    exit 0
}

Write-Host ('RESULT: FAIL - ' + $script:Problems.Count + ' problem(s) found.')
foreach ($problem in $script:Problems) {
    Write-ProblemAnnotation $problem
}

if ($Strict) {
    exit 1
}

Write-Host '(-Strict not specified: exiting 0 despite the problems above)'
exit 0
