[English](README.md) | [简体中文](README.zh-CN.md)

# PathAdder —— 右键一键把程序所在目录加入 PATH

一个**零依赖**（仅 Windows PowerShell 5.1 + .NET Framework）的小工具：在资源管理器里右键点击任意 `.exe` 程序文件，即可把它所在的文件夹加入系统 PATH，让命令行可以直接运行该程序。

- 免管理员安装（只写 `HKCU`，不碰系统目录）
- 修改 PATH 前**自动备份**，随时可回滚
- 支持用户级 / 系统级 PATH，系统级通过 UAC 自提权
- 自带 GUI「PATH 管理器」：查看路径、备份历史、恢复、变更日志

---

## 1. 安装

1. 双击 **`install.bat`**（推荐），或在 PowerShell 中执行：

   ```powershell
   powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File ".\install.ps1"
   ```

2. 弹出「安装完成」提示即表示成功。

---

## ⚠️ 1.5 必须重启资源管理器，菜单才会出现（最重要的一步）

**安装脚本写完注册表后，右键菜单通常仍然不会立刻出现——这是正常的，不是安装失败。**

原因是资源管理器会缓存菜单与文件关联。`install.ps1` 已经发出了
`SHChangeNotify(SHCNE_ASSOCCHANGED)` 通知，但**在 Windows 11 上这个通知并不总是生效**，
实测必须重启 explorer 进程或注销重登才会真正出现在菜单里。

所以请你**二选一**完成重启：

```powershell
Stop-Process -Name explorer -Force; Start-Process explorer.exe
```

或者直接**注销当前 Windows 账户后重新登录**。

> 安装结束时脚本会**弹框询问**是否立即帮你重启（默认按钮是「否」）。
> 因为重启会关闭所有已打开的文件夹窗口，脚本**绝不会未经询问直接重启**。
> 脚本化调用可用开关控制：
>
> | 开关 | 行为 |
> |---|---|
> | （默认，都不指定） | 弹框询问，默认「否」 |
> | `-RestartExplorer` | 不询问，直接重启（批量部署用） |
> | `-NoRestart` | 不询问也不重启 |
>
> ```powershell
> install.ps1 -RestartExplorer   # 直接重启
> install.ps1 -NoRestart         # 完全不碰资源管理器
> ```

---

### 3. 菜单怎么用

在**任意文件**（任意类型，含 `.exe`）上右键，菜单里会出现一项 **「PATH 助手」**。
**点击**它，会在鼠标位置弹出本工具的操作菜单：

| 菜单项 | 作用 | 是否需要管理员 |
|---|---|---|
| 添加到 PATH（当前用户） | 写入 `HKCU\Environment\Path` | 否 |
| 添加到 PATH（系统全局，管理员） | 写入 `HKLM\...\Session Manager\Environment\Path` | 是（UAC 弹窗） |
| 从 PATH 中移除此目录 | 同时从用户 PATH 与系统 PATH 移除 | 用户级否 / 系统级是 |
| 打开 PATH 管理器 | 打开 GUI 管理窗口 | 否（操作系统 PATH 时需要） |

菜单顶部有一行**灰色、不可点击**的目录名，用来确认当前操作的是哪个目录。

4 个动作收拢在**一个父菜单项**里，一级菜单只占一行，不干扰你的其它菜单项。

> ℹ️ **关于「点击」而不是「悬停」**
>
> 本工具早期版本使用 Windows 原生的 `SubCommands` 静态级联（鼠标悬停自动展开），
> 但在 **Windows 11 上实测失败**：父菜单能显示，**悬停完全不展开**，且因该机制
> 要求父项不能带 `command`，**点击也毫无反应**——功能彻底不可用。详见 §5.2。
>
> 因此现版本改为：「点击 → 在光标位置弹出菜单」，外观与交互和原生右键子菜单
> 基本一致，且不依赖 Explorer 的级联实现，可靠性 100%。代价是需要多一次点击。

> ⚠️ **Windows 11 必读：菜单在「显示更多选项」里**
>
> Windows 11 把传统右键菜单（verb）收进了分层菜单的第二层，**第一层只显示少量
> 固定项**（复制 / 粘贴 / 删除 / 重命名 / 属性等），本工具的 4 个菜单项不在第一层。
> 查看方式，任选一种：
>
> - 在 `.exe` 上**右键 → 点「显示更多选项」**；
> - **选中**文件后按 **`Shift` + `F10`**；
> - 选中文件后按 **`Shift` + `方向键`** 展开经典菜单；
> - 也可用**触控板/键盘**：菜单弹出后按 **`Shift` + `F10`** 或直接按左方向键。
>
> 这是 Windows 11 的系统行为，不是本工具的限制。Windows 10 及更早系统直接右键即可看到。

> 若菜单仍未出现：安装脚本已自动调用 `SHChangeNotify(SHCNE_ASSOCCHANGED)` 通知资源
> 管理器丢弃菜单缓存，通常立即生效。若仍未出现，请手动重启一次资源管理器或注销重登：
>
> ```powershell
> Stop-Process -Name explorer -Force; Start-Process explorer.exe
> ```

> ⚠️ **Windows 11 必读：菜单在「显示更多选项」里**
>
> Windows 11 把传统右键菜单收进了分层菜单的第二层，**第一层只显示少量固定项**
> （复制 / 粘贴 / 删除 / 重命名 / 属性等），「PATH 助手」不在第一层。查看方式任选：
>
> - 右键 → 点 **「显示更多选项」**；
> - **选中**文件后按 **`Shift` + `F10`**；
> - 选中文件后按 **`Shift` + `方向键`** 展开经典菜单。
>
> 这是 Windows 11 的系统行为，不是本工具的限制。Windows 10 及更早系统直接右键即可。

