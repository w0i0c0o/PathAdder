[English](README-COM.md) | [简体中文](README-COM.zh-CN.md)

# PathAdder COM Shell Extension (Native Hover Cascade)

> ## ⚠ Important: the `IExplorerCommand` route does not work — use the classic menu extension
>
> Measured on this machine (Windows 11 25H2 / 26200) on 2026-10-04:
> the `IExplorerCommand` + `ECF_HASSUBCOMMANDS` cascade **does not take effect**. The diagnostic
> log shows Explorer walking all the way through `GetFlags` (which returned HASSUBCOMMANDS) →
> `GetTitle` → `EnumSubCommands` (the enumerator was even constructed successfully),
> **yet it never calls `IEnumExplorerCommand::Next`**; instead it creates one more object, calls
> `GetState` only, and stops there.
>
> After cleaning up the duplicated `command` / `ExplorerCommandHandler` registrations the
> **behavior was completely unchanged**, which proves this is Explorer's own policy and not a
> defect in our code.
>
> 👉 **Currently recommended approach: `PathAdderContextMenu.cs`** (`IShellExtInit` +
> `IContextMenu` + `CreatePopupMenu` to build a POPUP submenu); the installer script is
> **`register-contextmenu.ps1`**. Hover expansion of the submenu is handled by the USER32 menu
> system — standard menu behavior that does not depend on Explorer's extension policy (mature
> extensions such as TortoiseGit / TortoiseSVN all work this way).
> The `IExplorerCommand` record is kept in the second half of this file for reference only; it is
> not recommended for use.

## 1. What Problem This Solves

Windows' native `SubCommands` static cascade was measured to **not expand on hover** on Windows 11
(the parent is visible, hovering does nothing, and because that mechanism requires the parent to
have no `command`, clicking is ineffective too).

The previous version therefore switched to "click the parent → `MenuPicker.ps1` pops up a menu at
the cursor" — usable, but **it requires a click instead of a hover**.

This directory provides a truly native solution: implement `IExplorerCommand` +
`IEnumExplorerCommand`, let Explorer enumerate the subcommands itself, and thereby get a cascaded
submenu that **auto-expands on mouse hover**.

| Approach | Interaction | Reliability | Cost |
|---|---|---|---|
| `SubCommands` (deprecated) | Hover | ❌ Does not expand on Win11 | — |
| `MenuPicker.ps1` (current default) | **Click** | ✅ 100% | One extra click |
| **This COM extension** | **Hover** | Depends on registration method | Compile, register, restart required |

## 2. Key Prerequisite: Windows 11 Menu Layering

⚠️ **This is the easiest trap to fall into — read it first.**

Windows 11 has two right-click menus:

| Menu | Registration method | Is this extension visible? |
|---|---|---|
| **New compact menu** (first layer) | Requires **MSIX packaging** + a `desktop4:FileExplorerContextMenus` declaration | ❌ **Not visible** with registry registration alone |
| **Classic menu** ("Show more options" / `Shift+F10`) | Registry `ExplorerCommandHandler` | ✅ Visible |

In other words: **with registry registration only, the menu appears solely under "Show more
options"** — the same place as the current MenuPicker mode; the only improvement is "hover"
replacing "click".

If you want it in the Windows 11 first layer, you must additionally do MSIX packaging (see
section 5).

## 3. Prerequisites

- Windows 10 1809+ / Windows 11
- **.NET Framework 4.x** (ships with Windows; both `csc.exe` and `RegAsm.exe` live under its
  directory)
- **Administrator rights** (`RegAsm` must write `HKLM` to register the COM class)
- This directory must be writable (the compiled DLL is produced here)

> 64-bit note: the scripts always use the 64-bit compiler and `RegAsm` from the `Framework64`
> directory.
> On 64-bit Windows `explorer.exe` is a 64-bit process, and **a 32-bit DLL cannot be loaded by it**.

## 4. Installation Steps (Recommended: Classic Menu Extension)

