# PathAdder COM 外壳扩展（原生悬停级联）

> ## ⚠ 重要：`IExplorerCommand` 这条路实测走不通，请直接用经典菜单扩展
>
> 2026-10-04 在本机（Windows 11 25H2 / 26200）实测结论：
> `IExplorerCommand` + `ECF_HASSUBCOMMANDS` 的级联**不生效**。诊断日志显示
> Explorer 走完了 `GetFlags`(拿到 HASSUBCOMMANDS) → `GetTitle` → `EnumSubCommands`
> （枚举器都构造成功了），**却永远不会调用 `IEnumExplorerCommand::Next`**，
> 而是再造一个对象只调 `GetState` 就收场。
>
> 清理掉重复的 `command` / `ExplorerCommandHandler` 注册后**行为完全不变**，
> 说明这是 Explorer 自身的策略，不是我们的代码缺陷。
>
> 👉 **当前推荐方案：`PathAdderContextMenu.cs`**（`IShellExtInit` + `IContextMenu`
> + `CreatePopupMenu` 造 POPUP 子菜单），安装脚本是 **`register-contextmenu.ps1`**。
> 子菜单的悬停展开由 USER32 菜单系统负责，是标准菜单行为，不依赖 Explorer 的
> 扩展策略（TortoiseGit / TortoiseSVN 等成熟扩展都是这么做的）。
> 本文件后半部分保留 `IExplorerCommand` 的完整记录，仅供对照，不建议再用。

## 1. 这是用来解决什么的

Windows 原生的 `SubCommands` 静态级联在 Windows 11 上实测**悬停不展开**（父项可见、
悬停无反应，且因该机制要求父项不能带 `command`，点击也无效）。

上一版因此改用「点击父项 → `MenuPicker.ps1` 在光标处弹出菜单」——功能可用，
但**需要点击而非悬停**。

本目录提供真正的原生方案：实现 `IExplorerCommand` + `IEnumExplorerCommand`，
由 Explorer 自己枚举子命令，从而实现**鼠标悬停自动展开**的级联子菜单。

| 方案 | 交互 | 可靠性 | 代价 |
|---|---|---|---|
| `SubCommands`（已废弃） | 悬停 | ❌ Win11 不展开 | — |
| `MenuPicker.ps1`（当前默认） | **点击** | ✅ 100% | 多一次点击 |
| **本 COM 扩展** | **悬停** | 取决于注册方式 | 需编译、注册、重启 |

## 2. 关键前提：Windows 11 的菜单分层

⚠️ **这是最容易踩的坑，务必先读。**

Windows 11 有两套右键菜单：

| 菜单 | 注册方式 | 本扩展是否可见 |
|---|---|---|
| **新版精简菜单**（第一层） | 必须 **MSIX 打包** + `desktop4:FileExplorerContextMenus` 声明 | ❌ 仅注册表注册**看不到** |
| **经典菜单**（「显示更多选项」/ `Shift+F10`） | 注册表 `ExplorerCommandHandler` | ✅ 可见 |

也就是说：**只做注册表注册，菜单只会出现在「显示更多选项」里**——这和现在的
MenuPicker 模式位置一样，唯一改善是「悬停」替代「点击」。

若你想让它出现在 Win11 第一层，必须额外做 MSIX 打包（见第 5 节）。

## 3. 前置条件

- Windows 10 1809+ / Windows 11
- **.NET Framework 4.x**（Windows 自带，`csc.exe` 与 `RegAsm.exe` 均在其目录下）
- **管理员权限**（`RegAsm` 要写 `HKLM` 注册 COM 类）
- 本目录可写（编译产物 DLL 会生成在这里）

> 64 位要点：脚本固定使用 `Framework64` 目录下的 64 位编译器与 `RegAsm`。
> `explorer.exe` 在 64 位 Windows 上是 64 位进程，**32 位 DLL 无法被它加载**。

## 4. 安装步骤（推荐：经典菜单扩展）

以**管理员**身份打开 PowerShell 或终端：

```powershell
cd E:\幸玮代码\Buddy_Space\8_Path\PathAdder\com
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\register-contextmenu.ps1
```

脚本会做五件事：

1. `build.ps1` —— 把 `PathAdderShellExt.cs`（公共 Helper/Native）与
   `PathAdderContextMenu.cs`（菜单扩展）编译进同一个 `PathAdderShellExt.dll`
2. `RegAsm.exe /codebase` 注册 COM 类（写 HKLM）
3. 彻底清除旧的 `*\shell\PathAdder`（`IExplorerCommand` 那条），避免同一功能出现两个菜单
4. 写 `HKLM\Software\Classes\*\shellex\ContextMenuHandlers\PathAdder` =
   `{9B3E5D2A-7C41-4F8B-A1D6-2E5C8F40B7A3}`，并加入 Shell Extensions Approved 列表