### 验证安装是否成功

双击 **`verify.bat`**，或运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File ".\verify-registration.ps1"
```

它会分多层检查：父菜单结构与 `command` 子键、HKLM 侧系统菜单是否完好、
历史位置是否有残留、默认动词是否被误改、第三方菜单是否被误伤，并尝试调用 Shell COM
**真实枚举**一次右键菜单（`.exe` 与 `.txt` 各一个）。详见 [§5.9](#510-验证脚本verify-registrationps1)。

> 注意：验证脚本只能验证「注册表与 Shell 这一侧」。若你**还没重启资源管理器**，
> 脚本可能提示结构完整但菜单未构建——请先完成上面的重启步骤再看菜单。

### 卸载

双击 **`uninstall.bat`**，或：

```powershell
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File ".\uninstall.ps1"
```

卸载会清理**所有位置**（当前位置 + 两个历史位置），见下表：

| # | 位置 | 清理内容 |
|---|---|---|
| 1 | `HKCU\Software\Classes\*\shell\PathAdder` | 当前版本的级联菜单（整棵子树） |
| 2 | `HKCU\Software\Classes\exefile\shell\PathAdder*` | 早期版本扁平注册的 4 项 |
| 3 | `HKCU\Software\Classes\SystemFileAssociations\.exe\shell\PathAdder*` | 早期版本兜底注册的 4 项 |

这样即使你装过旧版本，升级后也不会留下孤儿菜单项。卸载后**同样需要重启资源管理器**
才会从菜单里消失（脚本会询问是否帮你重启）。

卸载只会删除右键菜单；**备份与日志会保留**在 `%LOCALAPPDATA%\PathAdder\`，方便你随时回滚。如需彻底清理，手动删除该目录即可。

---

## 2. 用法示例

假设：`D:\Tools\ffmpeg-6.0\bin\ffmpeg.exe`

1. 右键 `ffmpeg.exe` → **「添加到 PATH（当前用户）」**
2. 弹出提示：`已成功添加到【用户 PATH（当前用户）】`，并显示目录 `D:\Tools\ffmpeg-6.0\bin` 与备份文件名
3. **新打开**一个 cmd / PowerShell 窗口，直接输入 `ffmpeg -version` 即可运行

> 已打开的命令行窗口不会自动感知变化，需要重新打开（工具已广播 `WM_SETTINGCHANGE`，资源管理器与大部分程序会自动刷新）。

撤销：右键同一个 `.exe` → **「从 PATH 中移除此目录」**，用户级与系统级会同时处理；系统级若提权失败，只做用户级并明确提示。

---

## 3. 文件说明

```
PathAdder\
├── PathAdder.ps1      # 核心引擎：右键菜单实际调用的入口
│                      #   -Action Add/Remove/Restore/OpenManager
│                      #   -Scope User/System/All   -Target <文件或目录>
│                      #   -BackupFile <备份文件名>  -Elevated（内部提权标记）
├── PathManager.ps1    # PATH 管理器 GUI（WinForms）
│                      #   · 用户 PATH / 系统 PATH 列表（带序号）
│                      #   · 备份历史（预览 / 恢复 / 刷新）
│                      #   · 变更日志（倒序最近 200 条）
│                      #   · 刷新 / 打开备份目录 / 打开变更日志 / 关闭
├── install.ps1        # 注册右键菜单（用户级，幂等）
│                      #   -RestartExplorer / -NoRestart 控制是否重启资源管理器
├── uninstall.ps1      # 清除右键菜单（幂等，当前 + 两个历史位置都清）
│                      #   -RestartExplorer / -NoRestart 同 install.ps1
├── verify-registration.ps1  # 【独立诊断工具】验证注册是否真的生效
│                      #   · 第 1 层：级联菜单结构完整性（含「父项无 command」断言）
│                      #   · 第 1.2 层：历史位置残留检查
│                      #   · 第 1.3 层：默认动词安全性
│                      #   · 第 1.5 层：HKLM 系统菜单完好性
│                      #   · 第 2 层：真实 IContextMenu 枚举（.exe + .txt）
│                      #   · 第 2 层降级：合并视图关联解析推演
│                      #   · 第 3 层：第三方菜单存活检查
│                      #   退出码 0=通过 1=有失败 2=环境不足未验证
├── install.bat        # 双击安装入口（内部调用 install.ps1）
├── uninstall.bat      # 双击卸载入口（内部调用 uninstall.ps1）
├── verify.bat         # 双击验证入口（内部调用 verify-registration.ps1）
├── lib\Common.ps1     # 公共函数库：PATH 读写、去重比较、备份、日志、
│                      # 弹窗、管理员检测、UAC 自提权、环境变更广播
├── lib\ShellMenu.ps1  # 右键菜单库：4 个 verb 的唯一定义源、注册/卸载、
│                      # SHChangeNotify 刷新、空键回收
│                      #   （安装与卸载共用同一份 verb 定义，避免两处漂移）
├── lib\i18n.ps1       # i18n 运行时：语言解析优先级、语言包加载、支持语言列表、
│                      # 配置文件/注册表持久化、Set-PathAdderLanguage /
│                      # Get-PathAdderLanguage
├── lang\              # 语言包（见 §9 语言）
│   ├── en-US\         # 英文（美国）——兜底底座，必须保持完整
│   └── zh-CN\         # 简体中文
│                      #   每种语言下都是同样的 8 个分片：
│                      #   core / shell / picker / gui / cli / setup / verify / com
├── com\               # C# 外壳扩展（见 com\README-COM.md）
├── README.md          # 本文档的英文版
└── README.zh-CN.md    # 本文档（简体中文）
```

---

## 4. 备份与日志

- 备份目录：`%LOCALAPPDATA%\PathAdder\backups\`
- 命名规则：`<scope>-<yyyyMMdd-HHmmss>.txt`，例如 `user-20261002-070000.txt`、`system-20261002-070000.txt`
- 同秒重复操作时自动追加序号：`user-20261002-070000-1.txt`
- 变更日志：`%LOCALAPPDATA%\PathAdder\change.log`

  日志行格式（人可读，也可被程序解析）：

  ```
  [2026-10-02 07:00:00] 动作=Add 范围=User 目录=D:\Tools\bin 备份=user-20261002-070000.txt 类型=ExpandString
  ```

- **恢复**：在「PATH 管理器 → 备份历史」中选中一条备份，点「恢复到此次备份」。
  恢复前会**再次自动备份当前 PATH**，因此恢复本身也是可回滚的。

---

## 5. 关键实现决策

### 5.1 注册位置：`HKCU\Software\Classes\*\shell\PathAdder`

> **这一节记录了两轮真实缺陷及其修复。**如果你遇到「安装成功、注册表里键和值
> 全都齐全，但右键菜单完全不出现」，原因基本都在这里。

#### 当前位置：`*` = 所有文件对象

```
HKCU\Software\Classes\*\shell\PathAdder
```

`HKCR\*` 是 Windows 官方支持的「**所有文件对象**」关联键，无条件覆盖任意扩展名
（包括 `.exe`）。这样右键任何文件都能用，不需要为每种扩展名各注册一份。

#### 缺陷一（早期版本）：只注册在 `SystemFileAssociations\.exe\shell`

那时注册表检查一切正常——4 个子键齐全、`(Default)`/`MUIVerb`/`command` 都在、
命令行指向的脚本真实存在。但**资源管理器永远不显示菜单**。

根因（本机实测）：

```
HKCR\.exe\(Default)   = exefile          <-- .exe 存在关联 ProgID
HKCR\exefile\shell    = open / runas / runasuser / ...
HKCR\SystemFileAssociations\.exe\shell = 只有本工具的 verb
```

按 Windows 的文件类型菜单合成规则，`SystemFileAssociations\.xxx` 是**扩展名没有
关联 ProgID 时**才启用的**兜底**路径；一旦扩展名存在关联 ProgID，资源管理器就以
该 ProgID 的 `shell` 为主干，兜底路径被直接跳过。`.exe` 关联着 `exefile`，
于是 Explorer 只读 `exefile\shell`，永远不读 `SystemFileAssociations\.exe\shell`。

**这不是缓存/权限/32-64 重定向/组策略问题，而是注册位置选错了。**

#### 缺陷二（中期版本）：注册在 `exefile\shell`，只对 `.exe` 生效

修好了缺陷一，但用户只要右键的不是 `.exe` 就看不到菜单。

#### 最终方案与两个历史位置的处置

| 位置 | 处置 | 理由 |
|---|---|---|
| `*\shell\PathAdder` | **当前使用** | `*` 覆盖所有文件（含 .exe），单点注册最干净 |
| `exefile\shell\PathAdder*` | **已移除** | `*` 已覆盖 .exe；再注册会在菜单里出现两份相同动作 |
| `SystemFileAssociations\.exe\shell\PathAdder*` | **已移除** | 原本就是「.exe 无关联 ProgID」时的兜底；`*` 无条件覆盖所有文件后，这条兜底已完全失去意义 |

> **关于「是否保留 SystemFileAssociations 兜底」的判断：彻底移除。**
> 它存在的唯一理由是「万一 `.exe` 查不到关联 ProgID」。但 `*` 是**无条件**生效的
> ——它对任何文件对象都成立，根本不走 ProgID 关联解析，因此不存在「`.exe` 查不到
> ProgID 导致菜单丢失」的风险。既然 `*` 已经无条件兜住了所有情况，这条
> SystemFileAssociations 就成了纯冗余，移除它反而让注册点从 2 个降到 1 个，
> 更不容易出现菜单重复或清理遗漏。

**⚠ 卸载必须清理全部三个位置**（当前 + 两个历史），否则老用户升级后会留下孤儿菜单项。
`uninstall.ps1` 通过 `Get-PathAdderShellCleanupLocations` 遍历清理，已实测验证。

#### 为什么用户级注册是安全的

`HKCR` 是 `HKCU\Software\Classes` 与 `HKLM\Software\Classes` 的**合并视图**，
按「值」和「子键」逐项合并：同名值 HKCU 优先，同名子键两侧并存。

本工具**从不写入 HKLM**，也**从不修改** `*\shell` / `exefile\shell` 上的任何系统值，
**尤其绝不写入默认动词**（见 §5.3）。


### 5.2 子菜单实现：为什么放弃 `SubCommands`，改用「点击弹出」（2026-10-04 变更）

#### 曾经踩的坑：`SubCommands` 在 Windows 11 上悬停不展开

初版用 Windows 原生的**静态级联（`SubCommands`）**把 4 个动作收进父菜单：

```
HKCU\Software\Classes\*\shell\PathAdder
    SubCommands = "PathAdder.AddUser;PathAdder.AddSystem;PathAdder.Remove;PathAdder.Manager"
    └─ shell\PathAdder.AddUser\command = …
