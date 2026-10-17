# -----------------------------------------------------------------------------
# PathAdder - Multi-language support framework (lib\i18n.ps1)
#
# Target runtime: Windows PowerShell 5.1 (compatible with 3.0+).
# PowerShell 7-only syntax (?? / && / || / ternary / $PSStyle) is FORBIDDEN.
#
# Design:
#   1. Language packs are stored per module SHARD: lang\<language>\<shard>.ps1
#      Each shard file does exactly one thing: assign a hashtable to
#      $PathAdderStrings. Sharding means several people can localise different
#      modules without ever editing the same file.
#   2. The loader merges every shard into a single table. English (en-US) is
#      always loaded FIRST as the base, then the active language overlays it,
#      so a missing key falls back to English, and finally to the key name
#      itself (never blank).
#   3. Language resolution order (highest priority first):
#        a. Environment variable PATHADDER_LANG
#        b. "language" field of %LOCALAPPDATA%\PathAdder\config.json
#        c. Registry value Language under HKCU\Software\PathAdder
#           (this is how the COM shell extension running inside explorer.exe
#           picks the language up - it can see neither our variables nor our
#           scopes)
#        d. OS UI culture (CurrentUICulture), so a fresh install on a Chinese
#           Windows starts in Chinese
#        e. Default language: en-US (used when the OS language is unsupported)
#      NOTE: an explicit user choice (a/b/c) always wins over the OS language.
#      The OS culture only decides the INITIAL default; once the user picks a
#      language it is persisted and takes precedence on every later run.
#   4. State lives in $global: (not $script:) so that WinForms event callbacks,
#      which run in a child scope, can still resolve strings.
#
# Usage:
#   . (Join-Path $libDir 'i18n.ps1')      # dot-source at the top of a script
#   Initialize-PathAdderI18n -ScriptDirectory $root   # optional explicit init
#   T 'App.Name'                          # resolve a string
#   T 'Core.Msg.InvalidDir' @($dir)       # with a {0} placeholder
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# 0. Constants
# -----------------------------------------------------------------------------

# Canonical names of the supported languages (order = order shown in the
# language picker)
$script:PathAdderSupportedLanguages = @('en-US', 'zh-CN')

# Default language: English
$script:PathAdderDefaultLanguage = 'en-US'

# Shard file names (load order is irrelevant; everything ends up in one table)
$script:PathAdderLanguageShards = @('core', 'shell', 'picker', 'gui', 'cli', 'setup', 'verify', 'com')

<#
.SYNOPSIS
    Returns the command-line arguments used to hand the current language to a
    child script: @('-Language', '<code>').
.DESCRIPTION
    ProcessStartInfo.EnvironmentVariables is mutually exclusive with
    UseShellExecute=$true (.NET throws InvalidOperationException), while UAC
    elevation requires UseShellExecute. Child processes therefore receive the
    language as a command-line argument instead.
#>
function Get-PathAdderLanguageArgument {
    return @('-Language', (Get-PathAdderLanguage))
}

<#
.SYNOPSIS
    Returns the canonical names of the supported languages.
#>
function Get-PathAdderSupportedLanguages {
    return @('en-US', 'zh-CN')
}

<#
.SYNOPSIS
    Returns the default language (en-US).
#>
function Get-PathAdderDefaultLanguage {
    return 'en-US'
}

<#
.SYNOPSIS
    Normalises any language tag into a supported canonical name.
.DESCRIPTION
    'en' / 'en-US' / 'en-GB' -> 'en-US';
    'zh' / 'zh-CN' / 'zh-Hans' / 'zh-Hant' / 'zh-TW' -> 'zh-CN'.
    Returns $null when the tag is not recognised; the caller then falls back to
    the default language.
#>
function ConvertTo-PathAdderLanguage {
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [string]$Language
    )

    if ([string]::IsNullOrWhiteSpace($Language)) {
        return $null
    }

    $value = $Language.Trim()

    # Exact match first
    foreach ($supported in $script:PathAdderSupportedLanguages) {
        if ([string]::Compare($value, $supported, [StringComparison]::OrdinalIgnoreCase) -eq 0) {
            return $supported
        }
    }

    # Then match on the primary language subtag
    $lower = $value.ToLowerInvariant()
    if ($lower -eq 'en' -or $lower.StartsWith('en-')) {
        return 'en-US'
    }
    if ($lower -eq 'zh' -or $lower.StartsWith('zh-') -or $lower -eq 'chinese' -or $lower -eq 'cn') {
        return 'zh-CN'
    }

    return $null
}

