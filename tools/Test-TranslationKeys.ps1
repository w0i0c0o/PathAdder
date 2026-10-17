# -----------------------------------------------------------------------------
# PathAdder - Translation key usage checker (tools\Test-TranslationKeys.ps1)
#
# Target runtime: Windows PowerShell 5.1 (compatible with 3.0+).
# PowerShell 7-only syntax (?? / && / || / ternary / $PSStyle) is FORBIDDEN.
#
# PURPOSE
#   The code asks for strings with T 'Key' / Get-PathAdderText -Key 'Key' (and
#   L10n.T("Key") from the C# shell extension). If a developer renames a key in
#   the code and forgets the language pack - or the other way round - the UI
#   silently shows the raw key name ('Mgr.Title' instead of 'PATH 助手 - ...').
#   This tool statically extracts every LITERAL key referenced by the source
#   tree and cross-checks it against the reference language pack (en-US).
#
# WHAT IS SCANNED
#   PowerShell (.ps1):  T 'Key'            T "Key"
#                       T -Key 'Key'
#                       Get-PathAdderText -Key 'Key'
#                       Get-PathAdderText -Key:'Key'
#   C# (.cs):           L10n.T("Key")      L10n.T(@"Key")
#                       L10n.Get("Key")
#
#   Matching is done over the whole file text with 'singleline' mode so that a
#   call wrapped across several lines is still found.
#
# DYNAMIC KEYS ARE SKIPPED ON PURPOSE
#   The regexes only accept a QUOTED LITERAL directly after the call operator.
#   Anything else is by definition dynamic and is counted and reported
#   separately, never treated as an error:
#     PathManager.ps1:563   (T $script:BackupColumns[$i].Key)
#     lib\i18n.ps1:584      ('App.Language.' + $code)
#     lib\i18n.ps1:572      T '...' -Default $Default (fine: the key is literal)
#   Known dynamic patterns are additionally resolved to their real key prefix
#   (see $script:DynamicKeyHints) so that the report can state "these keys are
#   covered through a variable, not literally referenced".
#
# OUTPUT
#   error  : key referenced by code but absent from the language pack  -> fails
#   warning: key present in the pack but never referenced literally     -> never fails
#
# USAGE
#   .\tools\Test-TranslationKeys.ps1                # report only, always exit 0
#   .\tools\Test-TranslationKeys.ps1 -Strict        # exit 1 on missing keys
#   .\tools\Test-TranslationKeys.ps1 -Verbose       # also list unused keys
#   .\tools\Test-TranslationKeys.ps1 -SkipDynamicReport   # hide the dynamic-key section
#
# EXIT CODES
#   0 = every literal key exists (or missing keys found but -Strict not given)
#   1 = missing keys found and -Strict was given, or the check itself failed
# -----------------------------------------------------------------------------