5. 回读自检，不通过直接报错退出

### 必须重启资源管理器

```powershell
Stop-Process -Name explorer -Force; Start-Process explorer.exe
```

卸载：

```powershell
.\register-contextmenu.ps1 -Unregister
```

### DLL 被占用怎么办（重编译/重注册前必读）

`explorer.exe` 加载过本 DLL 后就一直持有它：允许**改名**，但**不允许写入/覆盖**，
于是新 DLL 编不到原路径，表现为 `build.ps1` 报错「DLL 正被占用」。

脚本已经自动处理了，但如果你想手动来，就是这个顺序：

```powershell
cd E:\幸玮代码\Buddy_Space\8_Path\PathAdder\com

# ① 找出是谁在持有这个模块
tasklist /m PathAdderShellExt

# ② 终止资源管理器（以及上面列出的其它持有者）
Stop-Process -Name explorer -Force

# ③ 立刻重新拉起，否则桌面会消失
Start-Process explorer.exe

# ④ 再编译 / 注册
.\register-contextmenu.ps1
```

`release-dll.ps1` 把上面 ①② ③ 自动化了，并会轮询等待文件真正可写（最多 12 秒）：

```powershell
.\release-dll.ps1                    # 释放并自动重启资源管理器
.\release-dll.ps1 -NoRestartExplorer # 只释放，不重启
```

`build.ps1` 检测到占用时会先调它，失败了才退回到「改名绕过」。
若最后仍报占用，通常是杀毒软件在扫描该文件——等 10~30 秒重试，或把
`PathAdder\com` 目录加入排除项；实在不行就注销重登（比重启快）。

> 再次强调：**不要用 `regsvr32 /u` 试图「卸载」本 DLL**。它是 .NET 程序集，
> 没有 `DllUnregisterServer` 导出，该命令必然报「找不到入口点」，而且**解除不了文件锁**。

---

## 4b. 安装步骤（已证实不可用：IExplorerCommand 级联）

> 仅供记录。**不要再走这条路**，原因见文首的重要提示。

---

以**管理员**身份打开 PowerShell 或终端：

```powershell
cd E:\幸玮代码\Buddy_Space\8_Path\PathAdder\com

# 一步完成：编译 + 注册 + 切换菜单位
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\register-com.ps1
```

脚本会依次做四件事：

1. `build.ps1` —— 用 `csc.exe` 编译 `PathAdderShellExt.cs` → `PathAdderShellExt.dll`
2. `RegAsm.exe /codebase` 注册 COM 类（写 HKLM）
3. 全量清理历史残留键后，**单点**在 `HKLM\Software\Classes\*\shell\PathAdder`
   写入 `ExplorerCommandHandler` = 父命令 CLSID，并确保没有 `command` 子键
   （两者互斥，见第 8 节「关键发现」），然后回读自检
4. `SHChangeNotify` 通知资源管理器

### 必须重启资源管理器

```powershell
Stop-Process -Name explorer -Force; Start-Process explorer.exe
```

不重启菜单不会变化（`SHChangeNotify` 在 Win11 上经常不够）。

## 5. 让菜单出现在 Win11 第一层（MSIX 打包）

注册表方式只进经典菜单。要进新版菜单，需要：

1. Visual Studio 2022（含「Windows 应用程序打包项目」负载）
2. 建 Windows 应用程序打包项目，把 `PathAdderShellExt.dll` 加入资源
3. 在 `Package.appxmanifest` 中声明：

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
      <uap:VisualElements DisplayName="PathAdder" Description="PATH 助手"
                          BackgroundColor="transparent" Square150x150Logo="Images\Square150x150Logo.png"
                          Square44x44Logo="Images\Square44x44Logo.png" />
      <Extensions>
        <!-- 注册 COM 代理（SurrogateServer 让 DLL 在独立进程中被加载） -->
        <com:Extension Category="windows.comServer">
          <com:ComServer>
            <com:SurrogateServer DisplayName="PathAdder Shell Extension">
              <com:Class Id="1C789ABD-65D1-5FAD-8B98-52595EBB290B" Path="PathAdderShellExt.dll" ThreadingModel="STA" />
            </com:SurrogateServer>
          </com:ComServer>
        </com:Extension>

        <!-- 新版（Win11 第一层）右键菜单 -->
        <desktop4:Extension Category="windows.fileExplorerContextMenus">
          <desktop4:FileExplorerContextMenus>
            <desktop4:ItemType Type="*">
              <desktop4:Verb Id="PathAdder" Clsid="1C789ABD-65D1-5FAD-8B98-52595EBB290B" />
            </desktop4:ItemType>
          </desktop4:FileExplorerContextMenus>
        </desktop4:Extension>

        <!-- 经典菜单（显示更多选项） -->
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

4. 打包为 MSIX 并安装（需受信任的证书，或用自签名证书并信任它）