# -----------------------------------------------------------------------------
# 1. Configuration persistence (file + registry)
# -----------------------------------------------------------------------------

<#
.SYNOPSIS
    Returns the configuration file path: %LOCALAPPDATA%\PathAdder\config.json
#>
function Get-PathAdderConfigPath {
    $root = $env:LOCALAPPDATA
    if ([string]::IsNullOrWhiteSpace($root)) {
        $root = Join-Path $env:USERPROFILE 'AppData\Local'
    }
    $dir = Join-Path $root 'PathAdder'
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -Path $dir -ItemType Directory -Force | Out-Null
    }
    return (Join-Path $dir 'config.json')
}

# Registry key used to publish the language to the COM shell extension that
# runs inside explorer.exe - there we can see neither our environment variables
# nor our PowerShell scopes.
$script:PathAdderRegistryKey = 'HKCU:\Software\PathAdder'

<#
.SYNOPSIS
    Reads the persisted language setting (file first, then registry).
.OUTPUTS
    A canonical language name, or $null when nothing has been saved yet.
#>
function Get-PathAdderStoredLanguage {
    # a. Environment variable
    $fromEnv = ConvertTo-PathAdderLanguage -Language $env:PATHADDER_LANG
    if (-not [string]::IsNullOrWhiteSpace($fromEnv)) {
        return $fromEnv
    }

    # b. Configuration file
    try {
        $configPath = Get-PathAdderConfigPath
        if (Test-Path -LiteralPath $configPath -PathType Leaf) {
            $raw = [System.IO.File]::ReadAllText($configPath, [System.Text.Encoding]::UTF8)
            if (-not [string]::IsNullOrWhiteSpace($raw)) {
                $config = $raw | ConvertFrom-Json
                if ($null -ne $config -and $null -ne $config.PSObject.Properties['language']) {
                    $fromFile = ConvertTo-PathAdderLanguage -Language ([string]$config.language)
                    if (-not [string]::IsNullOrWhiteSpace($fromFile)) {
                        return $fromFile
                    }
                }
            }
        }
    } catch {
        # Corrupt or unreadable config file: ignore and fall through
    }

    # c. Registry
    try {
        if (Test-Path -LiteralPath $script:PathAdderRegistryKey) {
            $item = Get-ItemProperty -LiteralPath $script:PathAdderRegistryKey -Name 'Language' -ErrorAction SilentlyContinue
            if ($null -ne $item) {
                $fromReg = ConvertTo-PathAdderLanguage -Language ([string]$item.Language)
                if (-not [string]::IsNullOrWhiteSpace($fromReg)) {
                    return $fromReg
                }
            }
        }
    } catch {
        # No permission or key missing: ignore
    }

    return $null
}

<#
.SYNOPSIS
    Persists the language setting to the configuration file and the registry.
.DESCRIPTION
    HKCU\Software\PathAdder\Language is written as well so that the COM shell
    extension (PathAdderShellExt.dll) running inside explorer.exe follows the
    switch too. A failing registry write (e.g. restricted permissions) is not
    treated as fatal.
#>
function Set-PathAdderLanguage {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Language,

        [Parameter(Mandatory = $false)]
        [switch]$NoPersist
    )

    $normalized = ConvertTo-PathAdderLanguage -Language $Language
    if ([string]::IsNullOrWhiteSpace($normalized)) {
        $normalized = $script:PathAdderDefaultLanguage
    }

    # Switch the current process immediately
    $global:PathAdderLanguage = $normalized
    $global:PathAdderStrings = $null
    [void](Import-PathAdderLanguagePack -Language $normalized)

    # Let child processes inherit the same language
    $env:PATHADDER_LANG = $normalized

    if ($NoPersist) {
        return $normalized
    }

    # Configuration file
    try {
        $json = '{ "language": "' + $normalized + '" }'
        [System.IO.File]::WriteAllText((Get-PathAdderConfigPath), $json, (New-Object System.Text.UTF8Encoding($false)))
    } catch {
        # Unwritable config file: the current session still works
    }

    # Registry
    try {
        if (-not (Test-Path -LiteralPath $script:PathAdderRegistryKey)) {
            New-Item -Path $script:PathAdderRegistryKey -Force | Out-Null
        }
        Set-ItemProperty -LiteralPath $script:PathAdderRegistryKey -Name 'Language' -Value $normalized -Force
    } catch {
        # Unwritable registry: the COM extension falls back to English
    }

    return $normalized
}