Open PowerShell or a terminal **as administrator**:

```powershell
cd <extracted-folder>\com
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\register-contextmenu.ps1
```

The script does five things:

1. `build.ps1` — compiles `PathAdderShellExt.cs` (shared Helper/Native) and
   `PathAdderContextMenu.cs` (menu extension) into the same `PathAdderShellExt.dll`
2. `RegAsm.exe /codebase` registers the COM class (writes HKLM)
3. Thoroughly removes the old `*\shell\PathAdder` (the `IExplorerCommand` one), so the same
   feature does not appear twice in the menu
4. Writes `HKLM\Software\Classes\*\shellex\ContextMenuHandlers\PathAdder` =
   `{9B3E5D2A-7C41-4F8B-A1D6-2E5C8F40B7A3}` and adds it to the Shell Extensions Approved list
5. Reads back and self-checks; if the check fails it reports an error and exits

### You Must Restart File Explorer

```powershell
Stop-Process -Name explorer -Force; Start-Process explorer.exe
```

To unregister:

```powershell
.\register-contextmenu.ps1 -Unregister
```

### Two Project-Specific Build Pitfalls (settled by measurement on 2026-10-04)

#### Pitfall 1: a non-ASCII path → the compiler reports CS2001 "Source file could not be found"

Measured symptom: `error CS2001: Source file "<non-ASCII-path>\...\PathAdderShellExt.cs" could not be
found`, while the file **really exists** and the path in the arguments is **completely correct**
(the argv was verified byte by byte with a native process). This is a parsing problem that occurs
when a non-ASCII path is passed to the compiler from an elevated session.

**Fix: move the build into a pure-English temporary directory.** `build.ps1` now:

1. Copies both `.cs` files to `%TEMP%\PathAdderBuild\` (a pure ASCII path)
2. Compiles there
3. Copies the produced DLL back to `PathAdder\com\` (the path the registry `CodeBase` points at is
   unchanged)

As a bonus, compiler arguments now go through a **response file** (`@xxx.rsp`, with a UTF-8 BOM),
completely sidestepping quoting / encoding problems in command-line argument passing; if the
response file fails, it automatically retries with direct arguments.

> ⚠ Because the "rename to work around" step moves the old DLL away before compiling, a failed
> build leaves **no DLL in the project at all**.
> The registry still points at that path → the menu extension cannot load at all. After a failed
> build you must fix the problem and rebuild.

#### Pitfall 2: `.ps1` / `.cs` files must be **UTF-8 with BOM**

When PowerShell 5.1 reads a `.ps1`, **a file without a BOM is parsed using the local ANSI code page
(GBK on Chinese systems)**. This project's source contains a lot of non-ASCII text; once it is
misread as GBK, `幸玮代码` turns into `骞哥幃浠ｇ爜` — at best the text is garbled, at worst strings
and comments get truncated and produce inexplicable syntax or compile errors.

```powershell
# Self-check: the first 3 bytes of the file should be EF BB BF
Format-Hex -Path .\build.ps1 -Count 3
```

`PathAdderContextMenu.cs` once missed its BOM; this has been fixed. **Any new script or source file
must carry a BOM.**

### What To Do When the DLL Is Locked (read before rebuilding/re-registering)

Once `explorer.exe` has loaded this DLL it holds on to it: **renaming is allowed**, but
**writing/overwriting is not**, so a new DLL cannot be built to the original path and `build.ps1`
fails with "DLL is in use".

The script already handles this automatically, but if you want to do it manually, this is the order:

```powershell
cd <extracted-folder>\com

# (1) find out who is holding this module
tasklist /m PathAdderShellExt

# (2) kill File Explorer (and any other holder listed above)
Stop-Process -Name explorer -Force

# (3) relaunch it immediately, otherwise the desktop disappears
Start-Process explorer.exe

