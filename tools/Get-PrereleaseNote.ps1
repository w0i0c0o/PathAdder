# -----------------------------------------------------------------------------
# PathAdder - pre-release note text (tools\Get-PrereleaseNote.ps1)
#
# Target runtime: Windows PowerShell 5.1 (compatible with 3.0+).
# PowerShell 7-only syntax (?? / && / || / ternary / $PSStyle) is FORBIDDEN.
#
# WHY THIS FILE EXISTS
#   Same root cause as tools\Test-I18nSmoke.ps1: GitHub Actions stores every
#   `run:` block in a BOM-less temporary .ps1 and hands it to Windows
#   PowerShell 5.1, which decodes BOM-less files with the active ANSI code page.
#   The bilingual pre-release note used to be written inline in
#   .github\workflows\release.yml, where it reached the process as mojibake and
#   was then substituted into the published release notes verbatim.
#   release.yml has to stay BOM-less (YAML parsers reject a BOM), so the
#   literal lives here, in a UTF-8-with-BOM .ps1, and the workflow merely asks
#   this script for it.
#
# USAGE
#   & .\tools\Get-PrereleaseNote.ps1     # prints the single note line
#   $note = [string](& .\tools\Get-PrereleaseNote.ps1)
#
# EXIT CODES
#   0 = the note was printed
# -----------------------------------------------------------------------------

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

# The literal below MUST stay in this BOM-carrying file - see the header.
$script:PrereleaseNote = '> **PRE-RELEASE / 预发布版本.** This build may still change before the final release. / 该版本在正式发布前仍可能变更。'

Write-Output $script:PrereleaseNote
exit 0
