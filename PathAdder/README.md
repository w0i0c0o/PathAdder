[English](README.md) | [简体中文](README.zh-CN.md)

# PathAdder — Add a Program's Folder to PATH with One Right-Click

A **zero-dependency** tool (Windows PowerShell 5.1 + .NET Framework only): right-click any `.exe` file in File Explorer and add the folder it lives in to your system PATH, so you can run that program straight from the command line.

- Admin-free installation (writes only to `HKCU`, never touches system directories)
- **Automatic backup** before every PATH change — roll back at any time
- Supports user-level and system-level PATH; system-level self-elevates through UAC
- Built-in **PATH Manager** GUI: browse entries, backup history, restore, change log

---

## 1. Installation

1. Double-click **`install.bat`** (recommended), or run in PowerShell:

   ```powershell
   powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File ".\install.ps1"
   ```

2. A "Installation complete" dialog means it succeeded.

---

## ⚠️ 1.5 You Must Restart Explorer Before the Menu Appears (The Most Important Step)

**After the installer writes the registry, the right-click menu usually does NOT appear immediately — this is normal, not a failed installation.**

The reason is that File Explorer caches menus and file associations. `install.ps1` does send a
`SHChangeNotify(SHCNE_ASSOCCHANGED)` notification, but **on Windows 11 this notification does not
always take effect**; in practice you must restart the explorer process or log off and back on
before the entry really shows up in the menu.

So please complete **one of the following two** restart options:

```powershell
Stop-Process -Name explorer -Force; Start-Process explorer.exe
```

Or simply **log off the current Windows account and log back in**.

> At the end of the installation the script will **ask you with a dialog** whether to restart
> Explorer right away (the default button is "No").
> Because restarting closes every open folder window, the script **never restarts without asking**.
> Scripted invocations can control this with switches:
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

---

### 3. How to Use the Menu

Right-click **any file** (any type, including `.exe`) and a **"PATH Assistant"** entry appears in
the menu. **Clicking** it pops up this tool's action menu at the mouse position:

| Menu item | Effect | Requires admin |
|---|---|---|
| Add to PATH (current user) | Writes to `HKCU\Environment\Path` | No |
| Add to PATH (system-wide, admin) | Writes to `HKLM\...\Session Manager\Environment\Path` | Yes (UAC prompt) |
| Remove this directory from PATH | Removes it from both user and system PATH | User: no / System: yes |
| Open PATH Manager | Opens the GUI management window | No (required when touching system PATH) |

The top row of the menu is a **grey, non-clickable** directory name, so you can confirm which
directory the action applies to.

All 4 actions are grouped under **a single parent menu item**, so the top-level menu only takes one
row and does not clutter your other menu entries.

> ℹ️ **About "click" instead of "hover"**
>
> Early versions of this tool used Windows' native `SubCommands` static cascade (auto-expanding on
> mouse hover), but **that failed in real testing on Windows 11**: the parent item showed up,
> **hovering never expanded anything**, and because that mechanism requires the parent to have no
> `command`, **clicking did nothing either** — the feature was completely unusable. See §5.2.
>
> The current version therefore uses "click → pop up a menu at the cursor position". The look and
> feel are essentially the same as a native right-click submenu, and it does not depend on
> Explorer's cascade implementation, so reliability is 100%. The price is one extra click.

> ⚠️ **Windows 11 must-read: the menu lives under "Show more options"**
>
> Windows 11 has folded the classic right-click menu (verbs) into the second layer of a layered
> menu; **the first layer only shows a few fixed items** (Copy / Paste / Delete / Rename /
> Properties, etc.), and this tool's 4 menu items are not in that first layer. Pick any of these
> ways to reach it:
>
> - **Right-click** the `.exe` → click **"Show more options"**;
> - **Select** the file, then press **`Shift` + `F10`**;
> - Select the file, then press **`Shift` + arrow keys** to expand the classic menu;
> - Trackpad/keyboard also works: once the menu pops up, press **`Shift` + `F10`** or just the left
>   arrow key.
>
> This is Windows 11 system behavior, not a limitation of this tool. On Windows 10 and earlier,
> a plain right-click shows it.

> If the menu still does not appear: the installer already calls
> `SHChangeNotify(SHCNE_ASSOCCHANGED)` to tell File Explorer to drop its menu cache, which usually
> takes effect immediately. If it still does not show up, restart File Explorer manually or log off
> and back on:
>
> ```powershell
> Stop-Process -Name explorer -Force; Start-Process explorer.exe
> ```

> ⚠️ **Windows 11 must-read: the menu lives under "Show more options"**
>
> Windows 11 has folded the classic right-click menu into the second layer of a layered menu;
> **the first layer only shows a few fixed items** (Copy / Paste / Delete / Rename / Properties,
> etc.), and "PATH Assistant" is not in that first layer. Pick any of these:
>
> - Right-click → click **"Show more options"**;
> - **Select** the file, then press **`Shift` + `F10`**;
> - Select the file, then press **`Shift` + arrow keys** to expand the classic menu.
>
> This is Windows 11 system behavior, not a limitation of this tool. On Windows 10 and earlier,
> a plain right-click shows it.