[CmdletBinding()]
param(
    # Repository root. Defaults to the parent directory of this script (tools\).
    [Parameter(Mandatory = $false)]
    [string]$RepoRoot = '',

    # Language pack used as the source of truth.
    [Parameter(Mandatory = $false)]
    [string]$ReferenceLanguage = 'en-US',

    # When set, keys referenced by code but missing from the pack cause exit 1.
    [Parameter(Mandatory = $false)]
    [switch]$Strict,

    # Hide the informational section that explains dynamically-built keys.
    [Parameter(Mandatory = $false)]
    [switch]$SkipDynamicReport,

    # Documentation shard for the C# L10n map. The C# map is self-contained, so
    # by default its keys are reported informationally only. Pass a shard name
    # (e.g. 'com') to require every L10n.T key to also appear in
    # lang\<ReferenceLanguage>\<shard>.ps1 - use that if the team decides to
    # mirror the C# labels into the language pack.
    [Parameter(Mandatory = $false)]
    [string]$CSharpMapShard = ''
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

# -----------------------------------------------------------------------------
# 1. Paths
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

# Directories that are never scanned (VCS metadata, build output, IDE noise).
$script:SkipDirectoryNames = @('.git', '.vscode', '.idea', 'obj', 'bin', 'node_modules')

# Files that must never be scanned even though they match the extension filter.
# tools\ holds the verification scripts themselves: they contain regex samples
# such as "T 'Key'" inside string literals, which must not be counted as real
# translation calls.
$script:SkipPathPatterns = @(
    '[\\/]tools[\\/]',
    '[\\/]docs[\\/]',
    '^[\\/]\.github[\\/]'
)

<#
.SYNOPSIS
    Call patterns for translation lookups, matched per LINE.
.DESCRIPTION
    The patterns are grouped by extension and applied line by line (never with
    the 'singleline' flag). A global multi-line match would happily run from the
    opening quote of one statement to the closing quote of the NEXT statement
    and invent keys that exist nowhere in the source.

    Within a line the key must be a plain quoted literal without an unescaped
    terminator, which is what makes dynamic keys fall out naturally:
        T 'Mgr.Title'                       -> match
        T "Mgr.Title"                       -> match
        Get-PathAdderText -Key 'A.B'        -> match
        L10n.T("Menu.Root")                 -> match
        T $script:BackupColumns[$i].Key     -> no match (no quote)
        ('App.Language.' + $code)           -> no match (concatenation)
        T 'Shell.*' inside a comment        -> match, see Get-LiteralKeysFromFile
#>
$script:PatternsByExtension = @{
    '.ps1' = @(
        [pscustomobject]@{
            Name  = 'Get-PathAdderText -Key <literal>'
            Regex = 'Get-PathAdderText\s+-Key\s*:?\s*(?:''(?<key>(?:[^'']|'''')+)''|"(?<key>(?:[^"`]|"")+)")'
        },
        [pscustomobject]@{
            Name  = 'T -Key <literal>'
            Regex = '(?<![\w-])T\s+-Key\s*:?\s*(?:''(?<key>(?:[^'']|'''')+)''|"(?<key>(?:[^"`]|"")+)")'
        },
        [pscustomobject]@{
            # The lookahead rejects a leading '$' so that a variable NAMED like
            # the alias (e.g. `$ParentLabel = Get-PathAdderShellMenuParentLabel`)
            # or any other identifier is never mistaken for a call site.
            Name  = 'T <literal>'
            Regex = '(?<![\w-])T\s+(?![$#@])(?:''(?<key>(?:[^'']|'''')+)''|"(?<key>(?:[^"`]|"")+)")'
        }
    )
    '.cs' = @(
        [pscustomobject]@{
            Name  = 'L10n.T("<literal>")'
            Regex = 'L10n\s*\.\s*T\s*\(\s*(?:@"(?<key>(?:[^"]|"")+)"|"(?<key>(?:[^"\\]|\\.)+)")'
        },
        [pscustomobject]@{
            # Defensive: covers a helper rename.
            Name  = 'L10n.Get("<literal>")'
            Regex = 'L10n\s*\.\s*Get\s*\(\s*(?:@"(?<key>(?:[^"]|"")+)"|"(?<key>(?:[^"\\]|\\.)+)")'
        }
    )
}

<#
.SYNOPSIS
    Comment syntax for the supported source types (used to drop commented-out
    call sites: an example inside a block comment, or after a line marker, is
    documentation - not a runtime lookup).
#>
$script:CommentSyntax = @{
    '.ps1' = @{ Line = '#'; BlockStart = '<#'; BlockEnd = '#>' }
    '.cs'  = @{ Line = '//'; BlockStart = '/*'; BlockEnd = '*/' }
}

# Kinds of consumption a literal key can have. Each key is tracked per kind, so
# a key consumed from both worlds does not need to exist twice.
$script:KindPack = 'language-pack'
$script:KindCSharp = 'csharp-map'

<#
.SYNOPSIS
    Maps a file extension to the consumption kind of the keys it references.
.DESCRIPTION
    'language-pack' keys are resolved at runtime by the PowerShell
    T / Get-PathAdderText functions, so they MUST exist under lang\<language>\.

    'csharp-map' keys are resolved by the C# L10n class, whose lookup table is
    a self-contained Dictionary<key, string[]> compiled into
    PathAdderShellExt.dll (com\PathAdderShellExt.cs). Those labels never touch
    the PowerShell language packs, so demanding them in lang\en-US\ would be
    wrong (it would force translators to duplicate text the DLL ignores).

    The C# side is therefore checked separately - and only with an explicit
    opt-in (-CSharpMapShard):
      * 'csharp-map keys not documented'  -> only with -CSharpMapShard <shard>
      * 'csharp-map shard drift'          -> always warning-only (see below)
#>
$script:KindByExtension = @{
    '.ps1' = $script:KindPack
    '.cs'  = $script:KindCSharp
}

<#
.SYNOPSIS
    Known keys that are built at runtime from a variable or a concatenation.
.DESCRIPTION
    These keys cannot be extracted statically. Each entry documents where the
    dynamic call lives and which key prefixes it resolves to; the checker then
    verifies that those prefixes are actually present in the language pack. If
    a prefix disappears from the pack the entry turns into an error, so this is
    a real check, not decoration.
#>
$script:DynamicKeyHints = @(
    [pscustomobject]@{
        Location = 'PathManager.ps1 (T $script:BackupColumns[$i].Key)'
        Reason   = 'Backup list-view column headers, key taken from the $script:BackupColumns hashtable'
        Prefix   = 'Mgr.Column.'
    },
    [pscustomobject]@{
        Location = 'lib\i18n.ps1 (Get-PathAdderText -Key (App.Language. + $code))'
        Reason   = 'Language picker display names, one key per supported language'
        Prefix   = 'App.Language.'
    }
)

# Documented state of the C# L10n dictionary. Recorded here so that the report
# shows the full picture and so that any future drift is visible:
#   * The C# map lives in code, not in lang\; a translator editing lang\ will
#     NOT change the shell context menu.
#   * The DllName/Shard values are informational only; pass -CSharpMapShard to
#     turn the documentation check into an error.
$script:CSharpMapDocumentedIn = 'com\PathAdderShellExt.cs (internal static class L10n, Dictionary Map)'

$script:Errors = New-Object System.Collections.ArrayList
$script:Warnings = New-Object System.Collections.ArrayList

<#
.SYNOPSIS
    Records an error (fails the run in -Strict mode).
#>
function Add-Error {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )
    [void]$script:Errors.Add($Message)
    Write-Host ('ERROR ' + $Message)
}

<#
.SYNOPSIS
    Records a warning (never fails the run).
#>
function Add-Warning {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )
    [void]$script:Warnings.Add($Message)
    Write-Host ('WARN  ' + $Message)
}

<#
.SYNOPSIS
    Prints a GitHub-Actions error annotation, escaping workflow syntax.
#>
function Write-ErrorAnnotation {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )
    $escaped = $Message.Replace('%', '%25').Replace("`r", '%0D').Replace("`n", '%0A')
    Write-Host ('::error title=Translation keys::' + $escaped)
}

<#
.SYNOPSIS
    Returns $true when the given absolute path must not be scanned.
#>
function Test-SkipPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FullName
    )

    $relative = $FullName.Substring($script:Root.Length)
    foreach ($pattern in $script:SkipPathPatterns) {
        if ($relative -match $pattern) {
            return $true
        }
    }
    return $false
}

<#
.SYNOPSIS
    Enumerates the source files to scan (.ps1 and .cs) below the repository root.
.OUTPUTS
    FileInfo array, sorted by full name for stable output.
#>
function Get-ScannableFiles {
    $files = New-Object System.Collections.ArrayList

    $stack = New-Object System.Collections.Stack
    $stack.Push($script:Root)

    while ($stack.Count -gt 0) {
        $current = [string]$stack.Pop()
        $entries = @()
        try {
            $entries = @(Get-ChildItem -LiteralPath $current -Force -ErrorAction Stop)
        } catch {
            Write-Verbose ('Cannot enumerate ' + $current + ': ' + $_.Exception.Message)
            continue
        }

        foreach ($entry in $entries) {
            if ($entry.PSIsContainer) {
                if ($script:SkipDirectoryNames -contains $entry.Name) { continue }
                $stack.Push($entry.FullName)
                continue
            }
            if ($entry.Extension -ne '.ps1' -and $entry.Extension -ne '.cs') { continue }
            if (Test-SkipPath -FullName $entry.FullName) {
                Write-Verbose ('Skipping (tooling/doc path): ' + $entry.FullName)
                continue
            }
            [void]$files.Add($entry)
        }
    }

    return @($files | Sort-Object -Property FullName)
}

<#
.SYNOPSIS
    Loads every shard of the reference language pack into one key set.
.OUTPUTS
    Hashtable mapping key name -> shard name (used for reporting the owner).
#>
function Get-ReferenceKeys {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LanguageRoot,
        [Parameter(Mandatory = $true)]
        [string]$Language
    )

    $languageDir = Join-Path $LanguageRoot $Language
    if (-not (Test-Path -LiteralPath $languageDir -PathType Container)) {
        throw ('Reference language directory not found: ' + $languageDir)
    }

    $keys = @{}
    $shards = @(Get-ChildItem -LiteralPath $languageDir -Filter '*.ps1' -File -ErrorAction SilentlyContinue |
        Sort-Object -Property Name)

    if ($shards.Count -eq 0) {
        throw ('Reference language ''' + $Language + ''' has no shard files in ' + $languageDir)
    }

    foreach ($shard in $shards) {
        $entries = & {
            $PathAdderStrings = @{}
            . $shard.FullName
            if ($null -eq $PathAdderStrings) {
                $PathAdderStrings = @{}
            }
            return $PathAdderStrings
        }
        if ($null -eq $entries) {
            throw ('Shard did not assign $PathAdderStrings: ' + $shard.FullName)
        }
        foreach ($key in $entries.Keys) {
            $name = [string]$key
            if (-not $keys.ContainsKey($name)) {
                $keys[$name] = $shard.BaseName
            }
        }
    }

    return $keys
}

<#
.SYNOPSIS
    Removes comment-only portions of a line.
.DESCRIPTION
    Documentation examples - a lookup written inside a block comment, or after a
    line marker - must not be treated as real lookups, otherwise the checker
    reports keys that only ever existed in prose (lib\i18n.ps1 and
    lib\ShellMenu.ps1 both show sample calls in their help blocks).

    The stripping is deliberately conservative:
      * state (inside block comment or not) is tracked ACROSS lines;
      * a line marker is only honoured when it is not preceded by a quote
        character, so a '#' or '//' inside a string literal is left alone.
    This is not a full parser - and does not need to be: a false positive here
    only means one extra key is checked, never a missed error.
.PARAMETER Line
    One source line (without its terminator).
.PARAMETER Syntax
    Comment syntax descriptor for the language.
.PARAMETER InBlockComment
    [ref] boolean carrying the block-comment state between calls.
.OUTPUTS
    The line with block-comment spans removed and the trailing line comment cut.
#>
function Remove-CommentText {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Line,

        [Parameter(Mandatory = $true)]
        [hashtable]$Syntax,

        [Parameter(Mandatory = $true)]
        [ref]$InBlockComment
    )

    $result = $Line

    # 1. Remove block comment spans (possibly opened on a previous line).
    $safety = 0
    while ($safety -lt 32) {
        $safety++
        if ($InBlockComment.Value) {
            $endIndex = $result.IndexOf($Syntax.BlockEnd, [System.StringComparison]::Ordinal)
            if ($endIndex -lt 0) {
                return ''
            }
            $result = $result.Substring($endIndex + $Syntax.BlockEnd.Length)
            $InBlockComment.Value = $false
            continue
        }

        $startIndex = $result.IndexOf($Syntax.BlockStart, [System.StringComparison]::Ordinal)
        if ($startIndex -lt 0) {
            break
        }
        $endIndex = $result.IndexOf($Syntax.BlockEnd,
            $startIndex + $Syntax.BlockStart.Length, [System.StringComparison]::Ordinal)
        if ($endIndex -lt 0) {
            $result = $result.Substring(0, $startIndex)
            $InBlockComment.Value = $true
            break
        }
        $result = $result.Substring(0, $startIndex) +
                  $result.Substring($endIndex + $Syntax.BlockEnd.Length)
    }

    # 2. Cut a trailing line comment, ignoring markers that sit inside quotes.
    $index = 0
    $inSingle = $false
    $inDouble = $false
    while ($index -lt $result.Length) {
        $char = $result[$index]

        if ($inSingle) {
            if ($char -eq "'") {
                if ($index + 1 -lt $result.Length -and $result[$index + 1] -eq "'") {
                    $index = $index + 2
                    continue
                }
                $inSingle = $false
            }
            $index++
            continue
        }
        if ($inDouble) {
            if ($char -eq '`') {
                $index = $index + 2
                continue
            }
            if ($char -eq '"') {
                if ($index + 1 -lt $result.Length -and $result[$index + 1] -eq '"') {
                    $index = $index + 2
                    continue
                }
                $inDouble = $false
            }
            $index++
            continue
        }

        if ($char -eq "'") { $inSingle = $true; $index++; continue }
        if ($char -eq '"') { $inDouble = $true; $index++; continue }

        if ([string]::CompareOrdinal($result, $index, $Syntax.Line, 0, $Syntax.Line.Length) -eq 0) {
            return $result.Substring(0, $index)
        }
        $index++
    }

    return $result
}

<#
.SYNOPSIS
    Extracts every literal translation key from one source file.
.DESCRIPTION
    Only the patterns for the file's extension are applied, so a .cs file is
    never scanned with the PowerShell 'T ...' pattern (and vice versa).
    Matching is LINE based (no 'singleline' flag): see $script:PatternsByExtension.

    Commented-out lines and documentation blocks are stripped first, because the
    PowerShell help blocks of lib\i18n.ps1 and lib\ShellMenu.ps1 legitimately
    contain example calls such as `T 'Core.Msg.InvalidDir'`.
.OUTPUTS
    PSObject with properties:
      Path       - absolute file path
      Relative   - path relative to the repository root
      Kind       - 'language-pack' or 'csharp-map'
      Keys       - string array of literal keys (may contain duplicates)
      MatchCount - total number of literal matches
#>
function Get-LiteralKeysFromFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $extension = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
    $kind = $script:KindPack
    if ($script:KindByExtension.ContainsKey($extension)) {
        $kind = $script:KindByExtension[$extension]
    }

    $patterns = @()
    if ($script:PatternsByExtension.ContainsKey($extension)) {
        $patterns = $script:PatternsByExtension[$extension]
    }
    $syntax = $script:CommentSyntax[$extension]

    $lines = [System.IO.File]::ReadAllLines($Path, [System.Text.Encoding]::UTF8)
    $found = New-Object System.Collections.ArrayList
    $inBlockComment = $false

    foreach ($line in $lines) {
        $code = $line
        if ($null -ne $syntax) {
            $state = [bool]$inBlockComment
            $code = Remove-CommentText -Line $line -Syntax $syntax -InBlockComment ([ref]$state)
            $inBlockComment = $state
        }
        if ([string]::IsNullOrWhiteSpace($code)) { continue }

        foreach ($pattern in $patterns) {
            $regex = New-Object System.Text.RegularExpressions.Regex(
                $pattern.Regex, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
            foreach ($match in $regex.Matches($code)) {
                $value = $match.Groups['key'].Value
                if ([string]::IsNullOrWhiteSpace($value)) { continue }
                if ($value.Contains("'")) {
                    $value = $value.Replace("''", "'")
                }
                if ($value.Contains('"')) {
                    $value = $value.Replace('""', '"')
                }
                [void]$found.Add($value.Trim())
            }
        }
    }

    return New-Object PSObject -Property @{
        Path       = $Path
        Relative   = $Path.Substring($script:Root.Length)
        Kind       = $kind
        Keys       = $found.ToArray()
        MatchCount = $found.Count
    }
}

<#
.SYNOPSIS
    Counts translation call sites whose argument is NOT a string literal.
.DESCRIPTION
    Purely informational: a developer reading the report should be able to see
    that dynamic call sites exist and are handled explicitly. Line based, like
    the literal extraction, and limited to PowerShell sources (the C# side only
    ever calls L10n.T with constants).
.OUTPUTS
    Integer count of dynamic call sites.
#>
function Get-DynamicCallCount {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $syntax = $script:CommentSyntax['.ps1']

    # T followed by a variable / sub-expression / parenthesis, or a -Key whose
    # value is not a literal quote.
    $dynamicPattern = '(?<![\w-])T\s+[$(@]|Get-PathAdderText\s+-Key\s*(?:[:=]\s*)?[$(@]'
    $regex = New-Object System.Text.RegularExpressions.Regex(
        $dynamicPattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

    $count = 0
    $inBlockComment = $false
    foreach ($line in [System.IO.File]::ReadAllLines($Path, [System.Text.Encoding]::UTF8)) {
        $state = [bool]$inBlockComment
        $code = Remove-CommentText -Line $line -Syntax $syntax -InBlockComment ([ref]$state)
        $inBlockComment = $state
        if ([string]::IsNullOrWhiteSpace($code)) { continue }
        $count += $regex.Matches($code).Count
    }
    return $count
}

# -----------------------------------------------------------------------------
# 2. Main
# -----------------------------------------------------------------------------

Write-Host '========================================================='
Write-Host ' PathAdder - translation key usage check'
Write-Host '========================================================='
Write-Host ('Repo root         : ' + $script:Root)
Write-Host ('Language root     : ' + $script:LangRoot)
Write-Host ('Reference language: ' + $ReferenceLanguage)
Write-Host ('Strict mode       : ' + [bool]$Strict)
Write-Host ''

# --- 2a. Language pack ------------------------------------------------------
try {
    $packKeys = Get-ReferenceKeys -LanguageRoot $script:LangRoot -Language $ReferenceLanguage
} catch {
    Add-Error ('Cannot load the language pack: ' + $_.Exception.Message)
    Write-ErrorAnnotation ('Cannot load the language pack: ' + $_.Exception.Message)
    exit 1
}
Write-Host ('Reference keys loaded: ' + $packKeys.Count + ' (from ' + $ReferenceLanguage + ')')
Write-Host ''

# --- 2b. Scan the source tree ----------------------------------------------
$files = @(Get-ScannableFiles)
if ($files.Count -eq 0) {
    Add-Error 'No .ps1 / .cs files found to scan'
    exit 1
}

$usage = @{}            # "kind|key" -> ArrayList of relative paths using it
$totalMatches = 0
$dynamicTotal = 0
$filesWithDynamic = New-Object System.Collections.ArrayList

foreach ($file in $files) {
    $result = Get-LiteralKeysFromFile -Path $file.FullName
    $totalMatches += $result.MatchCount

    foreach ($key in $result.Keys) {
        $composite = $result.Kind + '|' + $key
        if (-not $usage.ContainsKey($composite)) {
            $usage[$composite] = New-Object System.Collections.ArrayList
        }
        [void]$usage[$composite].Add($result.Relative)
    }

    $dynamicCount = Get-DynamicCallCount -Path $file.FullName
    if ($dynamicCount -gt 0) {
        $dynamicTotal += $dynamicCount
        [void]$filesWithDynamic.Add((New-Object PSObject -Property @{
            Relative = $result.Relative
            Count    = $dynamicCount
        }))
    }
}

# Split the composite keys back into the two consumption worlds.
$packUsage = @{}        # key -> ArrayList of paths (resolved by T / Get-PathAdderText)
$csharpUsage = @{}      # key -> ArrayList of paths (resolved by the compiled L10n map)
foreach ($composite in $usage.Keys) {
    $separator = $composite.IndexOf('|')
    $kind = $composite.Substring(0, $separator)
    $key = $composite.Substring($separator + 1)
    if ($kind -eq $script:KindCSharp) {
        $csharpUsage[$key] = $usage[$composite]
    } else {
        $packUsage[$key] = $usage[$composite]
    }
}

Write-Host ('Scanned files       : ' + $files.Count + ' (.ps1 / .cs)')
Write-Host ('Literal call sites  : ' + $totalMatches)
Write-Host ('Pack keys referenced     : ' + $packUsage.Keys.Count + ' (resolved by T / Get-PathAdderText)')
Write-Host ('C# map keys referenced   : ' + $csharpUsage.Keys.Count + ' (resolved by the compiled L10n dictionary)')
Write-Host ''

<#
    Formats up to $Max locations of a usage entry as a single readable string.
#>
function Format-UsageLocations {
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.ArrayList]$Locations,
        [Parameter(Mandatory = $false)]
        [int]$Max = 3
    )

    $unique = @($Locations | Select-Object -Unique)
    $shown = @($unique | Select-Object -First $Max)
    $text = ($shown -join ', ')
    if ($unique.Count -gt $shown.Count) {
        $text = $text + ', ...'
    }
    return $text
}

# --- 2c. Code -> pack: every key resolved by T must exist ------------------
$missing = @($packUsage.Keys | Where-Object { -not $packKeys.ContainsKey($_) } | Sort-Object)
foreach ($key in $missing) {
    $where = Format-UsageLocations -Locations $packUsage[$key]
    Add-Error ('Key ''' + $key + ''' is used in ' + $where + ' but missing from ' + $ReferenceLanguage)
}

# --- 2d. Code -> C# map ---------------------------------------------------
# The C# L10n dictionary is compiled into the DLL and never reads lang\, so
# these keys are NOT required in the language pack. They are always reported so
# that the split is visible, and the check becomes an error only when a
# documentation shard is requested explicitly via -CSharpMapShard.
$missingCSharp = @()
$csharpKeys = @($csharpUsage.Keys | Sort-Object)

if ($csharpKeys.Count -gt 0) {
    Write-Host ('C# L10n map: ' + $csharpKeys.Count + ' key(s), owner: ' + $script:CSharpMapDocumentedIn)
    foreach ($key in $csharpKeys) {
        $where = Format-UsageLocations -Locations $csharpUsage[$key]
        Write-Host ('  ' + $key + '  <- ' + $where)
    }
}

if (-not [string]::IsNullOrWhiteSpace($CSharpMapShard)) {
    foreach ($key in $csharpKeys) {
        if (-not $packKeys.ContainsKey($key)) {
            $missingCSharp += $key
            $where = Format-UsageLocations -Locations $csharpUsage[$key]
            Add-Error ('Key ''' + $key + ''' (C# L10n map) is used in ' + $where +
                ' but is not documented in ' + $ReferenceLanguage + '\' + $CSharpMapShard + '.ps1')
        }
    }
    if ($missingCSharp.Count -eq 0) {
        Write-Host ('C# map documented: all ' + $csharpKeys.Count + ' L10n.T key(s) are present in ' +
            $ReferenceLanguage + '\' + $CSharpMapShard + '.ps1')
    }
} else {
    Write-Host 'C# map check: informational only (pass -CSharpMapShard <shard> to require documentation).'
}

# --- 2e. Pack -> code: unreferenced keys (warning only) --------------------
# A key referenced ONLY from C# counts as referenced: it is documented, not dead.
$unused = @($packKeys.Keys | Where-Object {
        (-not $packUsage.ContainsKey($_)) -and (-not $csharpUsage.ContainsKey($_))
    } | Sort-Object)
foreach ($key in $unused) {
    Add-Warning ('Key ''' + $key + ''' (' + $packKeys[$key] + '.ps1) is never referenced literally (shared/indirect key?)')
}

# --- 2f. Dynamic key section ----------------------------------------------
if (-not $SkipDynamicReport) {
    Write-Host ''
    Write-Host '--- Dynamically built keys (excluded from the literal check) -----------'
    if ($dynamicTotal -eq 0) {
        Write-Host 'None detected.'
    } else {
        Write-Host ('Dynamic call sites detected: ' + $dynamicTotal + ' in ' + $filesWithDynamic.Count + ' file(s)')
        foreach ($item in $filesWithDynamic) {
            Write-Host ('  ' + $item.Relative + ' : ' + $item.Count)
        }
    }

    Write-Host ''
    Write-Host '--- Known dynamic patterns and their real key prefixes ----------------'
    foreach ($hint in $script:DynamicKeyHints) {
        $covered = @($packKeys.Keys | Where-Object { $_.StartsWith($hint.Prefix, [System.StringComparison]::Ordinal) })
        $state = 'OK      '
        if ($covered.Count -eq 0) {
            $state = 'MISSING '
            Add-Error ('Dynamic key prefix ''' + $hint.Prefix + ''' (' + $hint.Location + ') has no matching key in ' + $ReferenceLanguage)
        }
        Write-Host ('  [' + $state + '] ' + $hint.Prefix + '* -> ' + $covered.Count + ' key(s); ' + $hint.Location)
        Write-Host ('             ' + $hint.Reason)
        if ($covered.Count -gt 0 -and $covered.Count -le 12) {
            Write-Host ('             ' + ($covered -join ', '))
        }
    }
}

# --- 2g. Verbose listing of unused keys -----------------------------------
if ($unused.Count -gt 0) {
    Write-Verbose ('Unused keys (' + $unused.Count + '):')
    foreach ($key in $unused) {
        Write-Verbose ('  ' + $key + '  [' + $packKeys[$key] + ']')
    }
}

# --- 2h. Summary -----------------------------------------------------------
Write-Host ''
Write-Host '--- Summary -----------------------------------------------------------'
Write-Host ('Keys in ' + $ReferenceLanguage + '          : ' + $packKeys.Count)
Write-Host ('Pack keys referenced        : ' + $packUsage.Keys.Count)
Write-Host ('C# map keys referenced      : ' + $csharpUsage.Keys.Count)
Write-Host ('Missing from pack           : ' + $missing.Count + '  (error)')
Write-Host ('C# keys not documented      : ' + $missingCSharp.Count + '  (error)')
Write-Host ('Never referenced            : ' + $unused.Count + '  (warning only)')
Write-Host ''

if ($script:Errors.Count -eq 0) {
    Write-Host 'RESULT: PASS - every literal translation key exists in the language pack.'
    if ($script:Warnings.Count -gt 0) {
        Write-Host ('(' + $script:Warnings.Count + ' warning(s) - unused keys are informational only)')
    }
    exit 0
}

Write-Host ('RESULT: FAIL - ' + $script:Errors.Count + ' error(s) found.')
foreach ($errorMessage in $script:Errors) {
    Write-ErrorAnnotation $errorMessage
}

if ($Strict) {
    exit 1
}

Write-Host '(-Strict not specified: exiting 0 despite the errors above)'
exit 0
