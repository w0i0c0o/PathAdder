# Contributing to PathAdder

Thanks for your interest in contributing! This project is a small, focused Windows tool, but it
has a few **hard rules that are unusual and easy to trip over**. Please read this file fully
before your first PR — especially the encoding rules.

---

## 1. Encoding rules (the #1 way to break this project)

All files live on Windows and are consumed by tools with strict, divergent encoding behavior:

| File type | Encoding | BOM | Why |
|---|---|---|---|
| `.ps1` | UTF-8 | **MUST have BOM** | Windows PowerShell 5.1 reads BOM-less files as ANSI/GBK → all non-ASCII strings become garbage |
| `.cs` | UTF-8 | **MUST have BOM** | Same reason as `.ps1`; the compiler may also read them as ANSI |
| `.bat` | ASCII (English only) | **MUST have NO BOM** | `cmd.exe` chokes on the BOM bytes (`'﻿@echo' is not recognized...`) |
| `.yml` (workflows) | UTF-8 | **MUST have NO BOM** | YAML spec / GitHub parser |
| `.md`, `.json` | UTF-8 | **NO BOM** (convention, keeps things uniform) | — |

**Never write files with `Out-File` or `Set-Content` in PowerShell 5.1** — `Out-File` defaults
to UTF-16LE and `Set-Content` defaults to ANSI. Use this instead:

```powershell
# Write a .ps1/.cs (with BOM):
[System.IO.File]::WriteAllText($path, $content, (New-Object System.Text.UTF8Encoding($true)))

# Write a .md/.json/.yml/.bat (without BOM):
[System.IO.File]::WriteAllText($path, $content, (New-Object System.Text.UTF8Encoding($false)))
```

CI enforces this (BOM checks on every push and PR). If your editor strips or adds BOMs
silently, configure it before touching `.ps1` files.

## 2. PowerShell 5.1 syntax restrictions

The product runs on **Windows PowerShell 5.1** (the version built into Windows), not
PowerShell 7. The following **will not parse on 5.1** and must not appear in any `.ps1`:

- Null-coalescing / null-conditional operators: `??`, `??=`, `?.`
- Pipeline chain operators: `&&`, `||`
- Ternary operator: `$a ? $b : $c`
- `$PSStyle` and other 6+/7+ only features

CI runs the PowerShell parser on **5.1**, so these fail the build. When in doubt, write it the
5.1 way:

```powershell
# BAD (PS7 only):      $x = $maybe ?? 'default'
# GOOD (PS 5.1):       $x = $maybe; if (-not $x) { $x = 'default' }

# BAD (PS7 only):      foo && bar
# GOOD (PS 5.1):       foo; if ($LASTEXITCODE -eq 0) { bar }
```

## 3. Multilingual UI strings

PathAdder is fully bilingual (en-US / zh-CN) with the language packs under `lang\` (8 shards
per language: `core`, `shell`, `picker`, `gui`, `cli`, `setup`, `verify`, `com`).

- **Any user-visible string you add or change must be added to every currently supported
  language in the same change.** No language may be left behind.
- **English (`en-US`) must be completed first** — it is the fallback base; missing keys in
  other languages silently fall back to English.
- Key naming convention: `<module>.<area>.<name>`, e.g. `Gui.Title`, `Setup.AskRestart`.
- Placeholders use .NET composite formatting: `'Added {0} to PATH'` → `T 'Some.Key' $dir`.
- Never rename or delete a key in one language only; renaming means renaming everywhere.
- After changing `lang\` files, run both validation scripts (see §5).

The bilingual documentation (README.md / README.zh-CN.md) follows the same discipline:
chapter structure is 1:1 between the two languages, and any content change lands in both in
the same commit.

## 4. Things you must NOT change

These are load-bearing for compatibility with existing installs. Changing any of them breaks
upgrades or the registered right-click menu:

- **Registry key paths**: `Software\Classes\*\shell\PathAdder`, `HKCU:\Software\PathAdder`,
  `HKLM\...\Environment\Path` access logic.
- **CLSID / COM registration** in `com\*.cs` and `com\register-*.ps1`.
- **The `param` block of `PathAdder.ps1`** (`-Action`/`-Scope`/`-Target`/`-BackupFile`/
  `-Elevated`/`-Language`): this exact command line is written into the user's registry by
  the installer. Changing it makes every existing install's menu stop working.
- **The staged build mechanism in `com\build.ps1`** (copy to `%TEMP%\PathAdderBuild`,
  compile, copy back): it exists because .NET Framework's `csc.exe` fails on non-ASCII source
  paths. Do not "simplify" it away.
- **The `'cs' + 'c.exe'` string concatenation** in `com\build.ps1`: deliberate, do not inline
  it.
- **Existing language-pack key names**: they are referenced by 600+ `T '...'` call sites.

If you believe one of these genuinely needs to change, open an issue first to discuss the
migration path (existing installs, upgrade story).

## 5. Local validation before you push

Run the same checks CI runs:

```powershell
# Language pack parity (en-US vs every other language, all 8 shards)
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Test-LanguagePacks.ps1 -Strict

# Translation key usage: every T '...' / Get-PathAdderText -Key '...' literal must exist in en-US
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Test-TranslationKeys.ps1 -Strict

# Syntax: parse every .ps1 (no execution, no side effects)
powershell -NoProfile -Command "$e=0; Get-ChildItem -Recurse -Filter *.ps1 | Where-Object { $_.FullName -notmatch '\\\.git\\' } | ForEach-Object { $t=$null;$er=$null; [void][System.Management.Automation.Language.Parser]::ParseFile($_.FullName,[ref]$t,[ref]$er); if($er){$e++; Write-Host \"ERR $($_.Name): $($er[0].Message)\"} }; exit $e"
```

For behavior changes, also do a real install round-trip on a Windows machine:
`install.bat` → restart explorer → verify the menu → `verify.bat` (expect exit code 0) →
`uninstall.bat`.

## 6. Commit message convention

Use these prefixes:

| Prefix | For |
|---|---|
| `feat:` | new functionality |
| `fix:` | bug fixes |
| `docs:` | README / LICENSE / comments |
| `ci:` | workflow and validation script changes |
| `chore:` | tooling, repo hygiene, refactors without behavior change |

Example: `fix: preserve REG_EXPAND_SZ kind when restoring from backup`

## 7. Pull request process

1. **Fork** the repository (or create a branch off `main` if you are a collaborator):
   `feat/your-topic` or `fix/your-topic`.
2. **Make your changes**, keeping §1–§4 above in mind.
3. **Bilingual discipline**: if you touched user-visible strings or docs, update **all**
   supported languages / both READMEs in the same commit.
4. **Run the local validations** in §5 — all green.
5. **Open a pull request** against `main` with a short description of what and why. CI will
   automatically run syntax / BOM / language-pack / key-usage checks; the PR must be green
   before review.
6. For behavior changes, mention how you tested (the install round-trip from §5 counts).

---

Again: if in doubt about encodings or the do-not-touch list, ask in an issue first. Those two
areas account for nearly all of this project's historical bugs — we would like to keep it that
way.