```

**实测结论：在 Windows 11 上失败。** 表现为：

- 父菜单项「PATH 助手」**能正常显示**；
- **鼠标悬停完全不展开**子菜单；
- 因为该机制要求父项不能带 `command` 子键，**点击也毫无反应**；
- 结果就是 4 个功能**一个都点不到**。

**根因**：Windows 11 引入了新的上下文菜单管线，传统注册表 verb 被统一包装成
`ExplorerCommand verb` 再呈现。该包装器对 `SubCommands` 的静态级联支持不完整，
因此不触发级联展开。机器上安装的第三方 `IExplorerCommand` 扩展越多，失效越明显
（本机就有 VLC、Git、美图、云盘等多个 COM 型扩展）。

> 补充一个反直觉的细节：`SubCommands` 与「父项带 `command`」**互斥**——一旦父项
> 有 `command`，Windows 就把它当普通项，`SubCommands` 被完全忽略。所以「给父项加个
> command 做兜底」是行不通的，两者只能二选一。

#### 现方案：点击父项 → 在光标处弹出原生样式菜单

```
HKCU\Software\Classes\*\shell\PathAdder
    (Default)          = "PATH 助手"
    MUIVerb            = "PATH 助手"
    Icon               = "…\powershell.exe,0"
    NoWorkingDirectory = ""
    └─ command\(Default) = powershell … -File "…\MenuPicker.ps1" -Target "%V"