# -----------------------------------------------------------------------------
# 2. Language resolution
# -----------------------------------------------------------------------------

<#
.SYNOPSIS
    Resolves the language to use (cached for the lifetime of the process).
.DESCRIPTION
    Order: PATHADDER_LANG > config.json > HKCU registry > OS UI culture > en-US.
    The OS UI culture wins over the built-in default on first run, so a fresh
    install on a Chinese Windows shows Chinese; English is used whenever the
    OS language is not one we support (or nothing can be determined).
#>
function Get-PathAdderLanguage {
    if (-not [string]::IsNullOrWhiteSpace($global:PathAdderLanguage)) {
        return $global:PathAdderLanguage
    }

    # a/b/c. Anything the user explicitly saved
    $stored = Get-PathAdderStoredLanguage
    if (-not [string]::IsNullOrWhiteSpace($stored)) {
        $global:PathAdderLanguage = $stored
        return $stored
    }

    # d. OS UI language - the preferred default on a fresh install
    $fromCulture = $null
    try {
        $fromCulture = ConvertTo-PathAdderLanguage -Language ([System.Globalization.CultureInfo]::CurrentUICulture.Name)
    } catch {
        $fromCulture = $null
    }
    if (-not [string]::IsNullOrWhiteSpace($fromCulture)) {
        $global:PathAdderLanguage = $fromCulture
        return $fromCulture
    }

    # e. English
    $global:PathAdderLanguage = $script:PathAdderDefaultLanguage
    return $script:PathAdderDefaultLanguage
}

# -----------------------------------------------------------------------------
# 3. Language pack loading
# -----------------------------------------------------------------------------

# Directory of this file (lib\), used to derive the application root.
# This MUST be evaluated at script top level: inside a function neither
# $PSScriptRoot nor $MyInvocation points at the script file itself.
$script:PathAdderLibDirectory = ''
if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
    $script:PathAdderLibDirectory = $PSScriptRoot
} elseif ($null -ne $MyInvocation -and $null -ne $MyInvocation.MyCommand) {
    try {
        $script:PathAdderLibDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
    } catch {
        $script:PathAdderLibDirectory = ''
    }
}

# Last-resort fallback: when this file is dot-sourced from an interactive host
# or from a pipeline (no $PSScriptRoot, and $MyInvocation.MyCommand.Path is
# empty), scan the command line for the token that names this very file. This
# keeps the language root discoverable in hosts that do not populate
# $PSScriptRoot, instead of silently loading zero strings.
if ([string]::IsNullOrWhiteSpace($script:PathAdderLibDirectory)) {
    try {
        $commandLine = [System.Environment]::CommandLine
        if (-not [string]::IsNullOrWhiteSpace($commandLine)) {
            $marker = 'i18n.ps1'
            $index = $commandLine.IndexOf($marker, [System.StringComparison]::OrdinalIgnoreCase)
            if ($index -ge 0) {
                $tail = $commandLine.Substring(0, $index + $marker.Length).Trim()
                $tail = $tail.Trim('"', "'")
                if ($tail.Length -gt 0 -and (Test-Path -LiteralPath $tail -PathType Leaf)) {
                    $script:PathAdderLibDirectory = Split-Path -Parent (Resolve-Path -LiteralPath $tail).ProviderPath
                }
            }
        }
    } catch {
        # Best effort only - never let path discovery break the loader.
    }
}

# Register the application root explicitly (removes any path-guessing)
if ([string]::IsNullOrWhiteSpace($global:PathAdderRootDirectory) -and
    -not [string]::IsNullOrWhiteSpace($script:PathAdderLibDirectory)) {
    $parent = Split-Path -Parent $script:PathAdderLibDirectory
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        $global:PathAdderRootDirectory = $parent
    }
}

<#
.SYNOPSIS
    Locates the lang directory.
.DESCRIPTION
    Candidates, in order:
      1. $global:PathAdderRootDirectory (registered by the calling script)
      2. The parent of the lib directory (where this file lives)
      3. $PSScriptRoot and its parent
      4. The current working directory, walking up at most 4 levels

    WARNING: do not use $MyInvocation.MyCommand.Definition here - inside a
    function it returns the FUNCTION BODY source, not a script path, which
    makes Split-Path throw "provider not found".