### Verifying the Installation

Double-click **`verify.bat`**, or run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File ".\verify-registration.ps1"
```

It checks on several layers: the parent menu structure and its `command` subkey, whether the HKLM
side system menu is intact, whether anything is left behind at historical locations, whether the
default verb was modified by mistake, whether third-party menus were damaged — and it tries Shell
COM to **really enumerate** the right-click menu once (one `.exe` and one `.txt`). See
[§5.9](#510-verification-script-verify-registrationps1).

> Note: the verification script can only validate "the registry and Shell side of things". If you
> **have not restarted File Explorer yet**, the script may report a complete structure while the
> menu has not been built — finish the restart step above before looking at the menu.

### Uninstalling

Double-click **`uninstall.bat`**, or:

```powershell
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File ".\uninstall.ps1"
```

Uninstalling cleans **every location** (current location + two historical locations), see the table
below:

| # | Location | What is removed |
|---|---|---|
| 1 | `HKCU\Software\Classes\*\shell\PathAdder` | Current version's cascade menu (the whole subtree) |
| 2 | `HKCU\Software\Classes\exefile\shell\PathAdder*` | 4 items registered flat by early versions |
| 3 | `HKCU\Software\Classes\SystemFileAssociations\.exe\shell\PathAdder*` | 4 fallback items registered by early versions |

This way, even if you installed an old version, upgrading will not leave orphan menu items behind.
After uninstalling you **also need to restart File Explorer** before the entry disappears from the
menu (the script will ask whether it should restart for you).

Uninstalling only removes the right-click menu; **backups and logs are kept** in
`%LOCALAPPDATA%\PathAdder\` so you can roll back at any time. Delete that directory manually if you
want a complete cleanup.

---

## 2. Usage Example

Suppose: `D:\Tools\ffmpeg-6.0\bin\ffmpeg.exe`

1. Right-click `ffmpeg.exe` → **"Add to PATH (current user)"**
2. A dialog says `Successfully added to [User PATH (current user)]`, and shows the directory
   `D:\Tools\ffmpeg-6.0\bin` plus the backup file name
3. **Open a new** cmd / PowerShell window and type `ffmpeg -version` — it just runs

> Command-line windows that are already open do not pick up the change automatically; you need to
> reopen them (the tool broadcasts `WM_SETTINGCHANGE`, so File Explorer and most programs refresh
> on their own).

To undo: right-click the same `.exe` → **"Remove this directory from PATH"**; user-level and
system-level are both handled. If elevation fails for the system level, only the user level is
processed and you get an explicit message.

---

## 3. Files

```
PathAdder\
├── PathAdder.ps1      # Core engine: the entry point actually invoked by the menu
│                      #   -Action Add/Remove/Restore/OpenManager
│                      #   -Scope User/System/All   -Target <file or directory>
│                      #   -BackupFile <backup file name>   -Elevated (internal elevation flag)
├── PathManager.ps1    # PATH Manager GUI (WinForms)
│                      #   - user PATH / system PATH lists (numbered)
│                      #   - backup history (preview / restore / refresh)
│                      #   - change log (latest 200 entries, newest first)
│                      #   - refresh / open backup folder / open change log / close
├── install.ps1        # Register the right-click menu (user level, idempotent)
│                      #   -RestartExplorer / -NoRestart control the Explorer restart
├── uninstall.ps1      # Remove the right-click menu (idempotent; cleans current + two
│                      #   historical locations)  -RestartExplorer / -NoRestart as in install.ps1
├── verify-registration.ps1  # [Standalone diagnostic] verify that registration really took effect
│                      #   - Layer 1: cascade menu structural integrity (incl. "parent has no
│                      #     command" assertion)
│                      #   - Layer 1.2: leftovers at historical locations
│                      #   - Layer 1.3: default verb safety
│                      #   - Layer 1.5: HKLM system menu integrity
│                      #   - Layer 2: real IContextMenu enumeration (.exe + .txt)
│                      #   - Layer 2 fallback: merged-view association resolution inference
│                      #   - Layer 3: third-party menu survival check
│                      #   Exit code 0 = pass, 1 = failures present, 2 = environment insufficient
├── install.bat        # Double-click install entry (calls install.ps1 internally)
├── uninstall.bat      # Double-click uninstall entry (calls uninstall.ps1 internally)
├── verify.bat         # Double-click verify entry (calls verify-registration.ps1 internally)
├── lib\Common.ps1     # Shared library: PATH read/write, normalized comparison, backup, logging,
│                      # dialogs, admin detection, UAC self-elevation, environment broadcast
├── lib\ShellMenu.ps1  # Right-click menu library: single source of truth for the 4 verbs,
│                      # registration/unregistration, SHChangeNotify refresh, empty-key cleanup
│                      #   (install and uninstall share the same verb definitions, so the two
│                      #   never drift apart)
├── lib\i18n.ps1       # i18n runtime: language resolution priority, language-pack loading,
│                      # supported-language list, config file / registry persistence,
│                      # Set-PathAdderLanguage / Get-PathAdderLanguage
├── lang\              # Language packs (see §9 Language)
│   ├── en-US\         # English (US) — the fallback base, must stay complete
│   └── zh-CN\         # Simplified Chinese
│                      #   each language folder holds 8 shards:
│                      #   core / shell / picker / gui / cli / setup / verify / com
├── com\               # C# shell extension (see com\README-COM.md)
├── README.md          # This document (English)
└── README.zh-CN.md    # Simplified Chinese version of this document
```

---

## 4. Backups and Logs

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

---

## 5. Key Implementation Decisions

### 5.1 Registration Location: `HKCU\Software\Classes\*\shell\PathAdder`

> **This section documents two rounds of real bugs and their fixes.** If you hit "installation
> succeeds, the keys and values in the registry are all present, but the right-click menu never
> appears", the cause is almost always here.

#### Current location: `*` = all file objects

```
HKCU\Software\Classes\*\shell\PathAdder
```

`HKCR\*` is the officially supported Windows association key for "**all file objects**"; it covers
any extension unconditionally (including `.exe`). That way right-clicking any file works, with no
need to register once per extension.

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

Per Windows' file-type menu composition rules, `SystemFileAssociations\.xxx` is the **fallback**
path that is only used **when the extension has no associated ProgID**. Once an extension does have
an associated ProgID, File Explorer uses that ProgID's `shell` as the trunk and skips the fallback
path entirely. `.exe` is associated with `exefile`, so Explorer reads only `exefile\shell` and
never reads `SystemFileAssociations\.exe\shell`.

**This is not a caching / permission / 32-64 redirection / group policy problem — the registration
location was simply wrong.**

#### Bug two (mid versions): registered under `exefile\shell`, working only for `.exe`

Bug one was fixed, but the menu disappeared whenever the user right-clicked something that was not
an `.exe`.

#### Final solution and how the two historical locations are handled

| Location | Disposition | Reason |
|---|---|---|
| `*\shell\PathAdder` | **In use now** | `*` covers all files (incl. .exe); a single registration point is cleanest |
| `exefile\shell\PathAdder*` | **Removed** | `*` already covers .exe; registering both would show two copies of the same action |
| `SystemFileAssociations\.exe\shell\PathAdder*` | **Removed** | It was only a fallback for "when .exe has no associated ProgID"; once `*` covers all files unconditionally, that fallback is meaningless |

> **On whether to keep the SystemFileAssociations fallback: remove it entirely.**
> Its only reason to exist was "in case .exe has no associated ProgID". But `*` takes effect
> **unconditionally** — it holds for any file object and never goes through ProgID association
> resolution, so there is no risk of "the menu disappearing because .exe has no ProgID". Since `*`
> already covers every case unconditionally, this SystemFileAssociations entry is pure redundancy;
> removing it drops the number of registration points from 2 to 1 and makes duplicate menus or
> missed cleanups far less likely.

**⚠ Uninstalling must clean all three locations** (current + two historical), otherwise users
upgrading from an old version will keep orphan menu items. `uninstall.ps1` iterates through
`Get-PathAdderShellCleanupLocations` and this has been verified in practice.

#### Why user-level registration is safe

`HKCR` is a **merged view** of `HKCU\Software\Classes` and `HKLM\Software\Classes`, merged item by
item for both "values" and "subkeys": for identical value names HKCU wins, and subkeys with the
same name coexist on both sides.

This tool **never writes to HKLM** and **never modifies** any system value under `*\shell` /
`exefile\shell` — **in particular it never writes a default verb** (see §5.3).


### 5.2 Submenu Implementation: Why `SubCommands` Was Dropped for "Click to Pop Up" (changed 2026-10-04)

#### The trap: `SubCommands` does not expand on hover under Windows 11

The first version used Windows' native **static cascade (`SubCommands`)** to pack the 4 actions
under a parent menu:

```
HKCU\Software\Classes\*\shell\PathAdder
    SubCommands = "PathAdder.AddUser;PathAdder.AddSystem;PathAdder.Remove;PathAdder.Manager"
    └─ shell\PathAdder.AddUser\command = …