```

`MenuPicker.ps1` 收到 `%V` 后：

1. 取出目标文件所在目录，作为菜单顶部**灰色不可点击**的说明行（让用户确认对象）；
2. 用 WinForms `ContextMenuStrip` 在 `[Cursor]::Position` 弹出菜单；
3. 用户点选某项后，再转交 `PathAdder.ps1` 执行真正的动作（`Add` / `Remove` / `OpenManager`）。

**取舍：** 换来「多点一次鼠标」，换来的是**不依赖 Explorer 级联实现、100% 可靠**。
在 Windows 11 前提下，这是唯一能稳定工作的方案。

如果未来要恢复真正的「悬停展开」，唯一出路是实现 `IExplorerCommand` COM 外壳扩展
（注册 `ExplorerCommandHandler`），那需要编写并注册 COM DLL，工程量和维护成本高得多。

**升级兼容：** 安装时会自动清除上一版遗留的 `SubCommands` 值与 `…\shell\` 子命令树，
因此旧版本升级无需先卸载。

#### 关于 `Position = "Bottom"`：未采用

MSDN 的示例里出现过 `Position = "Bottom"`，直觉上应该加上「沉到菜单底部」。
本项目**不加**，理由是**可发现性优先于菜单整洁度**：

1. 收拢成父菜单已经把一级菜单占用从 4 行降到 1 行，整洁度目标已达成；
2. `Bottom` 会把菜单项推到「属性」那一组附近，而本工具的用户已经吃过
   「菜单找不到」的亏，此时**降低可见性是错误方向**；
3. 默认位置在菜单中部，反而更容易被看到。

需要时在父项加一个 `Position` 值即可，不必改代码结构。

### 5.3 从不写入默认动词（`-MakeDefault` 已废弃）

> ⚠️ **本工具在任何位置都不写入默认动词。**

默认动词（父键的 `(Default)`）决定文件的**双击行为**。把它改成我们的菜单项，
后果是**用户双击任何文件都不再是打开，而是弹窗改 PATH**——破坏性极强，
且几乎不可能是用户本意。

- `-MakeDefault` 开关**保留**（向后兼容），但已**完全失效**，只会打印一条说明；
- `*\shell` 与 `exefile\shell` 的 `(Default)` **永远不被本工具写入或清除**；
- `verify-registration.ps1` 有专门的**默认动词安全性检查**：一旦发现默认值变成
  `PathAdder*`，立即判失败并提示必须修正。

### 5.4 菜单传参使用 `%V` 而不是 `%1`

```text
powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "...\PathAdder.ps1" -Action Add -Scope User -Target "%V"
```

理由：

- `%V`（Verb 参数）在 Windows Vista 及以上**始终传递长文件名**，对含中文、空格的路径最稳健；
- `%1` 在部分遗留场景会被转换成 8.3 短名（如 `D:\TOOLS~1\BIN`），可能丢失中文目录名；
- 双保险：脚本内部另外用 `GetLongPathName`（P/Invoke）做一次短名还原，再用 `GetFullPath` 规范化。
- 脚本拿到的是**文件路径**，内部用 `[System.IO.Path]::GetDirectoryName()` 转成所在目录。

#### 目标参数的校验（防止把当前工作目录误加进 PATH）

`-Target` 在**添加**场景下必须通过三重校验，否则直接报错退出、PATH 一字不改：

1. **必须是真绝对路径**（`-RequireAbsolute`）：拒绝相对路径与盘符相对写法（如 `C:`），避免结果依赖脚本的 CWD；
2. Add 场景：**必须真实存在**（文件或目录），防止异常参数造成误加；
3. **垃圾输入拦截**：`'...'`、`'.'`、`'   '` 这类仅由空白/点/斜杠组成的字符串会被显式拒绝。

> 这一步是必需的：`[System.IO.Path]::GetFullPath('...')` 会默默返回**当前工作目录**，
> 若不拦截，`...` 就会被当成合法目录把 PowerShell 进程的 CWD 写进 PATH。

> 同理，盘符相对写法 `C:` 也会被 `GetFullPath` 按「C 盘上的当前目录」展开，同样依赖进程
> CWD。因此这里**不使用** `Path.IsPathRooted()`（它把 `C:` 也算作绝对路径），只承认两种
> 与 CWD 无关的写法：驱动器 + 分隔符（`C:\`、`C:/`）与 UNC（`\\server\share`）。

> **注意**：上述三条主要约束 **Add**。**Remove 刻意放行存在性**（内部 `-AllowMissing`），
> 让你可以清掉 PATH 里那些「目录早就被删了、但 PATH 还留着一项」的历史残留条目；
> Remove 依然要求真绝对路径，垃圾输入同样被拒。
>
> 库函数 `Remove-DirectoryFromPath` 也同样加了 `-RequireAbsolute`（纵深防御）：否则在一次
> 右键「移除」里，`C:` 会被按 CWD 展开，进而**静默删掉** PATH 中恰好等于该 CWD 的合法条目
> ——这属于不可接受的破坏，必须在最底层拦住。

### 5.5 UAC 自提权

- 检测：`WindowsPrincipal.IsInRole(WindowsBuiltInRole.Administrator)`；
- 提权：构造 `ProcessStartInfo`，**`Verb = 'runas'`** + `UseShellExecute = $true`，用 `powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File` 重新拉起自身，并追加 `-Elevated` 标记防止无限循环提权；
- **三个条件缺一不可**：少了 `Verb = 'runas'` 就只是"以当前用户权限再开一个 PowerShell"（UAC 不弹、子进程 `ISADMIN` 仍为 False，系统 PATH 写入必失败）；少了 `UseShellExecute = $true` 则 `Verb` 会被静默忽略；
- **失败处理**：用 `try/catch` 捕获（用户在 UAC 中点「否」会抛 `Win32Exception`），弹出友好提示「系统 PATH 未被修改」，不崩溃、不留半截状态。

### 5.6 PATH 值类型（`REG_EXPAND_SZ` / `REG_SZ`）保持

`Path` 值既可能是 `REG_EXPAND_SZ` 也可能是 `REG_SZ`。读写流程：

1. `GetValue('Path')` 取值；
2. `GetValueKind('Path')` 取类型；
3. `SetValue('Path', 新值, 原类型)` 写回。

类型信息也会记录到日志，恢复备份时优先按日志中的原类型写回。

> 实现注意：`Microsoft.Win32.RegistryValueKind` 的成员名是 **`ExpandString`** 而不是
> `ExpandSz`。在 PowerShell 5.1 中写 `[RegistryValueKind]::ExpandSz` 不会报错，而是静默返回
> `$null`，进而导致 `SetValue(name, value, kind)` 的三参数重载解析失败。本工具统一通过
> `ConvertTo-RegistryValueKind` / `ConvertTo-RegistryValueKindName` 做安全映射。

### 5.7 去重比较（避免重复添加）

归一化后再比较：

1. 去首尾空白与引号；
2. `ExpandEnvironmentVariables()` 展开其中可能出现的 `%XXX%`；
3. `/` 统一成 `\`；
4. 去尾部反斜杠（盘符根目录 `C:\` 除外）；
5. 大小写不敏感（`ToLowerInvariant()`）。

命中已存在时**直接返回** `AlreadyExists`，不写注册表、不产生备份。

### 5.8 环境变更广播

写注册表后：

- `SetEnvironmentVariable('Path', $combined)` —— **仅 Process 目标（默认重载），只更新当前进程内存，绝不回写注册表**；
- 重建当前进程的 `$env:Path`（由注册表中的 Machine + User 重新拼出）；
- P/Invoke `SendMessageTimeout(HWND_BROADCAST, WM_SETTINGCHANGE, 0, "Environment", SMTO_ABORTIFHUNG, 5000, ...)`，让资源管理器与已打开程序感知。

> ⚠️ 实现陷阱：**不要**换成带 `EnvironmentVariableTarget.User` / `.Machine` 的重载。
> 那个重载会**回写注册表**，并把 `REG_EXPAND_SZ` 悄悄降级成 `REG_SZ`，直接破坏 §5.6 的
> 「保持原有值类型」要求。本工具因此只用 Process 目标。

P/Invoke 通过 `Add-Type` 编译；若编译失败会自动降级（仅跳过广播），不影响 PATH 写入。

### 5.9 资源管理器缓存刷新

改完注册表后，资源管理器可能仍在使用**已缓存**的右键菜单。`install.ps1` /
`uninstall.ps1` 在写入注册表后调用：

```csharp
SHChangeNotify(SHCNE_ASSOCCHANGED, SHCNF_IDLIST, NULL, NULL);   // 主：关联已变更
SHChangeNotify(SHCNE_UPDATEITEM,  SHCNF_PATHW,   NULL, NULL);   // 辅：催促刷新已存在项目
```

`SHCNE_ASSOCCHANGED` 是「改了文件类型关联」的标准通知，Explorer 收到后会作废已缓存的
`IContextMenu`，下次弹出右键菜单时重新读注册表。两次通知成本极低。

> ⚠️ **实测：在 Windows 11 上这个通知并不可靠。**很多时候必须**重启 explorer 进程或
> 注销重登**才会真正生效。用户反馈的「菜单还是没出现」绝大多数就是没做这一步。
> 因此本工具把「必须重启资源管理器」作为安装后的**首要提示**，并提供询问式的自动重启
> （见 [§1.5](#15-必须重启资源管理器菜单才会出现最重要的一步)）。

**降级策略**：`Add-Type` 编译失败（受限环境缺少 C# 编译器）或调用抛异常时，
**不抛异常终止安装/卸载**，改为在提示里给出手动重启指引。

### 5.10 验证脚本（`verify-registration.ps1`）

一个**独立**的诊断工具，用于回答「注册表里写了，Explorer 到底认不认」。

只看注册表**不足以**证明菜单可用——历史上的缺陷正是「键和值全都齐全，菜单却完全不出现」。
因此脚本分多层验证：

| 层 | 内容 | 证据强度 |
|---|---|---|
| 第 1 层 | 父项 `MUIVerb`/`Icon`/`NoWorkingDirectory`，以及父项 `command` 指向 `MenuPicker.ps1` | 必要条件 |
| 第 1 层**关键断言** | 父项**必须有** `command` 子键 —— 现方案靠「点击弹出菜单」，缺了 `command` 就点了没反应 | 必要条件 |

> ⚠️ **这条断言的方向已被反转过一次**，改动前务必看 §5.2：
> `SubCommands` 时代要求「父项**绝不能**有 `command`」；现方案改为「点击弹出」后，
> 要求恰好相反——父项**必须**有 `command`。若 `verify-registration.ps1` 报
> 「父项不应有 command」，说明它还是旧版，需要更新。
| 第 1.2 层 | 历史位置（exefile / SystemFileAssociations）是否有残留 | 升级路径回归 |
| 第 1.3 层 | `*\shell` 与 `exefile\shell` 的 `(Default)` 是否被误改成 PathAdder | **灾难级回归** |
| 第 1.5 层 | HKLM 侧 `open`/`runas`/`runasuser` 是否完好 | 安全性回归 |
| 第 2 层 | **真实 COM 枚举**（`.exe` + `.txt` 各一个）：`SHCreateItemFromParsingName` → `BindToHandler(BHID_ShellMenu)` → `QueryContextMenu` → `GetCommandString(GCS_VERBKEY)` | **决定性** |
| 第 2 层降级 | 当 Shell COM 不可用时，改用合并视图 `HKCR\*\shell\PathAdder` 推演 | 较强但非决定性 |
| 第 3 层 | 第三方菜单（`HKCR\*\shell`）是否被误伤 | 安全性回归 |

> 第 2 层直接调 `GetCommandString(GCS_VERBKEY)` 取**规范动词名**（如 `PathAdder.AddUser`），
> 而不是只比对显示文本——显示文本可以被本地化或改写，动词名是 Explorer 真正用来
> 分发命令的那个键名，无法伪造。

**退出码**：`0` = 全部通过；`1` = 有失败项；`2` = 环境问题，未能完成第 2 层验证。
脚本**绝不会**在没拿到第 2 层证据时输出「全部通过」——宁可报 `2`，也不给出假阳性。

> **实现提示**：本脚本**不使用 `[ComImport]` 接口**，而是按 vtable 槽位取函数指针
> 再用委托调用。原因有二：把 COM 对象经 `out object` 取出再强转，在 `Add-Type`
> （CodeDom 编译）下会抛 `InvalidCastException`；且 `IContextMenu` 的 vtable 顺序必须
> 严格正确（`GetCommandString` 是**第 5 个**方法，中间还隔着 `TrackPopupMenuEx`、
> `GetMenuStringInfo`、`InvokeCommand`），少声明一个方法就会静默打到错误槽位。

用法：

```powershell
verify-registration.ps1                                  # 自动挑 .exe + 造一个 .txt 探测
verify-registration.ps1 -TargetExe "D:\Tools\ffmpeg.exe" # 指定被右键的文件
verify-registration.ps1 -SkipContextMenu                # 只做注册表检查，跳过 COM 枚举
```

脚本会在非 STA 线程上**自动以 `-STA` 重新拉起自身**并透传退出码，
因此直接 `powershell -File verify-registration.ps1`（默认 MTA）也能一次跑通。

### 5.11 编码

所有 `.ps1` 文件均为 **UTF-8 with BOM**。Windows PowerShell 5.1 对无 BOM 的 UTF-8 文件会按 ANSI/GBK 解析，导致中文乱码；BOM 是必需的。
`.bat` 文件保持纯 ASCII（cmd.exe 按本地代码页解析），注释使用英文。

## 6. 常见问题

**Q1：安装后右键看不到菜单？**

按**这个顺序**排查（前两条占了 95% 的情况）：

1. **先重启资源管理器** —— 这是最常见的原因，没有之一。
   Windows 11 上 `SHChangeNotify` 通知经常不生效，必须重启 explorer 才会出现：

   ```powershell
   Stop-Process -Name explorer -Force; Start-Process explorer.exe
   ```

   或者**注销当前 Windows 账户后重新登录**。

2. **Windows 11 需点「显示更多选项」**（或选中文件后按 `Shift+F10`）。
   「PATH 助手」在经典菜单里，不在第一层。
   请**先点开「显示更多选项」再下结论**，别只看第一层就说没有。

3. **确认右键的是文件**（不是文件夹空白处、不是桌面空白）。本工具注册在 `*` 上，
   只对**文件对象**生效。

4. **运行验证脚本**确认注册是否真的生效，并看它给出的具体失败项：

   ```powershell
   powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File ".\verify-registration.ps1"
   ```

5. 若验证脚本报「父项存在 command 子键」，说明级联会失效（点了没反应）——
   重新运行 `install.ps1` 即可自动修正。

6. 若报结构完整但无法枚举菜单，多半是当前环境限制（容器/远程会话），
   请在普通桌面会话确认。


**Q2：提示「需要管理员权限」？**
A：选择「添加到 PATH（当前用户）」即可免管理员。系统级 PATH 必须管理员；若 UAC 被取消，工具会明确提示且**不修改**任何内容。

**Q3：命令行里还是找不到程序？**
A：PATH 只对**新打开**的窗口生效。请关闭并重新打开 cmd / PowerShell / Windows Terminal。

**Q4：加错了目录怎么办？**
A：右键该 `.exe` → 「从 PATH 中移除此目录」；或打开「PATH 管理器 → 备份历史」选择修改前那份备份点「恢复到此次备份」。

**Q5：会破坏我已有的 PATH 吗？**
A：不会。工具只做「追加一项」或「删除匹配项」，其余条目原样保留；每次修改前都会备份；写入失败时保留备份并提示，不会留下半截状态。

**Q6：备份文件会越堆越多吗？**
A：每次操作生成一个纯文本备份（通常几 KB），可自行在「PATH 管理器 → 打开备份目录」中清理。建议保留最近几次即可。

**Q7：脚本被杀毒软件拦截？**
A：本工具不联网、不注入、不写系统目录，仅修改 PATH 环境变量与 `HKCU` 下的右键菜单。如遇拦截请加入白名单。

---

## 7. 已知限制

1. **PATH 长度**：Windows 注册表对 `Path` 值有长度上限（传统上限约 2047 字符，部分系统可放宽到 32K）。若已接近上限，写入可能失败——工具会捕获并提示，不会静默截断。
2. **必须重启资源管理器**：这是「菜单不出现」的**第一原因**（比下面第 3 条更常见）。Windows 11 上 `SHChangeNotify` 通知经常不足够，必须重启 explorer 或注销重登。见 [§1.5](#15-必须重启资源管理器菜单才会出现最重要的一步)。
3. **Windows 11 分层菜单**：菜单项位于经典菜单（「显示更多选项」/`Shift+F10`）中，这是系统行为，非工具限制。请先点开「显示更多选项」再下结论。
4. **默认动词**：出于安全考虑**在任何位置都不写入**默认动词（会导致双击文件不再打开）。`-MakeDefault` 已废弃为无操作。见 §5.3。
5. **子菜单是「点击展开」而非「悬停展开」**：这是有意为之的取舍，不是缺陷。
   Windows 原生的 `SubCommands` 悬停级联在 **Windows 11 上实测不展开**（父项可见、
   悬停无反应、且因该机制要求父项不能有 `command` 导致点击也无效），四个功能会
   全部点不到。现改为点击后在光标位置弹出菜单，可靠性 100%，代价是多一次点击。
   详见 §5.2。若要恢复真正的悬停级联，唯一出路是实现 `IExplorerCommand` COM
   外壳扩展（需编写并注册 COM DLL），工程量高得多。
6. **备份粒度**：备份只记录 `Path` 这一项的值，不备份其它环境变量。
7. **P/Invoke 广播依赖 `Add-Type`**：极简/受限环境若缺少 C# 编译器，`WM_SETTINGCHANGE` 广播与 `SHChangeNotify` 刷新都会被跳过（PATH 写入与菜单注册本身仍会正确完成，只是需要手动重启资源管理器）。
8. **系统 PATH 移除**：若当前不是管理员且 UAC 被拒绝，只会完成用户级移除并提示，不会静默跳过告知。
9. **`Start-Process` 在「环境变量键大小写重复」的机器上会抛异常**：若你的环境里同时存在 `Path`/`PATH`、`http_proxy`/`HTTP_PROXY` 这类仅大小写不同的同名环境变量键，用 `Start-Process` 拉起本工具（默认 `UseShellExecute = $false`）时，.NET 构造环境块会失败并报错。这不是本工具的问题。解决办法：改用 `Start-Process -UseShellExecute`，或直接用本工具自带的 `Start-PathAdderScript`（内部已显式设置 `UseShellExecute = $true`），亦可先清理掉重复的环境变量键。
10. **验证脚本在受限环境下无法完成第 2 层**：某些容器 / 精简系统 / 远程会话中，Shell COM 的 `SHCreateItemFromParsingName` 会对所有接口 ID 返回 `E_NOINTERFACE (0x80004002)`，此时无法真实枚举菜单。脚本会自动降级为合并视图推演并**如实标注证据强度不足**（退出码 2），不会给出假阳性结论。

---

## 8. 附：关于 `HKCR\*\shell` 的观察记录

调查过程中发现 `HKCR\*\shell` 下有 7 个第三方菜单项：

```
meituxiuxiu | meituxiuxiupcl | pintohomefile | removeproperties
UpdateEncryptionSettingsWork | YunShellExplorerCommand
```

**核实结论：该键是正常的，没有被写坏。**

- `HKCR\*` 下只有 4 个子键（`OpenWithList` / `OpenWithProgids` / `shell` / `shellex`），
  `shell` 下有 6 个具名子键，**均为正常的一次一注册**，不存在重复或嵌套异常。
- 「几十个同名 `shell` 子键」是**枚举方式的显示假象**：若对 `HKCR\*` 使用递归枚举
  （`-Recurse`）或逐层下降，每个文件类型的 `shell` 都会各打印一次 `shell`，
  于是看起来像是同一个键出现了几十次。实际键数量是 1 个。
- 这些是第三方软件（美图系 / 加密设置 / 云盘等）注册的「所有文件」右键菜单，
  与本工具无关。

**本工具的处理（已变化）**：现在本工具**本身**就注册在 `HKCR\*\shell` 下
（父项 `PathAdder`），但采用**单点注册 + 精确删除**：

- 安装只在 `*\shell` 下新增一个 `PathAdder` 子键，不改动任何既有键；
- 卸载只删 `PathAdder` 这一棵子树，**绝不碰**任何不叫 `PathAdder` 的兄弟键；
- `*\shell` 与 `exefile\shell` 的 `(Default)`（默认动词）**永远不写、永不清除**。

验证脚本第 3 层会显式列出并校验这些第三方菜单项是否完好，以防误伤。

---

## 9. 语言

PathAdder 同时具备 PowerShell 侧的 i18n 层与 C# 侧的字符串表。本节是这套机制的对外说明。

### 9.1 默认语言与已支持语言

- **默认语言是 English（`en-US`）。**
- 目前支持：**English（`en-US`）** 与 **简体中文（`zh-CN`）**。
- `en-US` 同时是**兜底底座**：任何语言缺键都会自动回落到英文（见 §9.4）。

### 9.2 三种切换方式

| # | 方式 | 说明 |
|---|---|---|
| 1 | **PATH 管理器界面右上角的语言下拉框**（推荐） | 选择后立即生效并持久化；只有这种方式会同时帮你写好配置文件与注册表 |
| 2 | 命令行：`Set-PathAdderLanguage -Language zh-CN` | 由 `lib\i18n.ps1` 提供；会归一化语言代码、重新加载语言包并持久化选择 |
| 3 | 环境变量 `PATHADDER_LANG` | 优先级最高，适合一次性运行，以及由 COM 外壳扩展拉起的子进程 |

```powershell
Set-PathAdderLanguage -Language zh-CN    # 切换到简体中文
Set-PathAdderLanguage -Language en-US    # 切回英文