#>
function Get-PathAdderLanguageRoot {
    $candidateRoots = New-Object System.Collections.ArrayList

    if (-not [string]::IsNullOrWhiteSpace($global:PathAdderRootDirectory)) {
        [void]$candidateRoots.Add($global:PathAdderRootDirectory)
    }

    if (-not [string]::IsNullOrWhiteSpace($script:PathAdderLibDirectory)) {
        $parent = Split-Path -Parent $script:PathAdderLibDirectory
        if (-not [string]::IsNullOrWhiteSpace($parent)) {
            [void]$candidateRoots.Add($parent)
        }
        [void]$candidateRoots.Add($script:PathAdderLibDirectory)
    }

    if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
        $parent = Split-Path -Parent $PSScriptRoot
        if (-not [string]::IsNullOrWhiteSpace($parent)) {
            [void]$candidateRoots.Add($parent)
        }
        [void]$candidateRoots.Add($PSScriptRoot)
    }

    [void]$candidateRoots.Add((Get-Location).Path)

    foreach ($root in $candidateRoots) {
        if ([string]::IsNullOrWhiteSpace($root)) { continue }
        $current = $root
        for ($i = 0; $i -lt 4; $i++) {
            if ([string]::IsNullOrWhiteSpace($current)) { break }
            $langDir = Join-Path $current 'lang'
            if (Test-Path -LiteralPath $langDir -PathType Container) {
                $global:PathAdderRootDirectory = $current
                return $langDir
            }
            $parent = Split-Path -Parent $current
            if ([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $current) { break }
            $current = $parent
        }
    }

    return $null
}

<#
.SYNOPSIS
    Loads every shard of the given language and returns the merged table.
.DESCRIPTION
    English is loaded first as the base and the target language is layered on
    top, so a missing key automatically falls back to English. A broken shard
    is skipped instead of taking the whole application down.
#>
function Import-PathAdderLanguagePack {
    param(
        [Parameter(Mandatory = $false)]
        [string]$Language
    )

    if ([string]::IsNullOrWhiteSpace($Language)) {
        $Language = Get-PathAdderLanguage
    }
    $normalized = ConvertTo-PathAdderLanguage -Language $Language
    if ([string]::IsNullOrWhiteSpace($normalized)) {
        $normalized = $script:PathAdderDefaultLanguage
    }

    $langRoot = Get-PathAdderLanguageRoot
    $merged = @{}

    if ([string]::IsNullOrWhiteSpace($langRoot)) {
        # No lang directory. Surface this loudly: in production it is always a
        # packaging error, and silently returning an empty table makes every
        # string degrade to its key name with no hint about the cause.
        Write-Warning ("PathAdder i18n: the 'lang' directory could not be located from '" +
                       (Get-Location).Path + "'. All UI text will fall back to raw key names. " +
                       "Pass -ScriptDirectory <app root> to Initialize-PathAdderI18n, or " +
                       "dot-source lib\i18n.ps1 from a script file (not interactively).")
        $global:PathAdderStrings = $merged
        return $merged
    }

    $loadOrder = New-Object System.Collections.ArrayList
    if ($normalized -ne $script:PathAdderDefaultLanguage) {
        [void]$loadOrder.Add($script:PathAdderDefaultLanguage)
    }
    [void]$loadOrder.Add($normalized)

    foreach ($lang in $loadOrder) {
        $dir = Join-Path $langRoot $lang
        if (-not (Test-Path -LiteralPath $dir -PathType Container)) { continue }

        $files = Get-ChildItem -LiteralPath $dir -Filter '*.ps1' -ErrorAction SilentlyContinue
        if ($null -eq $files) { continue }

        # Known shards first (stable order), then anything extra
        $ordered = New-Object System.Collections.ArrayList
        foreach ($shard in $script:PathAdderLanguageShards) {
            $file = Join-Path $dir ($shard + '.ps1')
            if (Test-Path -LiteralPath $file -PathType Leaf) {
                [void]$ordered.Add($file)
            }
        }
        foreach ($file in $files) {
            if (-not ($ordered -contains $file.FullName)) {
                [void]$ordered.Add($file.FullName)
            }
        }

        foreach ($file in $ordered) {
            try {
                $pack = & {
                    $PathAdderStrings = @{}
                    . $file
                    if ($null -eq $PathAdderStrings) { $PathAdderStrings = @{} }
                    return $PathAdderStrings
                }
                if ($null -ne $pack) {
                    foreach ($key in $pack.Keys) {
                        $merged[[string]$key] = [string]$pack[$key]
                    }
                }
            } catch {
                # A single broken shard must not break the other modules
            }
        }
    }

    $global:PathAdderStrings = $merged
    return $merged
}