```

**Measured result: it fails on Windows 11.** Symptoms:

- The parent item "PATH Assistant" **displays normally**;
- **Hovering never expands** the submenu;
- Because that mechanism requires the parent to have no `command` subkey, **clicking does nothing
  either**;
- Net result: **not one of the 4 functions can be clicked**.

**Root cause:** Windows 11 introduced a new context-menu pipeline in which classic registry verbs
are wrapped into `ExplorerCommand verb` before being rendered. That wrapper's support for the
`SubCommands` static cascade is incomplete, so cascade expansion is never triggered. The more
third-party `IExplorerCommand` extensions are installed, the more visible the failure becomes (this
machine has several COM-based extensions: VLC, Git, Meitu, a cloud drive client, and so on).

> One counter-intuitive detail: `SubCommands` and "the parent has a `command`" are **mutually
> exclusive** — as soon as the parent has a `command`, Windows treats it as an ordinary item and
> `SubCommands` is ignored completely. So "add a fallback `command` to the parent" cannot work;
> you must pick one or the other.

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

1. It takes the directory containing the target file and shows it as the **grey, non-clickable**
   description row at the top of the menu (so the user can confirm the object);
2. It pops up a WinForms `ContextMenuStrip` at `[Cursor]::Position`;
3. Once the user picks an item, it hands over to `PathAdder.ps1` to perform the real action
   (`Add` / `Remove` / `OpenManager`).

**Trade-off:** one extra mouse click buys **independence from Explorer's cascade implementation and
100% reliability**. On Windows 11 this is the only design that works consistently.

If you ever want real "hover to expand" back, the only way out is implementing an
`IExplorerCommand` COM shell extension (registering `ExplorerCommandHandler`), which means writing
and registering a COM DLL — far more work and maintenance cost.

**Upgrade compatibility:** installation automatically clears the `SubCommands` value and the
`…\shell\` subcommand tree left behind by the previous version, so upgrading from an old version
does not require uninstalling first.

#### About `Position = "Bottom"`: not adopted

MSDN samples occasionally show `Position = "Bottom"`, and it may feel natural to sink the entry to
the bottom of the menu. This project **does not** add it, because **discoverability beats menu
tidiness**:

1. Grouping into a parent menu already cut the top-level footprint from 4 rows to 1, so the tidiness
   goal is met;
2. `Bottom` pushes the item next to the "Properties" group, and users of this tool have already
   suffered from "I cannot find the menu" — **reducing visibility here is the wrong direction**;
3. The default position, in the middle of the menu, is easier to spot.

If you do need it, just add a `Position` value on the parent item; no code restructuring required.

### 5.3 Never Writing a Default Verb (`-MakeDefault` Is Deprecated)

> ⚠️ **This tool never writes a default verb, at any location.**

The default verb (the parent key's `(Default)`) determines a file's **double-click behavior**.
Changing it to our menu item means **double-clicking any file no longer opens it but pops up a PATH
dialog** — extremely destructive, and almost certainly not what the user wanted.

- The `-MakeDefault` switch is **retained** (backward compatibility) but is now **completely
  inert**; it only prints an explanatory note;
- The `(Default)` of `*\shell` and `exefile\shell` is **never written or cleared** by this tool;
- `verify-registration.ps1` has a dedicated **default verb safety check**: if the default value ever
  becomes `PathAdder*`, it fails immediately and demands a fix.

### 5.4 Passing `%V` to the Menu Instead of `%1`

```text
powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "...\PathAdder.ps1" -Action Add -Scope User -Target "%V"
```

Reasons:

- `%V` (the verb parameter) **always passes a long file name** on Windows Vista and above, which is
  the most robust choice for paths containing non-ASCII characters or spaces;
- `%1` is converted to an 8.3 short name (e.g. `D:\TOOLS~1\BIN`) in some legacy scenarios, which can
  lose non-ASCII directory names;
- Belt and braces: the script additionally uses `GetLongPathName` (P/Invoke) to restore short names
  and then normalizes with `GetFullPath`.
- The script receives a **file path** and converts it to the containing directory internally with
  `[System.IO.Path]::GetDirectoryName()`.

#### Validating the `-Target` argument (preventing the current working directory from being added by mistake)

In **Add** scenarios `-Target` must pass three checks, otherwise the script errors out and PATH is
not touched at all:

1. **It must be a true absolute path** (`-RequireAbsolute`): relative paths and drive-relative forms
   (such as `C:`) are rejected, so the result never depends on the script's CWD;
2. In Add scenarios: **it must really exist** (file or directory), preventing bogus arguments from
   adding something wrong;
3. **Garbage input is intercepted**: strings made only of whitespace, dots or slashes, such as
   `'...'`, `'.'`, `'   '`, are explicitly rejected.

> This step is required: `[System.IO.Path]::GetFullPath('...')` silently returns the **current
> working directory**. Without the check, `...` would be treated as a legitimate directory and the
> PowerShell process's CWD would be written into PATH.

> Likewise, the drive-relative form `C:` is expanded by `GetFullPath` as "the current directory on
> drive C", which also depends on the process CWD. That is why `Path.IsPathRooted()` is **not**
> used here (it counts `C:` as absolute); only two CWD-independent forms are accepted: drive +
> separator (`C:\`, `C:/`) and UNC (`\\server\share`).

> **Note:** the three rules above mainly constrain **Add**. **Remove deliberately relaxes the
> existence check** (internal `-AllowMissing`) so you can clean up stale PATH entries whose
> directories were deleted long ago but are still listed in PATH; Remove still requires a true
> absolute path, and garbage input is rejected there too.
>
> The library function `Remove-DirectoryFromPath` also takes `-RequireAbsolute` (defense in depth):
> otherwise, in a right-click "Remove", `C:` would be expanded against the CWD and then **silently
> delete** the legitimate PATH entry that happens to equal that CWD — unacceptable destruction that
> must be blocked at the lowest level.

### 5.5 UAC Self-Elevation

- Detection: `WindowsPrincipal.IsInRole(WindowsBuiltInRole.Administrator)`;
- Elevation: build a `ProcessStartInfo` with **`Verb = 'runas'`** + `UseShellExecute = $true`, relaunch
  itself via `powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File`, and append
  an `-Elevated` flag to prevent infinite elevation loops;
- **All three conditions are mandatory**: without `Verb = 'runas'` you merely "open another
  PowerShell with the current user's rights" (no UAC prompt, the child's `ISADMIN` is still False,
  and writing system PATH is guaranteed to fail); without `UseShellExecute = $true` the `Verb` is
  silently ignored;
- **Failure handling:** wrap in `try/catch` (clicking "No" in UAC throws a `Win32Exception`) and show
  a friendly "System PATH was not modified" message — no crash, no half-finished state.

### 5.6 Preserving the PATH Value Type (`REG_EXPAND_SZ` / `REG_SZ`)

The `Path` value can be either `REG_EXPAND_SZ` or `REG_SZ`. The read/write flow:

1. `GetValue('Path')` reads the value;
2. `GetValueKind('Path')` reads the type;
3. `SetValue('Path', newValue, originalType)` writes it back.

The type is recorded in the log as well, and restoring a backup prefers the original type from the
log.

> Implementation note: the `Microsoft.Win32.RegistryValueKind` member is named **`ExpandString`**,
> not `ExpandSz`. In PowerShell 5.1 writing `[RegistryValueKind]::ExpandSz` does not raise an error —
> it silently returns `$null`, which then makes overload resolution fail for
> `SetValue(name, value, kind)`. This tool therefore always maps safely through
> `ConvertTo-RegistryValueKind` / `ConvertTo-RegistryValueKindName`.

### 5.7 Duplicate Comparison (Avoiding Re-Adding)

Normalize first, then compare:

1. Trim leading/trailing whitespace and quotes;
2. `ExpandEnvironmentVariables()` expands any `%XXX%` inside;
3. Normalize `/` to `\`;
4. Strip the trailing backslash (except for a drive root such as `C:\`);
5. Case-insensitive (`ToLowerInvariant()`).

On a hit it **returns immediately** with `AlreadyExists` — nothing is written to the registry and no
backup is created.

### 5.8 Broadcasting the Environment Change

After writing the registry:

- `SetEnvironmentVariable('Path', $combined)` — **Process target only (the default overload); it just
  updates the current process's memory and never writes back to the registry**;
- Rebuild the current process's `$env:Path` (reassembled from Machine + User in the registry);
- P/Invoke `SendMessageTimeout(HWND_BROADCAST, WM_SETTINGCHANGE, 0, "Environment", SMTO_ABORTIFHUNG, 5000, ...)`
  so File Explorer and already-open programs pick up the change.

> ⚠️ Implementation trap: **do not** switch to the overload that takes
> `EnvironmentVariableTarget.User` / `.Machine`.
> That overload **writes back to the registry** and silently downgrades `REG_EXPAND_SZ` to `REG_SZ`,
> directly breaking §5.6's "preserve the original value type" requirement. This tool therefore uses
> the Process target only.

P/Invoke goes through `Add-Type` compilation; if compilation fails it degrades gracefully (just
skips the broadcast) and PATH writing is unaffected.

### 5.9 Refreshing the File Explorer Cache

After changing the registry, File Explorer may still be using a **cached** right-click menu.
`install.ps1` / `uninstall.ps1` call the following after writing the registry:

```csharp
SHChangeNotify(SHCNE_ASSOCCHANGED, SHCNF_IDLIST, NULL, NULL);   // primary: associations changed
SHChangeNotify(SHCNE_UPDATEITEM,  SHCNF_PATHW,   NULL, NULL);   // secondary: nudge refresh of existing items
```

`SHCNE_ASSOCCHANGED` is the standard notification for "file type associations changed"; upon
receiving it Explorer invalidates its cached `IContextMenu` and re-reads the registry the next time a
right-click menu is shown. The two notifications cost almost nothing.

> ⚠️ **Measured: on Windows 11 this notification is unreliable.** Very often you must **restart the
> explorer process or log off and back on** before it truly takes effect. The overwhelming majority
> of "the menu still is not there" reports come from skipping this step.
> That is why this tool makes "you must restart File Explorer" the **first thing** it tells you after
> installing, and offers an opt-in automatic restart (see
> [§1.5](#15-you-must-restart-explorer-before-the-menu-appears-the-most-important-step)).

**Degradation strategy:** if `Add-Type` compilation fails (restricted environments lack the C#
compiler) or the call throws, installation/uninstallation **does not abort with an exception**; it
instead prints manual restart instructions.

### 5.10 Verification Script (`verify-registration.ps1`)

A **standalone** diagnostic tool that answers "the registry is written, but does Explorer actually
recognize it?".

Looking at the registry **alone is not enough** to prove the menu works — the historical bug was
exactly "every key and value present, yet the menu never appears". Hence the script verifies on
several layers:

| Layer | Content | Evidence strength |
|---|---|---|
| Layer 1 | Parent item `MUIVerb`/`Icon`/`NoWorkingDirectory`, and the parent's `command` pointing at `MenuPicker.ps1` | Necessary condition |
| Layer 1 **key assertion** | The parent item **must have** a `command` subkey — the current design relies on "click to pop up a menu"; without `command`, clicking does nothing | Necessary condition |

> ⚠️ **The direction of this assertion was reversed once — read §5.2 before changing it:**
> in the `SubCommands` era the requirement was "the parent must **never** have a `command`"; after
> the switch to "click to pop up", the requirement is exactly the opposite — the parent **must**
> have one. If `verify-registration.ps1` reports "the parent should not have a command", it is still
> an old version and needs updating.
| Layer 1.2 | Whether anything is left behind at historical locations (exefile / SystemFileAssociations) | Upgrade-path regression |
| Layer 1.3 | Whether `(Default)` of `*\shell` / `exefile\shell` was wrongly changed to PathAdder | **Disaster-level regression** |
| Layer 1.5 | Whether HKLM-side `open`/`runas`/`runasuser` are intact | Safety regression |
| Layer 2 | **Real COM enumeration** (one `.exe` + one `.txt`): `SHCreateItemFromParsingName` → `BindToHandler(BHID_ShellMenu)` → `QueryContextMenu` → `GetCommandString(GCS_VERBKEY)` | **Decisive** |
| Layer 2 fallback | When Shell COM is unavailable, infer from the merged view `HKCR\*\shell\PathAdder` | Strong but not decisive |
| Layer 3 | Whether third-party menus (`HKCR\*\shell`) were damaged | Safety regression |

> Layer 2 calls `GetCommandString(GCS_VERBKEY)` to get the **canonical verb name** (such as
> `PathAdder.AddUser`) instead of just comparing the display text — display text can be localized or
> rewritten, whereas the verb name is the very key Explorer uses to dispatch the command and cannot
> be faked.

**Exit codes:** `0` = everything passed; `1` = some checks failed; `2` = environment problem, layer 2
could not be completed.
The script **never** prints "all passed" without layer 2 evidence — it would rather report `2` than
produce a false positive.

> **Implementation note:** this script does **not** use `[ComImport]` interfaces; it takes function
> pointers by vtable slot and invokes them through delegates. Two reasons: pulling a COM object out
> via `out object` and then casting it throws `InvalidCastException` under `Add-Type` (CodeDom
> compilation); and the `IContextMenu` vtable order must be exactly right (`GetCommandString` is the
> **5th** method, with `TrackPopupMenuEx`, `GetMenuStringInfo` and `InvokeCommand` in between) —
> omitting one method silently calls the wrong slot.

Usage:

```powershell
verify-registration.ps1                                  # auto-pick an .exe and create a .txt probe
verify-registration.ps1 -TargetExe "D:\Tools\ffmpeg.exe" # specify the file being right-clicked
verify-registration.ps1 -SkipContextMenu                # registry checks only, skip COM enumeration
```

The script **automatically relaunches itself with `-STA`** on a non-STA thread and forwards the exit
code, so `powershell -File verify-registration.ps1` (MTA by default) also works in one shot.

### 5.11 Encoding

All `.ps1` files are **UTF-8 with BOM**. Windows PowerShell 5.1 parses BOM-less UTF-8 files as
ANSI/GBK, which corrupts non-ASCII characters; the BOM is mandatory.
`.bat` files stay pure ASCII (cmd.exe parses them with the local code page) and their comments are in
English.

## 6. FAQ

**Q1: I installed it but cannot see the menu on right-click?**

Troubleshoot in **this order** (the first two cover 95% of cases):

1. **Restart File Explorer first** — this is the most common cause, by far.
   On Windows 11 the `SHChangeNotify` notification often fails to take effect, and you must restart
   explorer before the entry appears:

   ```powershell
   Stop-Process -Name explorer -Force; Start-Process explorer.exe
   ```

   Or **log off the current Windows account and log back in**.

2. **On Windows 11 you need to click "Show more options"** (or press `Shift+F10` after selecting the
   file).
   "PATH Assistant" lives in the classic menu, not in the first layer.
   **Open "Show more options" before drawing conclusions** — do not call it missing after only
   glancing at the first layer.

3. **Make sure you right-clicked a file** (not empty space in a folder, not the desktop background).
   This tool registers on `*`, which applies only to **file objects**.

4. **Run the verification script** to confirm registration really took effect, and read the specific
   failures it reports:

   ```powershell
   powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File ".\verify-registration.ps1"
   ```

5. If the verification script reports "the parent item has a command subkey", the cascade will be
   broken (clicking does nothing) — re-running `install.ps1` fixes it automatically.

6. If it reports a complete structure but cannot enumerate the menu, that is most likely an
   environment limitation (container / remote session); confirm in a normal desktop session.


**Q2: It says "administrator privileges required"?**
A: Choose "Add to PATH (current user)" — that needs no admin. System-level PATH requires admin; if
you cancel UAC, the tool tells you explicitly and **changes nothing**.

**Q3: The program is still not found on the command line?**
A: PATH only takes effect in **newly opened** windows. Close and reopen cmd / PowerShell / Windows
Terminal.

**Q4: I added the wrong directory, what now?**
A: Right-click that `.exe` → "Remove this directory from PATH"; or open "PATH Manager → Backup
history", pick the backup taken before the change, and click "Restore to this backup".

**Q5: Will it break my existing PATH?**
A: No. The tool only "appends one entry" or "removes matching entries"; everything else is kept as
is; it backs up before every change; and if writing fails it keeps the backup and reports, leaving
no half-finished state.

**Q6: Will backup files pile up?**
A: Every operation writes one plain-text backup (usually a few KB); you can clean them up yourself
via "PATH Manager → Open backup folder". Keeping the most recent few is enough.

**Q7: My antivirus blocks the scripts?**
A: This tool does not access the network, does not inject anything, and does not write to system
directories; it only edits the PATH environment variable and the right-click menu under `HKCU`. Add
it to the whitelist if it gets blocked.

---

## 7. Known Limitations

1. **PATH length**: Windows imposes a length limit on the registry `Path` value (classically about
   2047 characters, relaxed to 32K on some systems). If you are already near the limit, writing may
   fail — the tool catches this and reports it rather than silently truncating.
2. **You must restart File Explorer**: this is the **number one** reason for "the menu does not
   appear" (more common than item 3 below). On Windows 11 the `SHChangeNotify` notification is often
   not enough; you must restart explorer or log off and back on. See
   [§1.5](#15-you-must-restart-explorer-before-the-menu-appears-the-most-important-step).
3. **Windows 11 layered menu**: the entries live in the classic menu ("Show more options" /
   `Shift+F10`); this is system behavior, not a tool limitation. Open "Show more options" before
   drawing conclusions.
4. **Default verb**: for safety the tool **never writes a default verb at any location** (it would
   make double-clicking a file stop opening it). `-MakeDefault` is deprecated to a no-op. See §5.3.
5. **The submenu is "click to expand", not "hover to expand"**: this is a deliberate trade-off, not a
   defect.
   Windows' native `SubCommands` hover cascade was **measured to not expand on Windows 11** (the
   parent is visible, hovering does nothing, and because that mechanism requires the parent to have
   no `command`, clicking is ineffective too), leaving all four functions unreachable. The current
   design pops up a menu at the cursor after a click: 100% reliable, at the cost of one extra click.
   See §5.2. To get a real hover cascade back, the only way out is implementing an
   `IExplorerCommand` COM shell extension (requires writing and registering a COM DLL), which is far
   more work.
6. **Backup granularity**: a backup records only the value of the single `Path` entry, not other
   environment variables.
7. **P/Invoke broadcast depends on `Add-Type`**: in minimal/restricted environments without the C#
   compiler, both the `WM_SETTINGCHANGE` broadcast and the `SHChangeNotify` refresh are skipped (PATH
   writing and menu registration still complete correctly; you just have to restart File Explorer
   manually).
8. **System PATH removal**: if you are not an admin and decline UAC, only the user-level removal is
   performed and reported — it is never skipped silently.
9. **`Start-Process` throws on machines with duplicate environment-variable keys differing only in
   case**: if your environment contains `Path`/`PATH`, `http_proxy`/`HTTP_PROXY` or similar keys that
   differ only in case, launching this tool with `Start-Process` (whose default is
   `UseShellExecute = $false`) fails because .NET cannot build the environment block. This is not a
   problem with this tool. Workarounds: use `Start-Process -UseShellExecute`, or use the tool's own
   `Start-PathAdderScript` (which explicitly sets `UseShellExecute = $true`), or clean up the
   duplicate environment-variable keys first.
10. **The verification script cannot complete layer 2 in restricted environments**: in some
    containers / trimmed-down systems / remote sessions, Shell COM's `SHCreateItemFromParsingName`
    returns `E_NOINTERFACE (0x80004002)` for every interface ID, making real menu enumeration
    impossible. The script automatically degrades to merged-view inference and **honestly flags the
    evidence as insufficient** (exit code 2); it never gives a false-positive conclusion.

---

## 8. Appendix: Observations on `HKCR\*\shell`

During the investigation, 7 third-party menu items were found under `HKCR\*\shell`:

```
meituxiuxiu | meituxiuxiupcl | pintohomefile | removeproperties
UpdateEncryptionSettingsWork | YunShellExplorerCommand
```

**Verification result: this key is normal; nothing is corrupted.**

- `HKCR\*` has only 4 subkeys (`OpenWithList` / `OpenWithProgids` / `shell` / `shellex`), and `shell`
  has 6 named subkeys, **all normal one-shot registrations** — no duplication or nesting anomalies.
- "Dozens of identically named `shell` subkeys" is a **display artifact of the enumeration method**:
  if you enumerate `HKCR\*` recursively (`-Recurse`) or descend level by level, every file type's
  `shell` prints `shell` again, so it looks like the same key appears dozens of times. The actual
  number of keys is 1.
- These are "all files" right-click menus registered by third-party software (Meitu family /
  encryption settings / cloud drives, etc.) and are unrelated to this tool.

**How this tool behaves here (this changed)**: the tool **itself** now registers under
`HKCR\*\shell` (parent item `PathAdder`), but with **single-point registration + precise deletion**:

- Installation adds exactly one `PathAdder` subkey under `*\shell` and modifies no existing key;
- Uninstallation deletes only the `PathAdder` subtree and **never touches** any sibling key not named
  `PathAdder`;
- The `(Default)` (default verb) of `*\shell` and `exefile\shell` is **never written and never
  cleared**.

Layer 3 of the verification script explicitly lists and validates these third-party menu items to
guard against collateral damage.

---

## 9. Language

PathAdder ships a PowerShell-side i18n layer plus a C#-side string table. This section is the
outside-facing description of that mechanism.

### 9.1 Default and Supported Languages

- **Default language: English (`en-US`).**
- Currently supported: **English (`en-US`)** and **Simplified Chinese (`zh-CN`)**.
- `en-US` is also the **fallback base**: any key missing from another language automatically falls
  back to English (see §9.4).

### 9.2 Three Ways to Switch Language

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

### 9.3 Language Resolution Priority

Resolved strictly in this order; the first hit wins:

1. Environment variable **`PATHADDER_LANG`**
2. The **`language`** field of **`%LOCALAPPDATA%\PathAdder\config.json`**
3. Registry **`HKCU\Software\PathAdder\Language`**
4. The **system UI language** (`CultureInfo.CurrentUICulture`)
5. **`en-US`** (final fallback)

> The registry value exists so that the COM shell extension running inside `explorer.exe` — which
> does not inherit your shell's environment variables or your script scope — can still read the
> active language.

### 9.4 Language Pack Layout

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

- Shards are split by module: **`core` / `shell` / `picker` / `gui` / `cli` / `setup` / `verify` /
  `com`**.
- Loading merges `en-US` first and then overlays the selected language on top, so **any key missing
  from the selected language falls back to English** automatically. A partially translated language
  never produces empty UI text.

### 9.5 Adding a New Language

Follow these steps in order:

1. **Register the language code** in `lib\i18n.ps1`: add it to `$script:PathAdderSupportedLanguages`
   and make sure `Get-PathAdderSupportedLanguages()` returns it.
2. **Add a normalization rule** in `ConvertTo-PathAdderLanguage()` (in `lib\i18n.ps1`) that maps the
   loose forms `xx` and `xx-YY` onto your canonical code (same pattern as `en`/`en-*` → `en-US`,
   `zh`/`zh-*`/`chinese`/`cn` → `zh-CN`).
3. **Copy `lang\en-US\` to `lang\<code>\`** and translate all **8** shard files
   (`core`, `shell`, `picker`, `gui`, `cli`, `setup`, `verify`, `com`).
4. **Add the display name** `App.Language.<code>` to the language pack (`core.ps1` of every
   supported language, `en-US` first). This is the name shown in the language dropdown.
5. **Right-click menu display names are written into the registry.** They are baked in at
   registration time, so after switching language you must **re-run the install/registration script**
   (`install.ps1`, or `com\register-contextmenu.ps1` for the COM extension) and restart File Explorer
   before the menu text refreshes.
6. **C# COM shell extension strings are embedded in the `L10n` class inside
   `com\PathAdderShellExt.cs`** — they do not come from the `.ps1` language packs. Adding a language
   means **adding a column there and recompiling the DLL** (see
   [com\README-COM.md](com/README-COM.md)).

### 9.6 Maintenance Rules

- Any user-visible text that is **added or changed must be added to every currently supported
  language in the same change** — no language may be left behind.
- **English must be completed first**, because it is the fallback base: until a key exists in
  `en-US`, other languages have nothing to fall back to and the UI can end up blank.
- Never delete or rename a key in one language only; renaming a key means renaming it in `en-US` and
  in every other pack.