$env:PATHADDER_LANG = 'zh-CN'            # 用环境变量做一次性覆盖
```

### 9.3 语言解析优先级

严格按以下顺序解析，命中即止：

1. 环境变量 **`PATHADDER_LANG`**
2. **`%LOCALAPPDATA%\PathAdder\config.json`** 的 **`language`** 字段
3. 注册表 **`HKCU\Software\PathAdder\Language`**
4. **系统 UI 语言**（`CultureInfo.CurrentUICulture`）
5. **`en-US`**（最终兜底）

> 之所以还要写注册表，是因为运行在 `explorer.exe` 里的 COM 外壳扩展既拿不到你 shell 的
> 环境变量，也拿不到脚本作用域，只能靠注册表读取当前语言。

### 9.4 语言包结构

```
lang\
├── en-US\          # 英文（美国）——兜底底座，必须保持完整
│   ├── core.ps1
│   ├── shell.ps1
│   ├── picker.ps1
│   ├── gui.ps1
│   ├── cli.ps1
│   ├── setup.ps1
│   ├── verify.ps1
│   └── com.ps1
└── zh-CN\          # 简体中文
    └── （同样的 8 个分片）
```

- 路径模式：**`lang\<language-code>\<shard>.ps1`**
- 每个文件就是一句哈希表赋值：

  ```powershell
  $PathAdderStrings = @{
      'Key'       = 'Text'
      'Other.Key' = 'Other text'
  }
  ```

- 分片按模块划分：**`core` / `shell` / `picker` / `gui` / `cli` / `setup` / `verify` / `com`**。
- 加载时先并入 `en-US`，再用所选语言覆盖其上，因此**任何语言缺键都会自动回落到英文**。
  翻译不完整也不会出现空白文案。

### 9.5 如何新增一门语言

按顺序执行以下步骤：

1. **注册语言代码**：在 `lib\i18n.ps1` 里把它加进 `$script:PathAdderSupportedLanguages`，
   并确保 `Get-PathAdderSupportedLanguages()` 会返回它。
2. **补归一化规则**：在 `ConvertTo-PathAdderLanguage()`（`lib\i18n.ps1`）里加上该语言的
   归一化规则，把松散写法 `xx` / `xx-YY` 映射到规范代码（照 `en` / `en-*` → `en-US`、
   `zh` / `zh-*` / `chinese` / `cn` → `zh-CN` 的写法照搬即可）。
3. **复制 `lang\en-US\` 为 `lang\<code>\`**，翻译全部 **8** 个分片文件
   （`core`、`shell`、`picker`、`gui`、`cli`、`setup`、`verify`、`com`）。
4. **加显示名**：在语言包里加 `App.Language.<code>`（先加 `en-US`，再加其它语言的
   `core.ps1`）。这是语言选择器下拉框里显示的名字。
5. **右键菜单的显示名是写进注册表的**：它在注册那一刻就被固化，因此切换语言后需要
   **重新运行安装/注册脚本**（`install.ps1`，COM 扩展则是 `com\register-contextmenu.ps1`）
   并重启资源管理器才会刷新。
6. **C# COM 外壳扩展的字符串内嵌在 `com\PathAdderShellExt.cs` 的 `L10n` 类里**，
   不走 `.ps1` 语言包。新增语言要在那里**加一列并重新编译 DLL**
   （参见 [com\README-COM.md](com/README-COM.md)）。

### 9.6 维护约定

- 任何新增或修改的**用户可见文案**，必须在同一次改动里**同步添加到当前支持的全部语言**，
  不允许任何一门语言掉队。
- **英文必须最先补齐**，因为它是兜底底座：只要 `en-US` 里还没有这个键，其它语言就没有
  回落目标，界面可能出现空白。
- 不允许只在某一种语言里删除或重命名键；重命名键意味着 `en-US` 与其它语言包必须一起改。