> 这一步工程量明显大于前面的注册表方式，且需要 Visual Studio。
> 若你只需要「悬停」而不必在第一层，注册表方式（第 4 节）就够了。

## 6. 验证

1. 重启资源管理器
2. 右键**任意文件** → 点「显示更多选项」（或选中后按 `Shift+F10`）
3. 找到「PATH 助手」
4. **把鼠标悬停**在上面 —— 应自动展开：
   - 添加到 PATH（当前用户）
   - 添加到 PATH（系统全局，管理员）← 带 UAC 盾牌图标
   - 从 PATH 中移除此目录
   - ──────────（分隔线）
   - 打开 PATH 管理器

## 7. 回滚

```powershell
# 回到「点击弹出菜单」模式并注销 COM
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\restore-menu.ps1

# 若 DLL 正被 explorer 占用导致注销失败
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\restore-menu.ps1 -KeepComRegistration
```

之后重启资源管理器。

> 代码层面也可回滚：仓库标签 `v1.0-menu-picker` 是 COM 改造前的稳定版本。

## 8. 故障排查

| 现象 | 可能原因 | 处理 |
|---|---|---|
| 菜单完全不出现 | 没重启资源管理器 | 重启 explorer 或注销重登 |
| **菜单完全不出现**（已重启过） | **菜单键本身不存在**（被别的脚本删了） | 重跑 `.\register-com.ps1`；确认日志里是否有内容 |
| 菜单不出现 | CLSID 未正确注册 | `reg query HKCR\CLSID\{1C789ABD-...}` 看是否存在 |
| 出现但悬停不展开 | `GetFlags` 未返回 `ECF_HASSUBCOMMANDS` | 检查 `PathAdderCommand.GetFlags`；Explorer 靠它决定是否枚举子命令 |
| **出现但悬停不展开** | **`command` 子键与 `ExplorerCommandHandler` 并存** → CLSID 被实例化两遍 | 见下方「关键发现」；跑 `.\register-com.ps1` 的清理步骤 |
| 子菜单项显示但点击无效 | 接口 vtable 顺序错了 | 方法顺序必须与 `shobjidl_core.h` 一致，顺序错会让调用打到错误槽位 |
| 点击后 PowerShell 不执行 | `Helper.GetEnginePath()` 找不到脚本 | 确认 `PathAdderShellExt.dll` 与 `PathAdder.ps1` 的相对位置 |
| Explorer 卡死/崩溃 | COM 方法抛了异常 | 所有 COM 可见方法都必须 try/catch 并返回 HRESULT |
| `build.ps1` 报 DLL 被占用 | explorer 已加载旧 DLL | 直接跑 `.\rebuild.ps1`（自动重启 explorer 释放占用后重编译） |
| 32/64 位不匹配 | 用了 `Framework`（32 位）目录 | 必须用 `Framework64` |
| `regsvr32` 报「找不到入口点 DllUnregisterServer」 | **用错工具了** | 见下方「常见误区」 |

### 关键发现（2026-10-04 实测）：`command` 与 `ExplorerCommandHandler` 互斥

这是本组件调试过程中最重要的结论，前面的 Row「菜单不展开」绝大多数都源于此。

若同一个菜单键 **同时** 存在：

- `HKCR\*\shell\PathAdder\command`（普通动词）
- `HKCR\*\shell\PathAdder\ExplorerCommandHandler` = `{CLSID}`（级联父项）

Explorer 会把同一个 CLSID **实例化两遍**——一遍按普通动词走（只调 `GetState` /
`Invoke`），另一遍按级联父项走（调 `GetFlags` → `GetTitle` → `EnumSubCommands`）。
实测 `%TEMP%\PathAdderShellExt.log` 里就会出现**两条 `PathAdderCommand 构造`**，
并且**永远不会出现 `SubCommandEnum.Next`**——负责枚举的那一路拿不到结果，
于是现象精确表现为：

> 父项「PATH 助手」**看得见**，但**悬停永远不展开子菜单**。

`register-com.ps1` 的 3.1 步会做**全量清理**（含 `HKLM`/`HKCU` 两个 hive、
`*` / `exefile` / `Directory` / `AllFilesystemObjects` 四个位置），
再**单点写入** HKLM，并在 3.3 步回读自检——`command` 子键残留会直接报错退出，
而不是等到你发现没展开才察觉。

> 因此：**不要在注册了 `ExplorerCommandHandler` 之后再去手动补 `command` 子键。**
> 想保留「点击弹出菜单」就跑 `restore-menu.ps1` 整体切回，不要手工拼混两种模式。

### 诊断日志怎么读

组件的每个 COM 方法入口都写日志到 `%TEMP%\PathAdderShellExt.log`：

```powershell
type "%TEMP%\PathAdderShellExt.log"
```

