[English](README.md) | [简体中文](README.zh-CN.md)

# PathAdder — Add a Program's Folder to PATH with One Right-Click

[![License: GPL-3.0-or-later](https://img.shields.io/badge/License-GPL--3.0--or--later-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-Windows%2010%2F11%20x64-0078D6.svg)](#4-requirements)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%20(built%20in)-5391FE.svg)](#4-requirements)
[![i18n](https://img.shields.io/badge/i18n-en--US%20%7C%20zh--CN-green.svg)](#12-language)

A **zero-dependency** tool (Windows PowerShell 5.1 + .NET Framework only): right-click any `.exe` file in File Explorer and add the folder it lives in to your system PATH, so you can run that program straight from the command line.

---

## 1. What It Does

PathAdder adds a **"PATH Assistant"** entry to the right-click menu of every file in File Explorer. Clicking it lets you add or remove the clicked file's folder from your PATH — no manual `setx`, no registry editing, no admin console.

- Admin-free installation (writes only to `HKCU`, never touches system directories)
- **Automatic backup** before every PATH change — roll back at any time
- Supports user-level and system-level PATH; system-level self-elevates through UAC
- Built-in **PATH Manager** GUI: browse entries, backup history, restore, change log

## 2. Features

| Feature | Description | Requires admin |
|---|---|---|
| Add folder to PATH (user) | Right-click a file → add its folder to the user PATH (`HKCU\Environment\Path`) | No |
| Add folder to PATH (system) | Same, written to `HKLM\...\Session Manager\Environment\Path` via UAC self-elevation | Yes |
| Remove folder from PATH | Removes it from both user and system PATH | User: no / System: yes |
| Automatic backup | One plain-text backup before every change, restorable from the GUI | No |
| Change log | Human-readable, machine-parseable log of every PATH change | No |
| PATH Manager GUI | Browse, restore, inspect backups and the change log | No |
| Bilingual UI | English (en-US) and Simplified Chinese (zh-CN), switchable at runtime | No |
| Zero dependencies | Uses only what Windows already ships: PowerShell 5.1 + .NET Framework | — |

## 3. Screenshots

<!-- TODO(T05): add real screenshots to docs/images/ and replace this block.
<img src="docs/images/context-menu.png" alt="PATH Assistant context menu" width="480">
<img src="docs/images/path-manager.png" alt="PATH Manager window" width="480">
-->

> **Coming soon.** Planned screenshots: `docs/images/context-menu.png` (right-click menu),
> `docs/images/path-manager.png` (PATH Manager GUI), `docs/images/language-switch.png`
> (language dropdown). They will be added after the first release.

## 4. Requirements

| Requirement | Detail |
|---|---|
| Operating system | Windows 10 (1809 or later) or Windows 11, **x64 only** (the shell extension DLL targets the 64-bit explorer process) |
| Runtime | Windows PowerShell 5.1 — built into Windows, **nothing to install** |
| Privileges | **User-level install needs no administrator rights** (writes only to `HKCU`). System-level PATH changes require admin — the tool elevates through UAC on demand |
| Disk space | A few hundred KB |
| Network | Not used at all |

## 5. Quick Start

### A. Download a release (recommended)

1. Go to [Releases](https://github.com/w0i0c0o/PathAdder/releases) and download
   `PathAdder-vX.Y.Z-win-x64.zip`.
2. Extract it anywhere (you get a single `PathAdder-vX.Y.Z\` folder).
3. Double-click **`install.bat`**.
4. When the installer asks, restart File Explorer (see
   [§6 Where to Find the Menu](#6-where-to-find-the-menu-read-this-first)).

> **Extract to the folder you intend to keep, and do not move it afterwards.**
> The COM shell extension is registered with an **absolute** DLL path (`CodeBase`), so
> relocating the folder breaks the right-click menu. If you already moved it, just re-run
> `com\register-com.ps1` from the new location — see [Q8](#q8-the-menu-worked-then-vanished-after-i-moved--renamed--updated-the-pathadder-folder).

> Prefer the command line?
>
> ```powershell
> powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File ".\install.ps1"
> ```

### B. From source

```powershell
git clone https://github.com/w0i0c0o/PathAdder.git
cd PathAdder
.\install.bat
```

The release zip ships with a pre-compiled shell extension DLL. If you clone the source, you
either build the DLL once yourself (see
[§18 Building the Shell Extension from Source](#18-building-the-shell-extension-from-source))
or run `install.ps1` first — the PowerShell-side right-click menu works without the DLL; the
compiled extension is the COM-based layer on top.

## 6. Where to Find the Menu (READ THIS FIRST)

After installing, right-click **any file** and look for **"PATH Assistant"**. Two things trip
everyone up:

### 6.1 Windows 11: click "Show more options" first

Windows 11 folds the classic right-click menu into the second layer of its layered menu;
**the first layer only shows a few fixed items** (Copy / Paste / Delete / Rename / Properties,
etc.), and "PATH Assistant" is **not** in that first layer. **This is normal — the menu is there.**

Any of these reaches it:

- **Right-click** the file → click **"Show more options"**;
- **Select** the file, then press **`Shift` + `F10`**;
- Select the file, then press **`Shift` + arrow keys** to expand the classic menu;
- Trackpad/keyboard: once the menu pops up, press **`Shift` + `F10`** or the left arrow key.

On Windows 10 and earlier, a plain right-click shows it directly. **Always open "Show more
options" before concluding that the menu is missing.**

### 6.2 After installing: restart File Explorer

The installer writes the registry, but **the right-click menu usually does NOT appear
immediately — this is normal, not a failed installation.** File Explorer caches menus and file
associations. `install.ps1` does send a `SHChangeNotify(SHCNE_ASSOCCHANGED)` notification, but
**on Windows 11 this notification does not always take effect**; in practice you must restart
the explorer process or log off and back on before the entry really shows up.

Complete one of these:

```powershell
Stop-Process -Name explorer -Force; Start-Process explorer.exe
```

Or simply **log off the current Windows account and log back in**.

> At the end of the installation the script will **ask you with a dialog** whether to restart
> Explorer right away (the default button is "No"). Because restarting closes every open folder
> window, the script **never restarts without asking**. Scripted invocations can control this:
>
> | Switch | Behavior |
> |---|---|
> | (default, neither specified) | Ask with a dialog, defaulting to "No" |
> | `-RestartExplorer` | Restart immediately without asking (for batch deployment) |
> | `-NoRestart` | Do not ask and do not restart |
>
> ```powershell
> install.ps1 -RestartExplorer   # restart immediately
> install.ps1 -NoRestart         # leave File Explorer completely untouched
> ```

## 7. How to Use the Menu

Right-click **any file** (any type, including `.exe`) and a **"PATH Assistant"** entry appears
in the menu. **Clicking** it pops up this tool's action menu at the mouse position:

| Menu item | Effect | Requires admin |
|---|---|---|
| Add to PATH (current user) | Writes to `HKCU\Environment\Path` | No |
| Add to PATH (system-wide, admin) | Writes to `HKLM\...\Session Manager\Environment\Path` | Yes (UAC prompt) |
| Remove this directory from PATH | Removes it from both user and system PATH | User: no / System: yes |
| Open PATH Manager | Opens the GUI management window | No (required when touching system PATH) |

The top row of the menu is a **grey, non-clickable** directory name, so you can confirm which
directory the action applies to.

All 4 actions are grouped under **a single parent menu item**, so the top-level menu only takes
one row and does not clutter your other menu entries.

> ℹ️ **About "click" instead of "hover"**
>
> Early versions of this tool used Windows' native `SubCommands` static cascade
> (auto-expanding on mouse hover), but **that failed in real testing on Windows 11**: the parent
> item showed up, **hovering never expanded anything**, and because that mechanism requires the
> parent to have no `command`, **clicking did nothing either** — the feature was completely
> unusable. See [§16.2](#162-submenu-why-subcommands-was-dropped-for-click-to-pop-up).
>
> The current version therefore uses "click → pop up a menu at the cursor position". The look
> and feel are essentially the same as a native right-click submenu, and it does not depend on
> Explorer's cascade implementation, so reliability is 100%. The price is one extra click.

### Verifying the installation

Double-click **`verify.bat`**, or run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File ".\verify-registration.ps1"
```

It checks on several layers: the parent menu structure and its `command` subkey, whether the
HKLM-side system menu is intact, whether anything is left behind at historical locations,
whether the default verb was modified by mistake, whether third-party menus were damaged — and
it tries Shell COM to **really enumerate** the right-click menu once (one `.exe` and one
`.txt`). See [§16.10](#1610-verification-script-verify-registrationps1).

> Note: the verification script can only validate "the registry and Shell side of things". If
> you **have not restarted File Explorer yet**, the script may report a complete structure while
> the menu has not been built — finish the restart step in [§6](#6-where-to-find-the-menu-read-this-first)
> before looking at the menu.

## 8. Usage Example

Suppose: `D:\Tools\ffmpeg-6.0\bin\ffmpeg.exe`

1. Right-click `ffmpeg.exe` → **"Add to PATH (current user)"**
2. A dialog says `Successfully added to [User PATH (current user)]`, and shows the directory
   `D:\Tools\ffmpeg-6.0\bin` plus the backup file name
3. **Open a new** cmd / PowerShell window and type `ffmpeg -version` — it just runs

> Command-line windows that are already open do not pick up the change automatically; you need
> to reopen them (the tool broadcasts `WM_SETTINGCHANGE`, so File Explorer and most programs
> refresh on their own).

To undo: right-click the same `.exe` → **"Remove this directory from PATH"**; user-level and
system-level are both handled. If elevation fails for the system level, only the user level is
processed and you get an explicit message.

## 9. PATH Manager (GUI)

Open it from the menu ("Open PATH Manager"), or double-click `PathManager.ps1`:

```powershell
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File ".\PathManager.ps1"
```

The window has four functional areas:

| Area | What it does |
|---|---|
| User PATH / system PATH lists | Numbered view of the actual PATH values; system list is read-only unless elevated |
| Backup history | Preview any backup, **restore to this backup** (restores re-backup first, so a restore is itself rollback-able), refresh |
| Change log | Last 200 entries, newest first — open the raw `change.log` too |
| Language dropdown (top-right) | Switches the UI language in place and persists the choice (see [§12](#12-language)) |

Buttons for refresh, opening the backup folder, opening the change log, and closing sit at the
bottom of the window.

## 10. Uninstall

Double-click **`uninstall.bat`**, or:

```powershell
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File ".\uninstall.ps1"
```

Uninstalling cleans **every location** (current location + two historical locations), see the
table below:

| # | Location | What is removed |
|---|---|---|
| 1 | `HKCU\Software\Classes\*\shell\PathAdder` | Current version's cascade menu (the whole subtree) |
| 2 | `HKCU\Software\Classes\exefile\shell\PathAdder*` | 4 items registered flat by early versions |
| 3 | `HKCU\Software\Classes\SystemFileAssociations\.exe\shell\PathAdder*` | 4 fallback items registered by early versions |

This way, even if you installed an old version, upgrading will not leave orphan menu items
behind. After uninstalling you **also need to restart File Explorer** before the entry
disappears from the menu (the script will ask whether it should restart for you).

Uninstalling only removes the right-click menu; **backups and logs are kept** in
`%LOCALAPPDATA%\PathAdder\` so you can roll back at any time. Delete that directory manually if
you want a complete cleanup.

## 11. Backups and Logs

- Backup folder: `%LOCALAPPDATA%\PathAdder\backups\`
- Naming: `<scope>-<yyyyMMdd-HHmmss>.txt`, e.g. `user-20261002-070000.txt`,
  `system-20261002-070000.txt`
- Repeated operations in the same second get a sequence number appended:
  `user-20261002-070000-1.txt`
- Change log: `%LOCALAPPDATA%\PathAdder\change.log`

  Log line format (human readable, also machine parseable):

  ```
  [2026-10-02 07:00:00] action=Add scope=User dir=D:\Tools\bin backup=user-20261002-070000.txt kind=ExpandString
  ```

- **Restore:** in "PATH Manager → Backup history" select a backup and click "Restore to this
  backup". The current PATH is **backed up again** before restoring, so a restore is itself
  rollback-able.

## 12. Language

PathAdder ships a PowerShell-side i18n layer plus a C#-side string table. This section is the
outside-facing description of that mechanism.

### 12.1 Default and supported languages

- **Default language: English (`en-US`).**
- Currently supported: **English (`en-US`)** and **Simplified Chinese (`zh-CN`)**.
- `en-US` is also the **fallback base**: any key missing from another language automatically
  falls back to English (see §12.4).

### 12.2 Three ways to switch language

| # | Method | Notes |
|---|---|---|
| 1 | **Language dropdown at the top-right of the PATH Manager window** (recommended) | Takes effect immediately and is persisted automatically; this is the only method that also writes the config file and registry for you |
| 2 | Command line: `Set-PathAdderLanguage -Language zh-CN` | Provided by `lib\i18n.ps1`; normalizes the code, reloads the language pack, and persists the choice |
| 3 | Environment variable `PATHADDER_LANG` | Highest priority; useful for one-off runs and for subprocesses spawned by the COM shell extension |

```powershell
Set-PathAdderLanguage -Language zh-CN    # switch to Simplified Chinese
Set-PathAdderLanguage -Language en-US    # switch back to English

$env:PATHADDER_LANG = 'zh-CN'            # one-off override via environment variable
```

### 12.3 Language resolution priority

Resolved strictly in this order; the first hit wins:

1. Environment variable **`PATHADDER_LANG`**
2. The **`language`** field of **`%LOCALAPPDATA%\PathAdder\config.json`**
3. Registry **`HKCU\Software\PathAdder\Language`**
4. The **system UI language** (`CultureInfo.CurrentUICulture`)
5. **`en-US`** (final fallback)

> The registry value exists so that the COM shell extension running inside `explorer.exe` —
> which does not inherit your shell's environment variables or your script scope — can still
> read the active language.

### 12.4 Language pack layout

```
lang\
├── en-US\          # English (US) — fallback base, always complete
│   ├── core.ps1
│   ├── shell.ps1
│   ├── picker.ps1
│   ├── gui.ps1
│   ├── cli.ps1
│   ├── setup.ps1
│   ├── verify.ps1
│   └── com.ps1
└── zh-CN\          # Simplified Chinese
    └── (same 8 shards)
```

- Path pattern: **`lang\<language-code>\<shard>.ps1`**
- Each file is a single assignment of one hashtable:

  ```powershell
  $PathAdderStrings = @{
      'Key'       = 'Text'
      'Other.Key' = 'Other text'
  }
  ```

- Shards are split by module: **`core` / `shell` / `picker` / `gui` / `cli` / `setup` / `verify`
  / `com`**.
- Loading merges `en-US` first and then overlays the selected language on top, so **any key
  missing from the selected language falls back to English** automatically. A partially
  translated language never produces empty UI text.

### 12.5 Adding a new language

Follow these steps in order:

1. **Register the language code** in `lib\i18n.ps1`: add it to
   `$script:PathAdderSupportedLanguages` and make sure
   `Get-PathAdderSupportedLanguages()` returns it.
2. **Add a normalization rule** in `ConvertTo-PathAdderLanguage()` (in `lib\i18n.ps1`) that
   maps the loose forms `xx` and `xx-YY` onto your canonical code (same pattern as
   `en`/`en-*` → `en-US`, `zh`/`zh-*`/`chinese`/`cn` → `zh-CN`).
3. **Copy `lang\en-US\` to `lang\<code>\`** and translate all **8** shard files
   (`core`, `shell`, `picker`, `gui`, `cli`, `setup`, `verify`, `com`).
4. **Add the display name** `App.Language.<code>` to the language pack (`core.ps1` of every
   supported language, `en-US` first). This is the name shown in the language dropdown.
5. **Right-click menu display names are written into the registry.** They are baked in at
   registration time, so after switching language you must **re-run the install/registration
   script** (`install.ps1`, or `com\register-contextmenu.ps1` for the COM extension) and
   restart File Explorer before the menu text refreshes.
6. **C# COM shell extension strings are embedded in the `L10n` class inside
   `com\PathAdderShellExt.cs`** — they do not come from the `.ps1` language packs. Adding a
   language means **adding a column there and recompiling the DLL** (see
   [com\README-COM.md](com/README-COM.md)).

### 12.6 Maintenance rules

- Any user-visible text that is **added or changed must be added to every currently supported
  language in the same change** — no language may be left behind.
- **English must be completed first**, because it is the fallback base: until a key exists in
  `en-US`, other languages have nothing to fall back to and the UI can end up blank.
- Never delete or rename a key in one language only; renaming a key means renaming it in
  `en-US` and in every other pack.

See also [CONTRIBUTING.md](CONTRIBUTING.md) for the contributor-facing version of these rules.

## 13. How PATH Changes Are Made

Understanding what the tool writes (and what it deliberately does not):

- **Where**: user PATH lives at `HKCU\Environment\Path`; system PATH at
  `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Control Session Manager` →
  `Environment\Path`. The tool appends **one entry** or removes **matching entries**; every
  other entry is left byte-for-byte untouched.
- **Value type preserved**: `Path` may be `REG_EXPAND_SZ` or `REG_SZ`. The tool reads the
  value kind and writes back with the **original type** (see §16.6). `SetEnvironmentVariable`
  with a Machine/User target would silently downgrade `REG_EXPAND_SZ` to `REG_SZ` — the tool
  never uses it for writes (see §16.8).
- **Backup first**: before any write, the whole current value is saved to
  `%LOCALAPPDATA%\PathAdder\backups\` (see [§11](#11-backups-and-logs) for naming and restore).
- **Broadcast**: after writing, the tool rebuilds its own process PATH and broadcasts
  `WM_SETTINGCHANGE` so File Explorer and open programs pick up the change (see §16.8).
  Already-open consoles still need to be reopened.
- **Duplicate-safe**: existing entries are compared after normalization
  (`%VAR%` expansion, slash normalization, trailing-backslash strip, case-insensitive); a
  duplicate add returns `AlreadyExists` and touches nothing (see §16.7).
- **Logs**: every change appends a line to `%LOCALAPPDATA%\PathAdder\change.log`
  (see [§11](#11-backups-and-logs)).

## 14. Troubleshooting / FAQ

**Q1: I installed it but cannot see the menu on right-click?**

Troubleshoot in **this order** (the first two cover 95% of cases):

1. **Restart File Explorer first** — this is the most common cause, by far.
   On Windows 11 the `SHChangeNotify` notification often fails to take effect, and you must
   restart explorer before the entry appears:

   ```powershell
   Stop-Process -Name explorer -Force; Start-Process explorer.exe
   ```

   Or **log off the current Windows account and log back in**. See [§6.2](#62-after-installing-restart-file-explorer).

2. **On Windows 11 you need to click "Show more options"** (or press `Shift+F10` after
   selecting the file). "PATH Assistant" lives in the classic menu, not in the first layer.
   **Open "Show more options" before drawing conclusions** — do not call it missing after only
   glancing at the first layer. See [§6.1](#61-windows-11-click-show-more-options-first).

3. **Make sure you right-clicked a file** (not empty space in a folder, not the desktop
   background). This tool registers on `*`, which applies only to **file objects**.

4. **Run the verification script** to confirm registration really took effect, and read the
   specific failures it reports:

   ```powershell
   powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File ".\verify-registration.ps1"
   ```

5. If the verification script reports "the parent item has a command subkey", the cascade will
   be broken (clicking does nothing) — re-running `install.ps1` fixes it automatically.

6. If it reports a complete structure but cannot enumerate the menu, that is most likely an
   environment limitation (container / remote session); confirm in a normal desktop session.

**Q2: It says "administrator privileges required"?**
A: Choose "Add to PATH (current user)" — that needs no admin. System-level PATH requires admin;
if you cancel UAC, the tool tells you explicitly and **changes nothing**.

**Q3: The program is still not found on the command line?**
A: PATH only takes effect in **newly opened** windows. Close and reopen cmd / PowerShell /
Windows Terminal.

**Q4: I added the wrong directory, what now?**
A: Right-click that `.exe` → "Remove this directory from PATH"; or open "PATH Manager → Backup
history", pick the backup taken before the change, and click "Restore to this backup".

**Q5: Will it break my existing PATH?**
A: No. The tool only "appends one entry" or "removes matching entries"; everything else is kept
as is; it backs up before every change; and if writing fails it keeps the backup and reports,
leaving no half-finished state.

**Q6: Will backup files pile up?**
A: Every operation writes one plain-text backup (usually a few KB); you can clean them up
yourself via "PATH Manager → Open backup folder". Keeping the most recent few is enough.

**Q7: My antivirus blocks the scripts?**
A: This tool does not access the network, does not inject anything, and does not write to
system directories; it only edits the PATH environment variable and the right-click menu under
`HKCU`. Add it to the whitelist if it gets blocked.

**Q8: The menu worked, then vanished after I moved / renamed / updated the PathAdder folder?**

A: This is expected behavior of the COM shell extension, and it is easy to fix.

`com\PathAdderShellExt.dll` is registered as an in-process COM server. Windows stores its
location in the registry as the **`CodeBase`** value under
`HKLM\Software\Classes\CLSID\{9B3E5D2A-7C41-4F8B-A1D6-2E5C8F40B7A3}\InprocServer32`
(and again under the version subkey `0.0.0.0`). **That value is an absolute path**, so moving
the folder does not move the registration: the CLSID still points at the old location, Windows
cannot load the DLL, and the menu entry silently disappears (or stays visible but does nothing).

Fix it by re-registering from the **new** location:

```powershell
# Run from the new PathAdder folder, elevated
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\com\register-com.ps1"
Stop-Process -Name explorer -Force; Start-Process explorer.exe
```

To avoid the problem entirely: **do not move the folder after installing.** Extract the release
archive to its final location first (for example `C:\Tools\PathAdder`), then register from there.

The same applies when you replace the DLL with a newer build by hand — if the new copy lives
elsewhere, re-run the registration script so `CodeBase` follows it.

## 15. Known Limitations

1. **PATH length**: Windows imposes a length limit on the registry `Path` value (classically
   about 2047 characters, relaxed to 32K on some systems). If you are already near the limit,
   writing may fail — the tool catches this and reports it rather than silently truncating.
2. **You must restart File Explorer**: this is the **number one** reason for "the menu does not
   appear" (more common than item 3 below). On Windows 11 the `SHChangeNotify` notification is
   often not enough; you must restart explorer or log off and back on. See
   [§6.2](#62-after-installing-restart-file-explorer).
3. **Windows 11 layered menu**: the entries live in the classic menu ("Show more options" /
   `Shift+F10`); this is system behavior, not a tool limitation. Open "Show more options"
   before drawing conclusions.
4. **Default verb**: for safety the tool **never writes a default verb at any location** (it
   would make double-clicking a file stop opening it). `-MakeDefault` is deprecated to a no-op.
   See §16.3.
5. **The submenu is "click to expand", not "hover to expand"**: this is a deliberate
   trade-off, not a defect.
   Windows' native `SubCommands` hover cascade was **measured to not expand on Windows 11**
   (the parent is visible, hovering does nothing, and because that mechanism requires the
   parent to have no `command`, clicking is ineffective too), leaving all four functions
   unreachable. The current design pops up a menu at the cursor after a click: 100% reliable,
   at the cost of one extra click. See
   [§16.2](#162-submenu-why-subcommands-was-dropped-for-click-to-pop-up). To get a real hover
   cascade back, the only way out is implementing an `IExplorerCommand` COM shell extension
   (requires writing and registering a COM DLL), which is far more work.
6. **Backup granularity**: a backup records only the value of the single `Path` entry, not
   other environment variables.
7. **P/Invoke broadcast depends on `Add-Type`**: in minimal/restricted environments without
   the C# compiler, both the `WM_SETTINGCHANGE` broadcast and the `SHChangeNotify` refresh are
   skipped (PATH writing and menu registration still complete correctly; you just have to
   restart File Explorer manually).
8. **System PATH removal**: if you are not an admin and decline UAC, only the user-level
   removal is performed and reported — it is never skipped silently.
9. **`Start-Process` throws on machines with duplicate environment-variable keys differing
   only in case**: if your environment contains `Path`/`PATH`, `http_proxy`/`HTTP_PROXY` or
   similar keys that differ only in case, launching this tool with `Start-Process` (whose
   default is `UseShellExecute = $false`) fails because .NET cannot build the environment
   block. This is not a problem with this tool. Workarounds: use
   `Start-Process -UseShellExecute`, or use the tool's own `Start-PathAdderScript` (which
   explicitly sets `UseShellExecute = $true`), or clean up the duplicate environment-variable
   keys first.
10. **The verification script cannot complete layer 2 in restricted environments**: in some
    containers / trimmed-down systems / remote sessions, Shell COM's
    `SHCreateItemFromParsingName` returns `E_NOINTERFACE (0x80004002)` for every interface ID,
    making real menu enumeration impossible. The script automatically degrades to merged-view
    inference and **honestly flags the evidence as insufficient** (exit code 2); it never gives
    a false-positive conclusion.
11. **The installation folder must not be moved after registering**: the COM `CodeBase`
    registration stores an **absolute** DLL path, so relocating the folder breaks the right-click
    menu until you re-run `com\register-com.ps1`. See
    [Q8](#q8-the-menu-worked-then-vanished-after-i-moved--renamed--updated-the-pathadder-folder).

## 16. How It Works (Implementation Notes)

> This chapter preserves the original implementation-decision notes: two rounds of real bugs
> and the reasoning behind every load-bearing design choice.

### 16.1 Registration Location: `HKCU\Software\Classes\*\shell\PathAdder`

> **This section documents two rounds of real bugs and their fixes.** If you hit "installation
> succeeds, the keys and values in the registry are all present, but the right-click menu never
> appears", the cause is almost always here.

#### Current location: `*` = all file objects

```
HKCU\Software\Classes\*\shell\PathAdder
```

`HKCR\*` is the officially supported Windows association key for "**all file objects**"; it
covers any extension unconditionally (including `.exe`). That way right-clicking any file
works, with no need to register once per extension.

#### Bug one (early versions): registered only under `SystemFileAssociations\.exe\shell`

Back then the registry looked perfectly fine — all 4 subkeys present, `(Default)`/`MUIVerb`/
`command` all there, and the script referenced by the command line really existed. Yet **File
Explorer never displayed the menu**.

Root cause (measured on this machine):

```
HKCR\.exe\(Default)   = exefile          <-- .exe has an associated ProgID
HKCR\exefile\shell    = open / runas / runasuser / ...
HKCR\SystemFileAssociations\.exe\shell = only this tool's verb
```

Per Windows' file-type menu composition rules, `SystemFileAssociations\.xxx` is the
**fallback** path that is only used **when the extension has no associated ProgID**. Once an
extension does have an associated ProgID, File Explorer uses that ProgID's `shell` as the
trunk and skips the fallback path entirely. `.exe` is associated with `exefile`, so Explorer
reads only `exefile\shell` and never reads `SystemFileAssociations\.exe\shell`.

**This is not a caching / permission / 32-64 redirection / group policy problem — the
registration location was simply wrong.**

#### Bug two (mid versions): registered under `exefile\shell`, working only for `.exe`

Bug one was fixed, but the menu disappeared whenever the user right-clicked something that was
not an `.exe`.

#### Final solution and how the two historical locations are handled

| Location | Disposition | Reason |
|---|---|---|
| `*\shell\PathAdder` | **In use now** | `*` covers all files (incl. .exe); a single registration point is cleanest |
| `exefile\shell\PathAdder*` | **Removed** | `*` already covers .exe; registering both would show two copies of the same action |
| `SystemFileAssociations\.exe\shell\PathAdder*` | **Removed** | It was only a fallback for "when .exe has no associated ProgID"; once `*` covers all files unconditionally, that fallback is meaningless |

> **On whether to keep the SystemFileAssociations fallback: remove it entirely.**
> Its only reason to exist was "in case .exe has no associated ProgID". But `*` takes effect
> **unconditionally** — it holds for any file object and never goes through ProgID association
> resolution, so there is no risk of "the menu disappearing because .exe has no ProgID". Since
> `*` already covers every case unconditionally, this SystemFileAssociations entry is pure
> redundancy; removing it drops the number of registration points from 2 to 1 and makes
> duplicate menus or missed cleanups far less likely.

**⚠ Uninstalling must clean all three locations** (current + two historical), otherwise users
upgrading from an old version will keep orphan menu items. `uninstall.ps1` iterates through
`Get-PathAdderShellCleanupLocations` and this has been verified in practice.

#### Why user-level registration is safe

`HKCR` is a **merged view** of `HKCU\Software\Classes` and `HKLM\Software\Classes`, merged item
by item for both "values" and "subkeys": for identical value names HKCU wins, and subkeys with
the same name coexist on both sides.

This tool **never writes to HKLM** and **never modifies** any system value under `*\shell` /
`exefile\shell` — **in particular it never writes a default verb** (see §16.3).

### 16.2 Submenu: Why SubCommands Was Dropped for Click-to-Pop-Up

#### The trap: `SubCommands` does not expand on hover under Windows 11

The first version used Windows' native **static cascade (`SubCommands`)** to pack the 4
actions under a parent menu:

```
HKCU\Software\Classes\*\shell\PathAdder
    SubCommands = "PathAdder.AddUser;PathAdder.AddSystem;PathAdder.Remove;PathAdder.Manager"
    └─ shell\PathAdder.AddUser\command = …
```

**Measured result: it fails on Windows 11.** Symptoms:

- The parent item "PATH Assistant" **displays normally**;
- **Hovering never expands** the submenu;
- Because that mechanism requires the parent to have no `command` subkey, **clicking does
  nothing either**;
- Net result: **not one of the 4 functions can be clicked**.

**Root cause:** Windows 11 introduced a new context-menu pipeline in which classic registry
verbs are wrapped into `ExplorerCommand verb` before being rendered. That wrapper's support
for the `SubCommands` static cascade is incomplete, so cascade expansion is never triggered.
The more third-party `IExplorerCommand` extensions are installed, the more visible the failure
becomes (this machine has several COM-based extensions: VLC, Git, Meitu, a cloud drive client,
and so on).

> One counter-intuitive detail: `SubCommands` and "the parent has a `command`" are **mutually
> exclusive** — as soon as the parent has a `command`, Windows treats it as an ordinary item
> and `SubCommands` is ignored completely. So "add a fallback `command` to the parent" cannot
> work; you must pick one or the other.

#### Current design: click the parent → pop up a native-style menu at the cursor

```
HKCU\Software\Classes\*\shell\PathAdder
    (Default)          = "PATH Assistant"
    MUIVerb            = "PATH Assistant"
    Icon               = "…\powershell.exe,0"
    NoWorkingDirectory = ""
    └─ command\(Default) = powershell … -File "…\MenuPicker.ps1" -Target "%V"
```

After `MenuPicker.ps1` receives `%V`:

1. It takes the directory containing the target file and shows it as the **grey,
   non-clickable** description row at the top of the menu (so the user can confirm the
   object);
2. It pops up a WinForms `ContextMenuStrip` at `[Cursor]::Position`;
3. Once the user picks an item, it hands over to `PathAdder.ps1` to perform the real action
   (`Add` / `Remove` / `OpenManager`).

**Trade-off:** one extra mouse click buys **independence from Explorer's cascade
implementation and 100% reliability**. On Windows 11 this is the only design that works
consistently.

If you ever want real "hover to expand" back, the only way out is implementing an
`IExplorerCommand` COM shell extension (registering `ExplorerCommandHandler`), which means
writing and registering a COM DLL — far more work and maintenance cost.

**Upgrade compatibility:** installation automatically clears the `SubCommands` value and the
`…\shell\` subcommand tree left behind by the previous version, so upgrading from an old
version does not require uninstalling first.

#### About `Position = "Bottom"`: not adopted

MSDN samples occasionally show `Position = "Bottom"`, and it may feel natural to sink the
entry to the bottom of the menu. This project **does not** add it, because **discoverability
beats menu tidiness**:

1. Grouping into a parent menu already cut the top-level footprint from 4 rows to 1, so the
   tidiness goal is met;
2. `Bottom` pushes the item next to the "Properties" group, and users of this tool have
   already suffered from "I cannot find the menu" — **reducing visibility here is the wrong
   direction**;
3. The default position, in the middle of the menu, is easier to spot.

If you do need it, just add a `Position` value on the parent item; no code restructuring
required.

### 16.3 Never Writing a Default Verb (`-MakeDefault` Is Deprecated)

> ⚠️ **This tool never writes a default verb, at any location.**

The default verb (the parent key's `(Default)`) determines a file's **double-click behavior**.
Changing it to our menu item means **double-clicking any file no longer opens it but pops up a
PATH dialog** — extremely destructive, and almost certainly not what the user wanted.

- The `-MakeDefault` switch is **retained** (backward compatibility) but is now **completely
  inert**; it only prints an explanatory note;
- The `(Default)` of `*\shell` and `exefile\shell` is **never written or cleared** by this
  tool;
- `verify-registration.ps1` has a dedicated **default verb safety check**: if the default
  value ever becomes `PathAdder*`, it fails immediately and demands a fix.

### 16.4 Passing `%V` to the Menu Instead of `%1`

```text
powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "...\PathAdder.ps1" -Action Add -Scope User -Target "%V"
```

Reasons:

- `%V` (the verb parameter) **always passes a long file name** on Windows Vista and above,
  which is the most robust choice for paths containing non-ASCII characters or spaces;
- `%1` is converted to an 8.3 short name (e.g. `D:\TOOLS~1\BIN`) in some legacy scenarios,
  which can lose non-ASCII directory names;
- Belt and braces: the script additionally uses `GetLongPathName` (P/Invoke) to restore short
  names and then normalizes with `GetFullPath`.
- The script receives a **file path** and converts it to the containing directory internally
  with `[System.IO.Path]::GetDirectoryName()`.

#### Validating the `-Target` argument (preventing the current working directory from being added by mistake)

In **Add** scenarios `-Target` must pass three checks, otherwise the script errors out and
PATH is not touched at all:

1. **It must be a true absolute path** (`-RequireAbsolute`): relative paths and
   drive-relative forms (such as `C:`) are rejected, so the result never depends on the
   script's CWD;
2. In Add scenarios: **it must really exist** (file or directory), preventing bogus arguments
   from adding something wrong;
3. **Garbage input is intercepted**: strings made only of whitespace, dots or slashes, such as
   `'...'`, `'.'`, `'   '`, are explicitly rejected.

> This step is required: `[System.IO.Path]::GetFullPath('...')` silently returns the **current
> working directory**. Without the check, `...` would be treated as a legitimate directory and
> the PowerShell process's CWD would be written into PATH.

> Likewise, the drive-relative form `C:` is expanded by `GetFullPath` as "the current directory
> on drive C", which also depends on the process CWD. That is why `Path.IsPathRooted()` is
> **not** used here (it counts `C:` as absolute); only two CWD-independent forms are accepted:
> drive + separator (`C:\`, `C:/`) and UNC (`\\server\share`).

> **Note:** the three rules above mainly constrain **Add**. **Remove deliberately relaxes the
> existence check** (internal `-AllowMissing`) so you can clean up stale PATH entries whose
> directories were deleted long ago but are still listed in PATH; Remove still requires a true
> absolute path, and garbage input is rejected there too.
>
> The library function `Remove-DirectoryFromPath` also takes `-RequireAbsolute` (defense in
> depth): otherwise, in a right-click "Remove", `C:` would be expanded against the CWD and
> then **silently delete** the legitimate PATH entry that happens to equal that CWD —
> unacceptable destruction that must be blocked at the lowest level.

### 16.5 UAC Self-Elevation

- Detection: `WindowsPrincipal.IsInRole(WindowsBuiltInRole.Administrator)`;
- Elevation: build a `ProcessStartInfo` with **`Verb = 'runas'`** + `UseShellExecute = $true`,
  relaunch itself via
  `powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File`, and append an
  `-Elevated` flag to prevent infinite elevation loops;
- **All three conditions are mandatory**: without `Verb = 'runas'` you merely "open another
  PowerShell with the current user's rights" (no UAC prompt, the child's `ISADMIN` is still
  False, and writing system PATH is guaranteed to fail); without `UseShellExecute = $true` the
  `Verb` is silently ignored;
- **Failure handling:** wrap in `try/catch` (clicking "No" in UAC throws a `Win32Exception`)
  and show a friendly "System PATH was not modified" message — no crash, no half-finished
  state.

### 16.6 Preserving the PATH Value Type (`REG_EXPAND_SZ` / `REG_SZ`)

The `Path` value can be either `REG_EXPAND_SZ` or `REG_SZ`. The read/write flow:

1. `GetValue('Path')` reads the value;
2. `GetValueKind('Path')` reads the type;
3. `SetValue('Path', newValue, originalType)` writes it back.

The type is recorded in the log as well, and restoring a backup prefers the original type from
the log.

> Implementation note: the `Microsoft.Win32.RegistryValueKind` member is named
> **`ExpandString`**, not `ExpandSz`. In PowerShell 5.1 writing
> `[RegistryValueKind]::ExpandSz` does not raise an error — it silently returns `$null`,
> which then makes overload resolution fail for `SetValue(name, value, kind)`. This tool
> therefore always maps safely through `ConvertTo-RegistryValueKind` /
> `ConvertTo-RegistryValueKindName`.

### 16.7 Duplicate Comparison (Avoiding Re-Adding)

Normalize first, then compare:

1. Trim leading/trailing whitespace and quotes;
2. `ExpandEnvironmentVariables()` expands any `%XXX%` inside;
3. Normalize `/` to `\`;
4. Strip the trailing backslash (except for a drive root such as `C:\`);
5. Case-insensitive (`ToLowerInvariant()`).

On a hit it **returns immediately** with `AlreadyExists` — nothing is written to the registry
and no backup is created.

### 16.8 Broadcasting the Environment Change

After writing the registry:

- `SetEnvironmentVariable('Path', $combined)` — **Process target only (the default overload);
  it just updates the current process's memory and never writes back to the registry**;
- Rebuild the current process's `$env:Path` (reassembled from Machine + User in the registry);
- P/Invoke
  `SendMessageTimeout(HWND_BROADCAST, WM_SETTINGCHANGE, 0, "Environment", SMTO_ABORTIFHUNG, 5000, ...)`
  so File Explorer and already-open programs pick up the change.

> ⚠️ Implementation trap: **do not** switch to the overload that takes
> `EnvironmentVariableTarget.User` / `.Machine`.
> That overload **writes back to the registry** and silently downgrades `REG_EXPAND_SZ` to
> `REG_SZ`, directly breaking §16.6's "preserve the original value type" requirement. This
> tool therefore uses the Process target only.

P/Invoke goes through `Add-Type` compilation; if compilation fails it degrades gracefully
(just skips the broadcast) and PATH writing is unaffected.

### 16.9 Refreshing the File Explorer Cache

After changing the registry, File Explorer may still be using a **cached** right-click menu.
`install.ps1` / `uninstall.ps1` call the following after writing the registry:

```csharp
SHChangeNotify(SHCNE_ASSOCCHANGED, SHCNF_IDLIST, NULL, NULL);   // primary: associations changed
SHChangeNotify(SHCNE_UPDATEITEM,  SHCNF_PATHW,   NULL, NULL);   // secondary: nudge refresh of existing items
```

`SHCNE_ASSOCCHANGED` is the standard notification for "file type associations changed"; upon
receiving it Explorer invalidates its cached `IContextMenu` and re-reads the registry the next
time a right-click menu is shown. The two notifications cost almost nothing.

> ⚠️ **Measured: on Windows 11 this notification is unreliable.** Very often you must
> **restart the explorer process or log off and back on** before it truly takes effect. The
> overwhelming majority of "the menu still is not there" reports come from skipping this step.
> That is why this tool makes "you must restart File Explorer" the **first thing** it tells
> you after installing, and offers an opt-in automatic restart (see
> [§6.2](#62-after-installing-restart-file-explorer)).

**Degradation strategy:** if `Add-Type` compilation fails (restricted environments lack the C#
compiler) or the call throws, installation/uninstallation **does not abort with an exception**;
it instead prints manual restart instructions.

### 16.10 Verification Script (`verify-registration.ps1`)

A **standalone** diagnostic tool that answers "the registry is written, but does Explorer
actually recognize it?".

Looking at the registry **alone is not enough** to prove the menu works — the historical bug
was exactly "every key and value present, yet the menu never appears". Hence the script
verifies on several layers:

| Layer | Content | Evidence strength |
|---|---|---|
| Layer 1 | Parent item `MUIVerb`/`Icon`/`NoWorkingDirectory`, and the parent's `command` pointing at `MenuPicker.ps1` | Necessary condition |
| Layer 1 **key assertion** | The parent item **must have** a `command` subkey — the current design relies on "click to pop up a menu"; without `command`, clicking does nothing | Necessary condition |

> ⚠️ **The direction of this assertion was reversed once — read §16.2 before changing it:**
> in the `SubCommands` era the requirement was "the parent must **never** have a `command`";
> after the switch to "click to pop up", the requirement is exactly the opposite — the parent
> **must** have one. If `verify-registration.ps1` reports "the parent should not have a
> command", it is still an old version and needs updating.
| Layer 1.2 | Whether anything is left behind at historical locations (exefile / SystemFileAssociations) | Upgrade-path regression |
| Layer 1.3 | Whether `(Default)` of `*\shell` / `exefile\shell` was wrongly changed to PathAdder | **Disaster-level regression** |
| Layer 1.5 | Whether HKLM-side `open`/`runas`/`runasuser` are intact | Safety regression |
| Layer 2 | **Real COM enumeration** (one `.exe` + one `.txt`): `SHCreateItemFromParsingName` → `BindToHandler(BHID_ShellMenu)` → `QueryContextMenu` → `GetCommandString(GCS_VERBKEY)` | **Decisive** |
| Layer 2 fallback | When Shell COM is unavailable, infer from the merged view `HKCR\*\shell\PathAdder` | Strong but not decisive |
| Layer 3 | Whether third-party menus (`HKCR\*\shell`) were damaged | Safety regression |

> Layer 2 calls `GetCommandString(GCS_VERBKEY)` to get the **canonical verb name** (such as
> `PathAdder.AddUser`) instead of just comparing the display text — display text can be
> localized or rewritten, whereas the verb name is the very key Explorer uses to dispatch the
> command and cannot be faked.

**Exit codes:** `0` = everything passed; `1` = some checks failed; `2` = environment problem,
layer 2 could not be completed.
The script **never** prints "all passed" without layer 2 evidence — it would rather report `2`
than produce a false positive.

> **Implementation note:** this script does **not** use `[ComImport]` interfaces; it takes
> function pointers by vtable slot and invokes them through delegates. Two reasons: pulling a
> COM object out via `out object` and then casting it throws `InvalidCastException` under
> `Add-Type` (CodeDom compilation); and the `IContextMenu` vtable order must be exactly right
> (`GetCommandString` is the **5th** method, with `TrackPopupMenuEx`, `GetMenuStringInfo` and
> `InvokeCommand` in between) — omitting one method silently calls the wrong slot.

Usage:

```powershell
verify-registration.ps1                                  # auto-pick an .exe and create a .txt probe
verify-registration.ps1 -TargetExe "D:\Tools\ffmpeg.exe" # specify the file being right-clicked
verify-registration.ps1 -SkipContextMenu                # registry checks only, skip COM enumeration
```

The script **automatically relaunches itself with `-STA`** on a non-STA thread and forwards
the exit code, so `powershell -File verify-registration.ps1` (MTA by default) also works in
one shot.

### 16.11 Encoding

All `.ps1` files are **UTF-8 with BOM**. Windows PowerShell 5.1 parses BOM-less UTF-8 files as
ANSI/GBK, which corrupts non-ASCII characters; the BOM is mandatory.
`.bat` files stay pure ASCII (cmd.exe parses them with the local code page) and their comments
are in English.

## 17. Appendix: Observations on `HKCR\*\shell`

During the investigation, 7 third-party menu items were found under `HKCR\*\shell`:

```
meituxiuxiu | meituxiuxiupcl | pintohomefile | removeproperties
UpdateEncryptionSettingsWork | YunShellExplorerCommand
```

**Verification result: this key is normal; nothing is corrupted.**

- `HKCR\*` has only 4 subkeys (`OpenWithList` / `OpenWithProgids` / `shell` / `shellex`), and
  `shell` has 6 named subkeys, **all normal one-shot registrations** — no duplication or
  nesting anomalies.
- "Dozens of identically named `shell` subkeys" is a **display artifact of the enumeration
  method**: if you enumerate `HKCR\*` recursively (`-Recurse`) or descend level by level,
  every file type's `shell` prints `shell` again, so it looks like the same key appears dozens
  of times. The actual number of keys is 1.
- These are "all files" right-click menus registered by third-party software (Meitu family /
  encryption settings / cloud drives, etc.) and are unrelated to this tool.

**How this tool behaves here (this changed)**: the tool **itself** now registers under
`HKCR\*\shell` (parent item `PathAdder`), but with **single-point registration + precise
deletion**:

- Installation adds exactly one `PathAdder` subkey under `*\shell` and modifies no existing
  key;
- Uninstallation deletes only the `PathAdder` subtree and **never touches** any sibling key
  not named `PathAdder`;
- The `(Default)` (default verb) of `*\shell` and `exefile\shell` is **never written and never
  cleared**.

Layer 3 of the verification script explicitly lists and validates these third-party menu items
to guard against collateral damage.

## 18. Building the Shell Extension from Source

The release zip ships with a pre-compiled `com\PathAdderShellExt.dll`. From a source checkout
you can rebuild it locally:

1. **Prerequisite**: .NET Framework 4.x (any Windows 10/11 machine has it — the compiler
   `csc.exe` ships inside `%WINDIR%\Microsoft.NET\Framework64\v4.0.30319`). No Visual Studio
   or SDK download is needed.
2. **Build**:

   ```powershell
   cd com
   .\build.ps1
   ```

3. **Register** (user level, no admin): `.\register-contextmenu.ps1` — then restart File
   Explorer (see [§6.2](#62-after-installing-restart-file-explorer)).

Why the build looks the way it does:

- **Staged build**: `build.ps1` copies the `.cs` sources to `%TEMP%\PathAdderBuild` (an ASCII
  path), compiles there, and copies the DLL back. `csc.exe` from .NET Framework is known to
  choke on non-ASCII source paths (CS2001-style failures), so this staging step is what makes
  the build work from any folder — including paths containing non-ASCII characters. Do not
  "simplify" it away.
- **Rebuild when the DLL is locked**: if explorer has the DLL loaded, `build.ps1` detects the
  lock and can hand over to `release-dll.ps1`, which renames the locked file aside (`.old`)
  so the new build can be written. `release-dll.ps1` may restart explorer; pass
  `-NoRestartExplorer` to skip that.

For full details of the COM extension see [com\README-COM.md](com/README-COM.md).

## 19. Repository Layout

```
PathAdder\                    (repository root / the folder you extracted from the release zip)
├── PathAdder.ps1             # Core engine: the entry point actually invoked by the menu
│                             #   -Action Add/Remove/Restore/OpenManager
│                             #   -Scope User/System/All   -Target <file or directory>
│                             #   -BackupFile <backup file name>   -Elevated (internal elevation flag)
├── PathManager.ps1           # PATH Manager GUI (WinForms)
│                             #   - user PATH / system PATH lists (numbered)
│                             #   - backup history (preview / restore / refresh)
│                             #   - change log (latest 200 entries, newest first)
│                             #   - refresh / open backup folder / open change log / close
├── install.ps1               # Register the right-click menu (user level, idempotent)
│                             #   -RestartExplorer / -NoRestart control the Explorer restart
├── uninstall.ps1             # Remove the right-click menu (idempotent; cleans current + two
│                             #   historical locations)  -RestartExplorer / -NoRestart as in install.ps1
├── verify-registration.ps1   # [Standalone diagnostic] verify that registration really took effect
│                             #   (multi-layer checks, real IContextMenu enumeration; see §16.10)
├── install.bat               # Double-click install entry (calls install.ps1 internally)
├── uninstall.bat             # Double-click uninstall entry (calls uninstall.ps1 internally)
├── verify.bat                # Double-click verify entry (calls verify-registration.ps1 internally)
├── lib\
│   ├── Common.ps1            # Shared library: PATH read/write, normalized comparison, backup,
│   │                         #   logging, dialogs, admin detection, UAC self-elevation,
│   │                         #   environment broadcast
│   ├── ShellMenu.ps1         # Right-click menu library: single source of truth for the 4 verbs,
│   │                         #   registration/unregistration, SHChangeNotify refresh,
│   │                         #   empty-key cleanup
│   └── i18n.ps1              # i18n runtime: language resolution priority, language-pack loading,
│                             #   supported-language list, config/registry persistence,
│                             #   Set-PathAdderLanguage / Get-PathAdderLanguage
├── lang\                     # Language packs (see §12 Language)
│   ├── en-US\                # English (US) — the fallback base, must stay complete
│   └── zh-CN\                # Simplified Chinese
│                             #   each language folder holds 8 shards:
│                             #   core / shell / picker / gui / cli / setup / verify / com
├── com\                      # C# shell extension (see com\README-COM.md)
│   ├── PathAdderShellExt.cs / PathAdderContextMenu.cs   # COM shell extension sources
│   ├── build.ps1 / rebuild.ps1 / release-dll.ps1        # build tooling
│   ├── register-com.ps1 / register-contextmenu.ps1 / restore-menu.ps1   # registration tooling
│   └── README-COM.md / README-COM.zh-CN.md              # extension documentation
├── docs\                     # design documents, images (screenshots live in docs\images)
├── tools\                    # CI validation scripts (not part of the release zip)
├── .github\workflows\        # ci.yml (syntax/BOM/i18n checks), release.yml (build + publish)
├── CONTRIBUTING.md           # contribution guide (encoding rules, PR flow)
├── LICENSE                   # GPL-3.0-or-later full text
├── version.json              # version number single source of truth
├── README.md                 # This document (English)
└── README.zh-CN.md           # Simplified Chinese version of this document
```

## 20. Contributing

Contributions are welcome! Please read [CONTRIBUTING.md](CONTRIBUTING.md) first — it covers
the project's hard rules, which are unusual and easy to trip over:

1. **Encoding**: all `.ps1`/`.cs` files **must** be UTF-8 **with BOM** (PowerShell 5.1 reads
   BOM-less files as GBK and corrupts non-ASCII text); `.bat` must be **without** BOM;
   `.yml` must be **without** BOM.
2. **PowerShell 5.1 only**: no PS7 syntax (`??`, `&&`, `||`, ternary, `$PSStyle`).
3. **Bilingual UI strings**: every user-visible string change must be applied to **all**
   supported languages in the same change; English first.
4. **No binaries in git**: the DLL is a build artifact, produced by CI at release time.

Quick local checks before opening a PR:

```powershell
powershell -NoProfile -File .\tools\Test-LanguagePacks.ps1 -Strict
powershell -NoProfile -File .\tools\Test-TranslationKeys.ps1 -Strict
```

## 21. License

PathAdder is licensed under the **GNU General Public License v3.0 or later**
([GPL-3.0-or-later](https://spdx.org/licenses/GPL-3.0-or-later.html)).

Copyright (C) 2026 w0i0c0o

This program is free software: you can redistribute it and/or modify it under the terms of the
GNU General Public License as published by the Free Software Foundation, either version 3 of
the License, or (at your option) any later version.

See the full text in [LICENSE](LICENSE). In short: if you distribute modified versions of this
program, they must also be released under GPL-3.0-or-later with the source code available.

## 22. Acknowledgements

- Built entirely on components Windows already ships: Windows PowerShell 5.1, .NET Framework,
  and the classic Shell verbs registry — no third-party runtime required.
- The COM shell extension uses plain `csc.exe` from the .NET Framework, avoiding any SDK
  dependency.
- Thanks to everyone who files clear bug reports — the deep-dive chapters
  ([§16](#16-how-it-works-implementation-notes)) exist because of them.