# (4) then build / register
.\register-contextmenu.ps1
```

`release-dll.ps1` automates (1)(2)(3) above and polls until the file is really writable (up to 12
seconds):

```powershell
.\release-dll.ps1                    # release and auto-restart File Explorer
.\release-dll.ps1 -NoRestartExplorer # release only, do not restart
```

`build.ps1` calls it first when it detects a lock, and only falls back to "rename to work around"
if that fails.
If it still reports a lock, it is usually antivirus software scanning the file — wait 10~30 seconds
and retry, or add `PathAdder\com` to the exclusion list; if that is not enough, log off and back on
(faster than rebooting).

> To repeat: **do not try to "unregister" this DLL with `regsvr32 /u`.** It is a .NET assembly with
> no `DllUnregisterServer` export, so that command is guaranteed to report "entry point not found",
> and it **does not release the file lock** either.

---

## 4b. Installation Steps (Proven Unusable: IExplorerCommand Cascade)

> Recorded for reference only. **Do not go down this road again** — see the important note at the
> top of this file.

---

Open PowerShell or a terminal **as administrator**:

```powershell
cd <extracted-folder>\com

# One-shot: compile + register + switch the menu location
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\register-com.ps1
```

The script does four things in order:

1. `build.ps1` — compiles `PathAdderShellExt.cs` → `PathAdderShellExt.dll` with `csc.exe`
2. `RegAsm.exe /codebase` registers the COM class (writes HKLM)
3. After a full cleanup of historical leftover keys, writes `ExplorerCommandHandler` = the parent
   command CLSID at a **single point** under `HKLM\Software\Classes\*\shell\PathAdder`, and makes
   sure there is no `command` subkey (the two are mutually exclusive, see the "Key finding" in
   section 8), then reads back and self-checks
4. `SHChangeNotify` notifies File Explorer

### You Must Restart File Explorer

```powershell
Stop-Process -Name explorer -Force; Start-Process explorer.exe
```

Without a restart the menu does not change (`SHChangeNotify` is often not enough on Win11).

## 5. Getting The Menu Into The Windows 11 First Layer (MSIX Packaging)

The registry route only reaches the classic menu. To reach the new menu you need:

1. Visual Studio 2022 (with the "Windows Application Packaging Project" workload)
2. Create a Windows Application Packaging Project and add `PathAdderShellExt.dll` as a resource
3. Declare the following in `Package.appxmanifest`:

```xml
<Package xmlns="http://schemas.microsoft.com/appx/manifest/foundation/windows10"
         xmlns:com="http://schemas.microsoft.com/appx/manifest/com/windows10"
         xmlns:desktop4="http://schemas.microsoft.com/appx/manifest/desktop/windows10/4"
         xmlns:desktop9="http://schemas.microsoft.com/appx/manifest/desktop/windows10/9"
         xmlns:rescap="http://schemas.microsoft.com/appx/manifest/foundation/windows10/restrictedcapabilities"
         xmlns:uap="http://schemas.microsoft.com/appx/manifest/uap/windows10"
         IgnorableNamespaces="uap rescap desktop4 desktop9 com">

  <Identity Name="PathAdder.ShellExt" Publisher="CN=YourName" Version="1.0.0.0" />
  <Properties>
    <DisplayName>PathAdder</DisplayName>
    <PublisherDisplayName>PathAdder</PublisherDisplayName>
    <Logo>Images\StoreLogo.png</Logo>
  </Properties>
  <Dependencies>
    <TargetDeviceFamily Name="Windows.Desktop" MinVersion="10.0.14393.0" MaxVersionTested="10.0.22621.0" />
  </Dependencies>
  <Resources><Resource Language="x-generate" /></Resources>

  <Applications>
    <Application Id="App" Executable="PathAdderHost.exe" EntryPoint="Windows.FullTrustApplication">
      <uap:VisualElements DisplayName="PathAdder" Description="PATH Assistant"
                          BackgroundColor="transparent" Square150x150Logo="Images\Square150x150Logo.png"
                          Square44x44Logo="Images\Square44x44Logo.png" />
      <Extensions>
        <!-- Register the COM surrogate (SurrogateServer loads the DLL in a separate process) -->
        <com:Extension Category="windows.comServer">
          <com:ComServer>
            <com:SurrogateServer DisplayName="PathAdder Shell Extension">
              <com:Class Id="1C789ABD-65D1-5FAD-8B98-52595EBB290B" Path="PathAdderShellExt.dll" ThreadingModel="STA" />
            </com:SurrogateServer>
          </com:ComServer>
        </com:Extension>

        <!-- New (Win11 first layer) right-click menu -->
        <desktop4:Extension Category="windows.fileExplorerContextMenus">
          <desktop4:FileExplorerContextMenus>
            <desktop4:ItemType Type="*">
              <desktop4:Verb Id="PathAdder" Clsid="1C789ABD-65D1-5FAD-8B98-52595EBB290B" />
            </desktop4:ItemType>
          </desktop4:FileExplorerContextMenus>
        </desktop4:Extension>

        <!-- Classic menu (Show more options) -->
        <desktop9:Extension Category="windows.fileExplorerClassicContextMenuHandler">
          <desktop9:FileExplorerClassicContextMenuHandler>
            <desktop9:ExtensionHandler Type="*" Clsid="1C789ABD-65D1-5FAD-8B98-52595EBB290B" />
          </desktop9:ExtensionHandler>
        </desktop9:Extension>
      </Extensions>
    </Application>
  </Applications>

  <Capabilities>
    <rescap:Capability Name="runFullTrust" />
  </Capabilities>
