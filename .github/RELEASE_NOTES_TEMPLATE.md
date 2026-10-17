<!--
  PathAdder release notes template.

  Used by .github/workflows/release.yml (step "Render release notes") as the
  source for the GitHub Release body.

  Placeholders are replaced with plain PowerShell string replacement -- there is
  no templating engine and no third-party action involved. The workflow FAILS if
  any placeholder token survives rendering, so every token used in the body MUST
  be one of the supported ones.

  Supported placeholders (uppercase, wrapped in DOUBLE CURLY BRACES):
      VERSION          e.g. 1.0.0
      TAG              e.g. v1.0.0
      ZIP_NAME         e.g. PathAdder-v1.0.0-win-x64.zip
      DLL_SHA256       SHA256 of com\PathAdderShellExt.dll, uppercase hex
      RELEASE_DATE     yyyy-MM-dd (runner local date)
      PRERELEASE_NOTE  a one-line pre-release banner, or empty

  IMPORTANT: this comment block is STRIPPED before substitution, so you may
  describe the tokens above in plain words. Any placeholder written inside the
  body (below the marker line) WILL be substituted -- keep this header free of
  literal double-curly tokens to avoid confusing future maintainers.

  Editing rules:
    * Keep both language sections; the project ships English + Simplified Chinese.
    * Do NOT add a BOM to this file -- see docs/design-open-source-release.md §9.1.
    * Keep the "What's Changed" lists short and user-facing; internal refactors
      belong in the commit log, not in release notes.
-->

## PathAdder {{TAG}}

{{PRERELEASE_NOTE}}

A zero-dependency Windows tool that adds a program's folder to PATH straight from the right-click menu.

[中文说明见下](#中文说明)

### Install / 安装

1. Download **`{{ZIP_NAME}}`** and extract it anywhere (it contains a single folder, `PathAdder-{{TAG}}/`).
2. Double-click `install.bat`. No administrator rights are needed for a user-level install.
3. Restart File Explorer when the installer asks, then right-click any file →
   **Show more options** (Windows 11) → **PATH Assistant**.

> On Windows 11 the entry is in the **second** level of the context menu — not seeing it in the first level is expected.

### What's Changed / 本次变更

- (English) Initial public release: right-click add/remove PATH, user and system scope, automatic backup, `PATH Manager` GUI, English + Simplified Chinese UI.
- (中文) 首个公开版本：右键添加/移除 PATH、用户级与系统级、自动备份、`PATH Manager` 图形界面、中英文界面。

### Requirements / 系统要求

- Windows 10 1809+ / Windows 11, **x64 only** (`explorer.exe` is a 64-bit process)
- Windows PowerShell 5.1 — built into Windows, nothing to install
- No admin rights required for a user-level install; admin rights only for machine-wide PATH changes

### Bundle contents / 包内容

- All PowerShell entry points and launchers (`install`/`uninstall`/`verify`)
- Language packs for `en-US` and `zh-CN` (8 shards each)
- Pre-compiled `com\PathAdderShellExt.dll` (x64)
- Full C# source of the shell extension, so you can rebuild it locally
- `LICENSE` (GNU General Public License v3.0 or later) and `version.json`

**SHA256 of `com\PathAdderShellExt.dll`:** `{{DLL_SHA256}}`

### Verify the download / 校验下载

```powershell
# From the extracted folder:
Get-FileHash .\com\PathAdderShellExt.dll -Algorithm SHA256
```

The hash must equal `{{DLL_SHA256}}`.

### License / 许可证

PathAdder is free software under the **GNU General Public License v3.0 or later**.
Copyright (C) 2026 w0i0c0o. See `LICENSE` in the package for the full terms.

---

## 中文说明

一个**零依赖**的 Windows 小工具：右键任意文件，把该程序所在的文件夹加入 PATH。

### 安装

1. 下载 **`{{ZIP_NAME}}`**，解压到任意目录（压缩包内只有一个顶层文件夹 `PathAdder-{{TAG}}/`）。
2. 双击 `install.bat`。用户级安装**不需要管理员权限**。
3. 按安装脚本提示重启资源管理器，然后在任意文件上右键 →
   **显示更多选项**（Windows 11）→ **PATH 助手**。

> Windows 11 上该菜单项位于**第二级**菜单中——第一级看不到是正常的。

### 本次变更

- （中文）首个公开版本：右键添加/移除 PATH、用户级与系统级、自动备份、`PATH Manager` 图形界面、中英文界面。

### 系统要求

- Windows 10 1809+ / Windows 11，**仅支持 x64**（`explorer.exe` 是 64 位进程）
- Windows PowerShell 5.1（系统自带，无需安装）
- 用户级安装不需要管理员权限；只有修改**系统级** PATH 才需要管理员

### 卸载

双击 `uninstall.bat`。备份与日志保留在 `%LOCALAPPDATA%\PathAdder\`，可手动删除。

### 校验

```powershell
# 在解压出来的目录里执行：
Get-FileHash .\com\PathAdderShellExt.dll -Algorithm SHA256
```

结果必须等于 `{{DLL_SHA256}}`。

### 许可证

PathAdder 是自由软件，采用 **GNU General Public License v3.0 or later**。
版权所有 (C) 2026 w0i0c0o。完整条款见包内 `LICENSE`。

---

**Full documentation / 完整文档:** [English](README.md) | [简体中文](README.zh-CN.md)

*Released on {{RELEASE_DATE}}.*