| 日志内容 | 结论 |
|---|---|
| 完全没有日志文件 | Explorer **从未加载** DLL → 菜单键不存在或被删了（这是最常见的「没子菜单」真因） |
| 只有 `PathAdderCommand 构造` | Explorer 创建了对象但没当级联父项用 → 检查 `GetFlags` 是否返回 `ECF_HASSUBCOMMANDS` |
| 有 `GetFlags` / `GetTitle` / `EnumSubCommands`，但**没有 `SubCommandEnum.Next`** | 菜单被重复注册了（见上一小节），或 Explorer 没把它识别为级联父项 |
| **出现两次 `PathAdderCommand 构造`** | 确认重复注册 → 检查其它位置的同名键 |
| 出现 `SubCommandEnum.Next` | 级联链路已通，子命令已被 Explorer 取走 |

### 常见误区：不要用 regsvr32 操作这个 DLL

```
regsvr32 /u "E:\...\PathAdderShellExt.dll"
-> 模块"...dll"已加载，但找不到入口点 DllUnregisterServer
```

这个报错是**必然的，不是故障**：

- `regsvr32` 只适用于**原生 Win32 COM DLL**，它靠调用 DLL 导出的
  `DllRegisterServer` / `DllUnregisterServer` 两个函数干活。
- 本 DLL 是 **.NET 程序集**，这两个导出函数**根本不存在** —— .NET 的 COM
  注册/注销是由 `mscoree.dll` 代理完成的（所以 `InprocServer32` 的默认值是
  `mscoree.dll`）。
- 因此必须用 **`RegAsm.exe`**（且必须是 `Framework64` 下的 64 位版本）：

```powershell
# 注销
C:\Windows\Microsoft.NET\Framework64\v4.0.30319\RegAsm.exe /unregister "E:\...\PathAdderShellExt.dll"
# 注册
C:\Windows\Microsoft.NET\Framework64\v4.0.30319\RegAsm.exe /codebase  "E:\...\PathAdderShellExt.dll"
```

> 本目录的 `register-com.ps1` / `restore-menu.ps1` 内部已经调用 `RegAsm`，
> **不需要你手动执行上述命令**。
>
> 另：`regsvr32 /u` 也**解决不了「DLL 被占用」** —— 占用是 explorer 等进程
> 把它加载进内存导致的文件锁，只有释放加载它的进程才能解除，
> 正确做法是重启资源管理器（`.\rebuild.ps1` 已自动化）。

## 9. 接口 GUID 来源

均取自 Windows SDK `shobjidl_core.h`，并与 Vanara、ReactOS PSDK 两个独立来源交叉核对：

| 接口 | GUID |
|---|---|
| `IExplorerCommand` | `a08ce4d0-fa25-44ab-b57c-c7b1c323e0b9` |
| `IEnumExplorerCommand` | `a88826f8-186f-4987-aade-ea0cef8fbfe8` |
| `IShellItem` | `43826d1e-e718-42ee-bc55-a1e261c37bfe` |
| `IShellItemArray` | `b63ea76d-1f85-456f-a19c-48159efa858b` |

本组件自己的 CLSID（由 uuid5 确定性生成，不会与系统组件冲突）：

| 类 | CLSID |
|---|---|
| `PathAdderCommand`（父菜单） | `1C789ABD-65D1-5FAD-8B98-52595EBB290B` |
| `AddUserCommand` | `A7E4EA78-559F-5293-A8AF-A4EC698FA7DC` |
| `AddSystemCommand` | `0674C9EF-7F6F-5C43-AA8B-36DCC81637B6` |
| `RemoveCommand` | `124AC498-75CF-5595-B46B-2CEFD81211A4` |
| `SeparatorCommand` | `4B5172F7-E928-506A-BABA-DFD251355925` |
| `ManagerCommand` | `9921ED8D-5AAF-563A-BAF4-0276A003291B` |
| `SubCommandEnum` | `53E97A7A-9ECB-5EC8-8499-CE6030C691BB` |

## 10. 已知限制

1. **未在本环境编译验证过**：开发环境的安全策略禁止调用编译器（`csc.exe` /
   `Add-Type` 被拦截），因此这份 C# 代码**没有经过实际编译和运行验证**。
   GUID 与接口定义已交叉核对，但请在你的机器上先 `.\build.ps1` 确认能编过，
   再执行注册。
2. **Windows 11 第一层菜单需要 MSIX 打包**，注册表方式只进经典菜单（见第 2 节）。
3. .NET COM DLL 在 explorer 进程中会加载 CLR；若系统 .NET Framework 损坏或
   版本冲突，可能导致菜单无响应。业界更稳的做法是 C++/ATL 实现（无 CLR 依赖）。
4. `RegAsm /codebase` 会把 DLL 的绝对路径写进注册表，**移动目录后需重新注册**。