</Package>
```

4. Package it as an MSIX and install it (needs a trusted certificate, or a self-signed certificate
   that you trust)

> This step is clearly more work than the registry route above, and it requires Visual Studio.
> If all you need is "hover" and not the first layer, the registry route (section 4) is enough.

## 6. Verification

1. Restart File Explorer
2. Right-click **any file** → click "Show more options" (or press `Shift+F10` after selecting it)
3. Find "PATH Assistant"
4. **Hover the mouse** over it — it should expand automatically:
   - Add to PATH (current user)
   - Add to PATH (system-wide, admin) ← with the UAC shield icon
   - Remove this directory from PATH
   - ────────── (separator)
   - Open PATH Manager

## 7. Rollback

```powershell
# Go back to "click to pop up a menu" mode and unregister the COM class
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\restore-menu.ps1

# If unregistering fails because explorer holds the DLL
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\restore-menu.ps1 -KeepComRegistration
```

Then restart File Explorer.

> You can also roll back at the code level: the repository tag `v1.0-menu-picker` is the stable
> version from before the COM rework.

## 8. Troubleshooting

| Symptom | Possible cause | Action |
|---|---|---|
| The menu does not appear at all | File Explorer was not restarted | Restart explorer or log off and back on |
| **The menu does not appear at all** (already restarted) | **The menu key itself does not exist** (deleted by some other script) | Re-run `.\register-com.ps1`; check whether the log has any content |
| The menu does not appear | The CLSID is not registered correctly | `reg query HKCR\CLSID\{1C789ABD-...}` and see whether it exists |
| It appears but does not expand on hover | `GetFlags` did not return `ECF_HASSUBCOMMANDS` | Check `PathAdderCommand.GetFlags`; Explorer relies on it to decide whether to enumerate subcommands |
| **It appears but does not expand on hover** | **`command` subkey and `ExplorerCommandHandler` coexist** → the CLSID gets instantiated twice | See "Key finding" below; run the cleanup step of `.\register-com.ps1` |
| Submenu items show up but clicking does nothing | The interface vtable order is wrong | The method order must match `shobjidl_core.h`; a wrong order makes the call hit the wrong slot |
| PowerShell does not run after a click | `Helper.GetEnginePath()` cannot find the script | Check the relative location of `PathAdderShellExt.dll` and `PathAdder.ps1` |
| Explorer freezes / crashes | A COM method threw an exception | Every COM-visible method must try/catch and return an HRESULT |
| `build.ps1` reports the DLL is in use | Explorer has already loaded the old DLL | Just run `.\rebuild.ps1` (it restarts explorer to release the lock, then rebuilds) |
| 32/64-bit mismatch | The `Framework` (32-bit) directory was used | You must use `Framework64` |
| `regsvr32` reports "entry point DllUnregisterServer not found" | **Wrong tool** | See "Common misconception" below |

### Key finding (measured 2026-10-04): `command` and `ExplorerCommandHandler` are mutually exclusive

This is the most important conclusion from debugging this component, and the vast majority of the
"menu does not expand" rows above stem from it.

If the **same** menu key has both:

- `HKCR\*\shell\PathAdder\command` (an ordinary verb)
- `HKCR\*\shell\PathAdder\ExplorerCommandHandler` = `{CLSID}` (a cascade parent)

Explorer will instantiate the same CLSID **twice** — once as an ordinary verb (only `GetState` /
`Invoke` are called) and once as a cascade parent (`GetFlags` → `GetTitle` → `EnumSubCommands`).
In practice, `%TEMP%\PathAdderShellExt.log` then contains **two `PathAdderCommand constructed`
lines**, and **`SubCommandEnum.Next` never appears** — the path responsible for enumeration never
gets a result, so the symptom is precisely:

> The parent item "PATH Assistant" **is visible**, but **hovering never expands the submenu**.

Step 3.1 of `register-com.ps1` does a **full cleanup** (both `HKLM`/`HKCU` hives, and all four
locations `*` / `exefile` / `Directory` / `AllFilesystemObjects`), then writes to HKLM at a
**single point**, and in step 3.3 reads back and self-checks — a leftover `command` subkey errors
out immediately, instead of waiting until you notice that the menu does not expand.

> Therefore: **do not manually add a `command` subkey after registering `ExplorerCommandHandler`.**
> If you want to keep "click to pop up a menu", run `restore-menu.ps1` to switch the whole thing
> back; do not hand-mix the two modes.

### How To Read The Diagnostic Log

Every COM method entry point of this component writes to `%TEMP%\PathAdderShellExt.log`:

```powershell
type "%TEMP%\PathAdderShellExt.log"
```

| Log content | Conclusion |
|---|---|
| No log file at all | Explorer **never loaded** the DLL → the menu key does not exist or was deleted (the most common real cause of "no submenu") |
| Only `PathAdderCommand constructed` | Explorer created the object but did not treat it as a cascade parent → check whether `GetFlags` returns `ECF_HASSUBCOMMANDS` |
| `GetFlags` / `GetTitle` / `EnumSubCommands` present, but **no `SubCommandEnum.Next`** | The menu is registered twice (see the previous subsection), or Explorer did not recognize it as a cascade parent |
| **`PathAdderCommand constructed` twice** | Confirms duplicate registration → check other locations for a key of the same name |
| `SubCommandEnum.Next` present | The cascade path works; Explorer has taken the subcommands |

### Common misconception: do not use regsvr32 on this DLL

```
regsvr32 /u "E:\...\PathAdderShellExt.dll"
-> module "...dll" was loaded, but the entry point DllUnregisterServer was not found
```

This error is **inevitable, not a failure**:

- `regsvr32` only applies to **native Win32 COM DLLs**; it works by calling the two exported
  functions `DllRegisterServer` / `DllUnregisterServer`.
- This DLL is a **.NET assembly**, and those two exports **do not exist at all** — .NET COM
  registration/unregistration is performed by the `mscoree.dll` proxy (which is why the default
  value of `InprocServer32` is `mscoree.dll`).
- So you must use **`RegAsm.exe`** (and specifically the 64-bit one under `Framework64`):

```powershell
# Unregister
C:\Windows\Microsoft.NET\Framework64\v4.0.30319\RegAsm.exe /unregister "E:\...\PathAdderShellExt.dll"
# Register
C:\Windows\Microsoft.NET\Framework64\v4.0.30319\RegAsm.exe /codebase  "E:\...\PathAdderShellExt.dll"
```

> `register-com.ps1` / `restore-menu.ps1` in this directory already call `RegAsm` internally,
> so **you do not need to run the commands above manually**.
>
> Also: `regsvr32 /u` **cannot fix "DLL in use"** either — that is a file lock caused by
> processes such as explorer loading it into memory, and it can only be released by terminating the
> process that loaded it; the correct action is to restart File Explorer (automated by
> `.\rebuild.ps1`).

## 9. Interface GUID Sources

All taken from the Windows SDK `shobjidl_core.h`, cross-checked against two independent sources,
Vanara and the ReactOS PSDK:

| Interface | GUID |
|---|---|
| `IExplorerCommand` | `a08ce4d0-fa25-44ab-b57c-c7b1c323e0b9` |
| `IEnumExplorerCommand` | `a88826f8-186f-4987-aade-ea0cef8fbfe8` |
| `IShellItem` | `43826d1e-e718-42ee-bc55-a1e261c37bfe` |
| `IShellItemArray` | `b63ea76d-1f85-456f-a19c-48159efa858b` |

This component's own CLSIDs (deterministically generated with uuid5, so they cannot clash with
system components):

| Class | CLSID |
|---|---|
| `PathAdderCommand` (parent menu) | `1C789ABD-65D1-5FAD-8B98-52595EBB290B` |
| `AddUserCommand` | `A7E4EA78-559F-5293-A8AF-A4EC698FA7DC` |
| `AddSystemCommand` | `0674C9EF-7F6F-5C43-AA8B-36DCC81637B6` |
| `RemoveCommand` | `124AC498-75CF-5595-B46B-2CEFD81211A4` |
| `SeparatorCommand` | `4B5172F7-E928-506A-BABA-DFD251355925` |
| `ManagerCommand` | `9921ED8D-5AAF-563A-BAF4-0276A003291B` |
| `SubCommandEnum` | `53E97A7A-9ECB-5EC8-8499-CE6030C691BB` |

## 10. Known Limitations

1. **Not compiled or verified in this environment**: the development environment's security policy
   forbids invoking the compiler (`csc.exe` / `Add-Type` are blocked), so this C# code **has not
   been actually compiled and run**. GUIDs and interface definitions have been cross-checked, but
   please run `.\build.ps1` on your own machine to confirm it compiles before registering.
2. **The Windows 11 first-layer menu requires MSIX packaging**; the registry route only reaches the
   classic menu (see section 2).
3. A .NET COM DLL loads the CLR inside the explorer process; if the system .NET Framework is
   damaged or has a version conflict, the menu may become unresponsive. The more robust industry
   approach is a C++/ATL implementation (no CLR dependency).
4. `RegAsm /codebase` writes the DLL's absolute path into the registry, so **you must re-register
   after moving the directory**.

## 11. Localizing the COM Strings (`L10n`)

The strings shown by the C# shell extension are **not** loaded from the `.ps1` language packs; they
are embedded in the **`L10n` class inside `com\PathAdderShellExt.cs`**.

- English (`en-US`) is the fallback column and must stay complete.
- To add a language, add one column for that language in `L10n`, fill in every string, and
  **recompile the DLL** (`build.ps1`) — the strings are baked into the binary, so a rebuild plus a
  re-registration is mandatory for them to take effect.
- The language the extension picks at runtime comes from the same resolution chain as the
  PowerShell side (see the "Language" section of the top-level `README.md`); inside `explorer.exe`
  it is effectively read from the registry value `HKCU\Software\PathAdder\Language`.
- Menu text is baked into the registry at registration time, so after switching language you must
  re-run `register-contextmenu.ps1` and restart File Explorer before the menu text refreshes.