<#
.SYNOPSIS
    Makes sure the string table is loaded (lazy initialisation).
#>
function Initialize-PathAdderStrings {
    if ($null -eq $global:PathAdderStrings -or $global:PathAdderStrings.Count -eq 0) {
        [void](Import-PathAdderLanguagePack)
    }
}

<#
.SYNOPSIS
    Called by a script entry point right after dot-sourcing this file.
.PARAMETER Language
    Explicit language (e.g. from a -Language command-line switch). When it is
    omitted the language is resolved using the normal priority order.
#>
function Initialize-PathAdderI18n {
    param(
        [Parameter(Mandatory = $false)]
        [string]$Language,

        # Explicit application root (the folder that contains lang\). Use this
        # from hosts that do not populate $PSScriptRoot (interactive sessions,
        # remote runspaces, job/pipeline hosts) - otherwise the loader has to
        # guess and may end up with an empty table.
        [Parameter(Mandatory = $false)]
        [string]$ScriptDirectory
    )

    if (-not [string]::IsNullOrWhiteSpace($ScriptDirectory)) {
        $resolved = $ScriptDirectory
        try { $resolved = (Resolve-Path -LiteralPath $ScriptDirectory).ProviderPath } catch { }
        if (Test-Path -LiteralPath (Join-Path $resolved 'lang') -PathType Container) {
            $global:PathAdderRootDirectory = $resolved
            $script:PathAdderLibDirectory = Join-Path $resolved 'lib'
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($Language)) {
        $normalized = ConvertTo-PathAdderLanguage -Language $Language
        if (-not [string]::IsNullOrWhiteSpace($normalized)) {
            $global:PathAdderLanguage = $normalized
            $env:PATHADDER_LANG = $normalized
        }
    }

    [void](Import-PathAdderLanguagePack)
    return (Get-PathAdderLanguage)
}

# -----------------------------------------------------------------------------
# 4. String lookup
# -----------------------------------------------------------------------------

<#
.SYNOPSIS
    Resolves a localised string by key.
.PARAMETER Key
    Key name, by convention "<module>.<area>.<name>", e.g. 'Core.Msg.DirEmpty'.
.PARAMETER Arguments
    Placeholder arguments matching {0} {1} ... in the text.
.PARAMETER Default
    Fallback used when neither the active language nor English has the key;
    when omitted the key name itself is returned.
.EXAMPLE
    Get-PathAdderText -Key 'Core.Msg.InvalidDir' -Arguments @($dir)
#>
function Get-PathAdderText {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Key,

        [Parameter(Mandatory = $false)]
        [object[]]$Arguments = @(),

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [string]$Default
    )

    Initialize-PathAdderStrings

    $text = $null
    if ($null -ne $global:PathAdderStrings -and $global:PathAdderStrings.ContainsKey($Key)) {
        $text = [string]$global:PathAdderStrings[$Key]
    }

    if ([string]::IsNullOrWhiteSpace($text)) {
        $text = $Default
    }
    if ([string]::IsNullOrWhiteSpace($text)) {
        # Last resort: show the key itself so missing translations are obvious
        $text = $Key
    }

    if ($null -ne $Arguments -and $Arguments.Count -gt 0) {
        try {
            return [string]::Format($text, [object[]]$Arguments)
        } catch {
            return $text
        }
    }

    return $text
}

<#
.SYNOPSIS
    Short alias of Get-PathAdderText for high-frequency UI code.
.EXAMPLE
    T 'Mgr.Title'
    T 'Core.Msg.InvalidDir' @($dir)
#>
function T {
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Key,

        [Parameter(Mandatory = $false, Position = 1)]
        [object[]]$Arguments = @(),

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [string]$Default
    )

    return (Get-PathAdderText -Key $Key -Arguments $Arguments -Default $Default)
}

<#
.SYNOPSIS
    Returns the entries for the language picker drop-down.
.OUTPUTS
    Array of PSObject with Code / DisplayName.
#>
function Get-PathAdderLanguageChoices {
    $choices = New-Object System.Collections.ArrayList
    foreach ($code in $script:PathAdderSupportedLanguages) {
        $display = Get-PathAdderText -Key ('App.Language.' + $code) -Default $code
        [void]$choices.Add((New-Object PSObject -Property @{
            Code        = $code
            DisplayName = $display
        }))
    }
    return $choices.ToArray()
}
