# PathAdder 开源发布 — 增量 PRD

| 项 | 内容 |
|---|---|
| 文档类型 | 增量 PRD（仅描述本次"开源发布"变更，不重复既有功能规格） |
| 语言 | 中文（内部文档）；对 GitHub 交付物用英文 |
| 应用技术栈 | Windows PowerShell 5.1 + WinForms + C#（.NET Framework `csc.exe`）COM 外壳扩展 |
| 代码库 | `E:\幸玮代码\Buddy_Space\8_Path`，当前 42 个跟踪文件，HEAD = `9b2f633`，无 remote，分支 `master` |
| 目标远端 | GitHub `w0i0c0o/PathAdder`（已存在、公开、空仓库，默认分支 `main`） |
| 协议 | GPL-3.0 |
| 版本 | v1（PRD 定稿待主理人确认） |
| 撰写人 | 许清楚（PM） |

---

## 0. 结论先行

1. **代码零改动是可选项，不是前提。** 现有脚本全部使用 `$PSScriptRoot` / `$PSCommandPath` 推导根目录（`lib\i18n.ps1` 还实现了 4 级向上候选查找），**目录提升本身不会破坏脚本**。真正需要改的只有 3 处硬编码的相对路径假设和 1 处 `com\` 的父目录假设 → 见 §4.4 的"必须改动清单"。
2. **`.gitignore` 当前规则整体可用**（已覆盖 `*.dll`/`*.pdb`/`*.tlb`/`*.old`/`obj/`/`bin/`/`.workbuddy/`/`diag*.txt`/`_*.txt`），唯一需要新增的是 Release 归档与本地打包产物。
3. **最大风险不是代码，是"装完看不到菜单"。** 项目历史上 3 次真实的"注册成功但菜单不出现"事故全部记载在 README §1.5 / §5.1 / §5.2 / §6。README 必须把"需重启 explorer"与"Win11 需点『显示更多选项』"放在安装步骤的**紧后位置**，不能塞进 FAQ 底部。
4. **用户下载的是 zip，不是仓库。** 因此 Release 归档必须自带预编译 `PathAdderShellExt.dll`，且 README 首屏必须给出"下载 Release zip"的路径，而不是让人 `git clone`。
5. **仓库根化与 shell 扩展共存**：`com\` 目录必须原样保留为二级目录（它不是"可选的示例代码"，是主功能），根目录因此会比常见小工具项目多一个文件夹。

---

## 1. 产品目标

| # | 目标 | 可衡量结果 |
|---|---|---|
| G1 | **可分发** — 非开发者零构建成本拿到可用版本 | 从 Release 页下载 zip → 解压 → 双击 `install.bat` → 右键可见菜单，**全程无需安装 C# 编译器、无需 git** |
| G2 | **可贡献** — 任何人能在 15 分钟内跑通"改一行 → 本地验证" | 仓库根有明确的 `docs/` 上手说明；贡献者不需要在本地注册 shell 扩展也能验证 `lib\` 层改动（见 §4.5） |
| G3 | **可信赖** — 新访客 30 秒内判断"这是什么、安不安全、什么协议" | 仓库首屏（About + README 折叠线以上）同时可见：一句话定位、平台徽章、GPL-3.0、零依赖说明、"只写 HKCU 不改系统"的安全声明 |
| G4 | **可自动发布** — 发版是人做决策、机器做动作 | 推 `v*` 标签后无需人工操作，Release 自动含源码包 + 预编译 DLL，且版本号与 tag 一致 |

**非目标（本次不做）**：Windows 11 首层菜单（MSIX 打包）、代码签名、应用商店分发、PowerShell 7 支持、新增语言。

---

## 2. 用户角色与核心场景

### R1 终端用户（只想装上用）

| 维度 | 内容 |
|---|---|
| 画像 | 开发者/运维/折腾党，Windows 10 或 11，有 PATH 需求但不想手点环境变量对话框 |
| 入口 | 搜索引擎 / 别人的推荐链接 → GitHub 仓库页 |
| 期望看到 | 首屏就有"这是什么 + 下载按钮在哪"；不需要读实现细节 |
| 行动路径 | 仓库页 → Releases → 下载 `PathAdder-v1.0.0.zip` → 解压到任意目录 → 双击 `install.bat` → 按提示重启 explorer → 右键任意 `.exe` → "显示更多选项" → PATH Assistant |
| 期望停在哪 | **停在"右键能用"**。不会读 §5 实现决策，不会 `git clone`，不会装 VS |
| 失败点 | ① 以为要 clone ② 装完没重启 explorer 就判定"坏了" ③ Win11 只看第一层菜单就提 issue |

### R2 贡献者（想改代码提 PR）

| 维度 | 内容 |
|---|---|
| 画像 | 想看代码、修 bug、加语言包、加功能的开发者 |
| 入口 | 仓库页 → Code 标签 |
| 期望看到 | 清晰的目录职责、构建方式（"不需要 VS，用系统自带 csc"）、如何本地验证、PR 要求 |
| 行动路径 | clone → 读 `README.md` 的 Files 章节定位模块 → 读 `CONTRIBUTING.md` → 改 `lib\` / `lang\` → 本地跑 `verify-registration.ps1` / 跑 `com\build.ps1` → 提 PR → CI 校验通过 |
| 期望停在哪 | **停在"PR 已提、CI 绿"**。不需要理解 shell 扩展的每一个 GUID |
| 失败点 | ① 不知道自己机器上已注册的旧版本会干扰测试 ② PS1 编码（UTF-8 BOM）踩坑 ③ DLL 被 explorer 占用导致编译失败 |

### R3 维护者（你自己，要发版）

| 维度 | 内容 |
|---|---|
| 画像 | 唯一 owner，改完代码要出 Release |
| 期望看到 | 一条命令/一次推送就能发版；版本号只有一个来源 |
| 行动路径 | 改代码 → 改 `CHANGELOG.md` → 改版本号单点 → `git tag v1.0.1` → `git push --tags` → 等待 Actions 完成 → 检查 Release 资产 |
| 期望停在哪 | **停在 Release 页 URL 可直接贴出去** |
| 失败点 | ① tag 与文档版本号不一致 ② 忘记同步 `README.zh-CN.md` ③ Release 里漏了 DLL 或漏了源码 zip |

### R4（隐含）审查者/好奇者

安全敏感用户会翻 `lib\Common.ps1` 看是否偷偷改系统。README 需明确"只写 `HKCU`、不改默认动词、每次改 PATH 前备份"——这三条是信任锚点。

---

## 3. 需求池

### P0 — Must have（缺一项则本次发布不成立）

| ID | 需求 | 说明 / 验收要点 |
|---|---|---|
| P0-1 | **仓库根化** | 应用文件平移到仓库根：`PathAdder.ps1`、`PathManager.ps1`、`MenuPicker.ps1`、`install.ps1`、`uninstall.ps1`、`verify-registration.ps1`、3 个 `.bat`、`lib\`、`lang\`、`com\`、`README.md`、`README.zh-CN.md`。**`com\` 保持为二级目录**（含 `README-COM.md`）。详见 §4.1 |
| P0-2 | **路径假设同步修正** | 根化后必须改动的 4 处（见 §4.4）。不改则 `install.bat` 与 `com\*.ps1` 断链 |
| P0-3 | **README 英文正本** | 见 §3.1 章节清单。**必须含"重启 explorer"与"Win11 显示更多选项"**，且位置在安装步骤紧后 |
| P0-4 | **README 中文配套** | `README.zh-CN.md`，与英文对等（不是摘要）。顶部语言切换行 `English \| 简体中文` 双向可达 |
| P0-5 | **`LICENSE`** | GPL-3.0 **完整官方文本**（不得截断、不得改写），文件名为 `LICENSE`，无扩展名 |
| P0-6 | **`.gitignore`** | 保留现有规则并补 Release 打包产物。必须验证：`git status` 不出现 `*.dll`、`*.old`、`.workbuddy/`；且 `com\build.ps1`、`com\release-dll.ps1` **仍被跟踪** |
| P0-7 | **Release 归档 zip** | 内容与命名见 §4.2。核心要求：解压即用、含预编译 `com\PathAdderShellExt.dll`、**不含** `.git/`、`.github/`、`docs/`、`*.old`、`.workbuddy/` |
| P0-8 | **GitHub Actions** | 两个 job：① `validate`（push/PR）② `release`（`v*` tag）。见 §4.3 |
| P0-9 | **远端与分支对齐** | 添加 remote 指向 `w0i0c0o/PathAdder`；本地 `master` → 远端 `main` 的推送策略需明确（见 §6 Q3） |

### P1 — Should have（首版应尽量有，缺了不阻塞发布）

| ID | 需求 | 说明 |
|---|---|---|
| P1-1 | **版本号单点定义** | 建议新增仓库根 `VERSION` 文件（内容 `1.0.0`），作为唯一来源：Actions 校验 `GITHUB_REF_NAME` 去掉 `v` 后必须等于该文件内容；界面（PATH Manager 标题/关于）与 README 徽章从同一处取。**实现方式由架构师定**，PM 只约束"单点 + tag 一致 + 可被 Actions 校验" |
| P1-2 | **`CHANGELOG.md`** | Keep a Changelog 风格；首版含 `[1.0.0]` 段落，把现有 3 个 commit 归纳为 "Initial public release" 条目 |
| P1-3 | **Release Notes 模板** | 固定三段：Highlights / Install / Requirements。安装段必须写明"解压后先 `install.bat`，再重启 explorer" |
| P1-4 | **徽章** | README 标题下 4 枚：`Platform: Windows 10/11`、`Language: PowerShell 5.1`、`License: GPL-3.0`、`Release: vX.Y.Z`（动态徽章指向自己的 Releases） |
| P1-5 | **`CONTRIBUTING.md`** | 至少含：开发环境、如何本地跑、编码约定（UTF-8 BOM）、PR 检查清单、语言包新增流程（引用 README §9.5，不重复） |
| P1-6 | **`.gitattributes`** | 强制 `*.ps1 text eol=crlf`（PS 5.1 与 BOM 场景更稳）＋ `*.bat text eol=crlf` ＋ `*.dll binary`，避免 Windows 开发者被换行符打乱 |

### P2 — Nice to have（后续迭代）

| ID | 需求 |
|---|---|
| P2-1 | Issue 模板（`bug_report.yml` 含"是否已重启 explorer / 是否已点显示更多选项"必填项、`feature_request.yml`） |
| P2-2 | PR 模板（含自查清单：双语 README 是否同步、语言包是否 8 个分片齐全） |
| P2-3 | `CODE_OF_CONDUCT.md`（Contributor Covenant 2.1） |
| P2-4 | `SECURITY.md`（说明：只写 HKCU、不上报、漏洞私信渠道） |
| P2-5 | 仓库 Topics：`windows`、`powershell`、`path`、`context-menu`、`shell-extension`、`winforms`、`productivity` |
| P2-6 | README 顶部截图/GIF（右键菜单 + PATH Manager 窗口）。**注意**：截图需隐藏本机真实路径 |

---

### 3.1 README 英文正本 章节清单（P0-3 展开）

现有 `README.md` 已有 876 行、9 大章，内容质量高。**本次不是重写，是"为陌生人重排 + 补齐缺失章节"**。

| 顺序 | 章节 | 来源 | 动作 |
|---|---|---|---|
| 0 | 徽章 + 一句话定位 + 语言切换 | 新增 | **前置**（现在定位在 H1 下，可保留但徽章要补） |
| 1 | Quick Start（下载 Release → 解压 → install.bat → 重启 explorer → 右键） | 改写自现 §1/§1.5 | **必须提到折叠线以上** |
| 2 | ⚠️ 两个坑：必须重启 explorer / Win11 需"显示更多选项" | 现 §1.5/§3 | **保留现有分级警报块**，内容不动 |
| 3 | Menu 用法 + 4 个动作表 | 现 §"3. How to Use the Menu" | 保留；**修正标题序号错乱**（现文有 `## 1.` → `## ⚠️ 1.5` → `### 3.`，层级跳号） |
| 4 | Verify / Uninstall | 现同名节 | 保留 |
| 5 | Requirements | **缺失，需新增** | Windows 10/11 x64、Windows PowerShell 5.1、.NET Framework 4.x |
| 6 | Files / 目录结构 | 现 §3 Files | **按根化后结构重画**（去掉 `PathAdder\` 根前缀） |
| 7 | Backups and Logs | 现 §4 | 保留 |
| 8 | Language / i18n | 现 §9 | 保留 |
| 9 | COM shell extension（可选高级模式） | 现 `com\README-COM.md` | **根 README 只留指针 + 一句"绝大多数用户不需要"**，细节留在 `com\README-COM.md` |
| 10 | Troubleshooting / FAQ | 现 §6 | 保留，**删除与 §2 重复的段落**（现文"Win11 显示更多选项"警报块重复出现两次，行 90-104 与 115-126） |
| 11 | Known Limitations | 现 §7 | 保留 |
| 12 | Contributing | **缺失，需新增** | 一屏：环境、构建 DLL、验证、PR 要求 → 指向 `CONTRIBUTING.md` |
| 13 | License | **缺失，需新增** | GPL-3.0，一行 + 指向 `LICENSE` |
| 14 | Acknowledgements / 实现决策 | 现 §5/§8 | 保留但**降级为附录**，新人不需要先读 |

> **发现的问题（需架构师在实现时处理）**：现 README 标题层级断裂——`## 1. Installation` 后直接 `## ⚠️ 1.5`，然后 `### 3. How to Use`、`### Verifying`、`### Uninstalling`，再跳回 `## 2. Usage Example`、`## 3. Files`。首版对外发布前必须把目录重排为单调递增。

---

## 4. 关键交互设计

### 4.1 仓库根化后的完整目录树

```
8_Path/  ← 仓库根（GitHub: w0i0c0o/PathAdder）
│
├── PathAdder.ps1              # 核心引擎：菜单实际调用的入口
│                              #   -Action Add/Remove/Restore/OpenManager
│                              #   -Scope User/System/All  -Target <file|dir>
├── PathManager.ps1            # PATH 管理 GUI（WinForms）
├── MenuPicker.ps1             # 点击父菜单后，在光标处弹出的动作选择菜单
├── install.ps1                # 注册右键菜单（HKCU，幂等，-RestartExplorer/-NoRestart）
├── uninstall.ps1              # 卸载（清理当前位置 + 2 个历史位置，幂等）
├── verify-registration.ps1    # 独立诊断：3 层校验，exit 0/1/2
├── install.bat                # 双击入口（纯 ASCII，调用 install.ps1）
├── uninstall.bat              # 双击入口
├── verify.bat                 # 双击入口（打印 exit code 语义）
│
├── lib\                       # 共享库（脚本层）
│   ├── Common.ps1             # PATH 读写/归一化比较/备份/日志/对话框/UAC 自提权/环境广播
│   ├── ShellMenu.ps1          # 右键菜单唯一真相源：4 个动词定义 + 注册/反注册 + SHChangeNotify
│   └── i18n.ps1               # 语言解析优先级、语言包加载、持久化、Set/Get-PathAdderLanguage
│
├── lang\                      # 语言包（8 个分片 × 2 语言）
│   ├── en-US\                 #   core / shell / picker / gui / cli / setup / verify / com
│   └── zh-CN\                 #   同上（en-US 为回落基准，必须完整）
│
├── com\                       # C# 外壳扩展（可选高级模式：悬停级联菜单）
│   ├── PathAdderShellExt.cs   #   共享 helper（Helper/Native）+ COM 实现
│   ├── PathAdderContextMenu.cs#   经典 IContextMenu 扩展（真正的 POPUP 子菜单）
│   ├── build.ps1              #   用系统自带 csc.exe 编译 x64 DLL → com\PathAdderShellExt.dll
│   ├── rebuild.ps1            #   一站式：解占用 → 编译 → 注册
│   ├── register-contextmenu.ps1 # 注册经典菜单扩展（*\shellex\ContextMenuHandlers）
│   ├── register-com.ps1       #   注册 IExplorerCommand 形态
│   ├── restore-menu.ps1       #   回滚到"点击弹出"模式
│   ├── release-dll.ps1        #   编译/注册前解除 explorer 对 DLL 的占用
│   ├── diag-cascade.ps1       #   级联菜单诊断
│   ├── README-COM.md          #   COM 扩展专题文档（英文）
│   └── README-COM.zh-CN.md    #   同上（中文）
│                              #   ⚠ PathAdderShellExt.dll 等编译产物不入库
│
├── docs\                      # 内部/维护文档（不进 Release zip）
│   └── prd-open-source-release.md
│
├── .github\
│   └── workflows\
│       └── release.yml        # validate（push/PR）+ release（v* tag）
│
├── .gitattributes             # 换行符/BOM 稳定策略（P1）
├── .gitignore                 # 编译产物 / 临时诊断 / 工作区数据
├── CHANGELOG.md               # 版本变更记录（P1）
├── CONTRIBUTING.md            # 贡献指引（P1）
├── LICENSE                    # GPL-3.0 完整文本
├── README.md                  # 英文正本（对外主文档）
├── README.zh-CN.md            # 简体中文配套
└── VERSION                    # 版本号单点：1.0.0（P1）
```

**关于 `src/` 分层的取舍（给架构师的说明）**：不引入 `src/`。理由：① 现有所有脚本用 `$PSScriptRoot` 自定位，平移进 `src\` 需要额外的一层 root 推导，回归风险高于收益；② `.bat` 双击入口必须在根（用户解压后要一眼看到）；③ `com\` 是唯一合理的二级目录，因为它是"可选高级模式"，与默认安装路径（`install.ps1` + `MenuPicker.ps1`）在职责上确实分层。

### 4.2 Release 归档 zip

**命名**：`PathAdder-v{MAJOR}.{MINOR}.{PATCH}.zip`（例：`PathAdder-v1.0.0.zip` → 资产名与 tag 一致，便于检索）

**zip 内结构（解压后得到一个 `PathAdder-v1.0.0\` 根目录，避免解压污染下载目录）**：

```
PathAdder-v1.0.0\
├── install.bat / install.ps1
├── uninstall.bat / uninstall.ps1
├── verify.bat / verify-registration.ps1
├── PathAdder.ps1 / PathManager.ps1 / MenuPicker.ps1
├── lib\   (3 个 .ps1)
├── lang\  (en-US + zh-CN 各 8 个分片)
├── com\   (全部 .cs / .ps1 / README-COM*.md  +  PathAdderShellExt.dll ← 预编译，关键)
├── README.md / README.zh-CN.md
├── CHANGELOG.md / LICENSE
└── VERSION
```

**明确排除**：`.git\`、`.github\`、`docs\`、`.workbuddy\`、`*.old`、`*.pdb`、`_*.txt`、`diag*.txt`、`obj\`、`bin\`。

**同时提供的第二个资产**：`PathAdderShellExt.dll`（单独文件），供已解压过旧版、只想换 DLL 的用户。此条为 P1，见 §6 Q1。

**为什么必须预编译 DLL**：`install.ps1`（默认模式）不需要 C#，但用户若想获得"悬停级联"体验要走 `com\register-contextmenu.ps1`，那条路径依赖 `com\PathAdderShellExt.dll`。且 `*.dll` 已被 `.gitignore` 排除 → **不预编译就永远拿不到**。这是 P0-7 的核心理由。

### 4.3 GitHub Actions 设计

| Job | 触发 | 步骤 | 失败即阻塞 |
|---|---|---|---|
| `validate` | `push`（任意分支）、`pull_request` | ① checkout ② `pwsh` 语法检查：批量 `[System.Management.Automation.Language.Parser]::ParseFile` 解析所有 `*.ps1`，有错退出 1 ③ 语言包完整性：`lang\en-US` 与 `lang\zh-CN` 的各 8 个分片都存在；`en-US` 的键集合是其他语言的超集 ④ `com\build.ps1` 在 `windows-latest` 上真实编译，确认 DLL 产出 ⑤（P1）tag 版本一致性校验只对 tag 生效 | 是 |
| `release` | `push` tag `v*` | ① `validate` 全部重跑 ② 编译 DLL ③ 组装 zip（见 §4.2） ④ `softprops/action-gh-release`（或 `gh release create`）上传 zip + DLL，body 用 P1-3 模板 | 是 |

**Runner**：`windows-latest`（必须 — 依赖 .NET Framework `csc.exe` 与 `%WINDIR%\Microsoft.NET\Framework64`，Linux runner 不可用）。

**权限**：`permissions: contents: write` 仅给 `release` job。

**约束（PM 只定行为，实施由架构师定）**：

- 校验 job **不注册任何 shell 扩展**（CI 机器不留副作用），只编译不注册。
- `v*` 标签格式非法（如 `v1.0`）应直接 fail，不猜测补零。
- Release 标题 = tag 名；Release 正文必须含"Install"段（P1-3），否则用户只会看到一堆 zip。

### 4.4 根化后**必须改动**的清单（PM 交付给架构师）

已核实代码，以下 4 处涉及"根目录 = 应用目录"的假设：

| # | 文件 | 现状 | 影响 | 处理要求 |
|---|---|---|---|---|
| 1 | `install.bat` / `uninstall.bat` / `verify.bat` | `-File "%~dp0install.ps1"` | **无影响** — `%~dp0` 自动跟随 `.bat` 所在目录 | 无需改动，但要实测 |
| 2 | `install.ps1` L116-117 | `Join-Path $script:ScriptRoot 'PathAdder.ps1'` | **无影响** — `ScriptRoot` = 脚本自身目录 | 无需改动 |
| 3 | `com\build.ps1` L29、`release-dll.ps1` L36、`register-*.ps1` L~40、`rebuild.ps1` L39 | `$scriptRoot = Split-Path -Parent $comDirectory` | **无影响** — 推导出的仍是仓库根 | 无需改动，但 `lang\`、`lib\` 必须真的在该父目录下（根化后成立） |
| 4 | `com\restore-menu.ps1` L96 | `$parentDir = Split-Path -Parent $PSScriptRoot` | 需人工确认语义是"应用根"还是"com 的父目录" | **架构师核对** |
| 5 | `.gitignore` | 现有规则 | 需补 Release 打包产物 | 追加（见 §3 P0-6） |
| 6 | `README.md` / `README.zh-CN.md` | 多处 `PathAdder\` 前缀的目录树与命令示例（如 `PathAdder\install.bat`） | 文档错误 | 全文替换为根目录形态 |
| 7 | `com\README-COM.md` / `.zh-CN.md` | 引用 `..\install.ps1` 等相对路径 | 需核对 | 全文核对 |
| 8 | `lib\i18n.ps1` L314-320 | root 未注册时回落到"`lib` 的父目录" | 根化后仍是仓库根 → 正确 | 无需改动，作为正向证据保留 |

> **结论**：代码层的根化风险**很低**（`$PSScriptRoot` 体系是健壮的），工作量集中在**两份 README + 两个 COM README 的路径文本修订**，以及 `docs\`、`.github\` 这类"只应存在于仓库、不应存在于 zip"的目录划分。

### 4.5 终端用户安装路径（README Quick Start 的目标形态）

```
① 打开 github.com/w0i0c0o/PathAdder → 右侧 Releases → 最新版
      ↓
② 下载 PathAdder-v1.0.0.zip → 解压到任意固定目录（例 D:\Tools\PathAdder）
   ⚠ 不要放在"下载"临时目录，注册表里记的是绝对路径，移动后菜单会失效
      ↓
③ 双击 install.bat
   - 用户级注册（HKCU），不需要管理员
   - 弹窗问"是否立即重启资源管理器"（默认"否"）
      ↓
④ 【必须】重启 explorer 或注销重登
   Stop-Process -Name explorer -Force; Start-Process explorer.exe
   ⚠ Win11 上 SHChangeNotify 通知常常无效，跳过这步 = 菜单一定不出现
      ↓
⑤ 右键任意 .exe（或任意文件）
   ⚠ Win11：必须点"显示更多选项"（或选中后 Shift+F10）
      ↓
⑥ 点 "PATH Assistant" → 在光标处弹出 4 项菜单 → 选 "Add to PATH (current user)"
      ↓
⑦ 【新开】一个 cmd / PowerShell → 输入程序名验证
   ⚠ 已打开的终端不会自动刷新 PATH
```

**四条必须写进 README 现实约束（历史踩坑）**：

| 约束 | 用户会怎么误解 | README 的写法要求 |
|---|---|---|
| 注册 shell 菜单**不需要**管理员，但**改系统级 PATH 需要**（UAC） | 以为整个工具都要管理员 | 表格里逐行标注"需要管理员"列 |
| 注册后**必须重启 explorer 或等菜单刷新** | 装完立刻看 → 没菜单 → 判定失败 | 放在安装步骤**紧后**，用 ⚠️ 独立小节，不要放 FAQ |
| Win11 菜单在**"显示更多选项"**第二层 | 只看第一层 → 判定失败 | 同上；并给出 `Shift+F10` 替代键 |
| 注册表记的是**脚本绝对路径**，移动/删除解压目录会让菜单变哑 | 随手拖到别处 | Quick Start 第 ② 步就提示 |

**卸载路径**：双击 `uninstall.bat` → 重启 explorer → 菜单消失。备份与日志保留在 `%LOCALAPPDATA%\PathAdder\`（不删，可回滚）。

### 4.6 贡献者上手路径

```
clone → 读 README.md 的 Files 章节（定位到 lib / lang / com 三层职责）
      ↓
读 CONTRIBUTING.md（编码约定：UTF-8 BOM、纯 ASCII .bat、PS 5.1 无 PS7 语法）
      ↓
改哪一层？
 ├─ 文本/翻译  → lang\<code>\<shard>.ps1（8 个分片齐全）+ lib\i18n.ps1 注册语言码
 ├─ PATH 逻辑  → lib\Common.ps1（内部函数有独立 docstring）
 ├─ 菜单定义   → lib\ShellMenu.ps1（唯一真相源，install/uninstall 共用，禁止各写一份）
 └─ 外壳扩展   → com\*.cs
      ↓
本地验证
 ├─ 轻量（改 lib/lang，无需注册）：直接运行 PathManager.ps1 看 GUI，或跑 verify-registration.ps1
 ├─ 改菜单：install.ps1 -RestartExplorer 后右键实测
 └─ 改 COM：com\release-dll.ps1（先解 explorer 占用）→ com\build.ps1 → com\register-contextmenu.ps1
      ↓
提 PR → CI validate job 通过（语法 + 语言包完整性 + DLL 编译）
```

**给贡献者的三条显式警告（写进 CONTRIBUTING，也提醒架构师）**：

1. **本机已注册的旧版本会干扰**：测试前先 `uninstall.bat`，或接受"多一份菜单项"。
2. **`.ps1` 必须 UTF-8 with BOM**：PS 5.1 会把无 BOM 的 UTF-8 当 ANSI/GBK，中文直接乱码。
3. **DLL 被 explorer 占用**：改完 DLL 必须先 `com\release-dll.ps1`，否则编译产物复制不回去。

---

## 5. 验收标准

### 5.1 仓库形态

- [ ] `git ls-files` 输出中**不存在**任何以 `PathAdder/` 开头的路径
- [ ] `git ls-files` 中**存在**：`PathAdder.ps1`、`install.ps1`、`uninstall.ps1`、`verify-registration.ps1`、`MenuPicker.ps1`、`PathManager.ps1`、`lib/Common.ps1`、`lib/ShellMenu.ps1`、`lib/i18n.ps1`、`lang/en-US/*`（8 个）、`lang/zh-CN/*`（8 个）、`com/build.ps1`、`com/PathAdderShellExt.cs`、`com/PathAdderContextMenu.cs`、`README.md`、`README.zh-CN.md`、`LICENSE`、`.gitignore`
- [ ] `git ls-files | grep -Ei '\.(dll|pdb|tlb|old)$'` 输出为空
- [ ] `test -f LICENSE && head -3 LICENSE` 显示 "GNU GENERAL PUBLIC LICENSE" / "Version 3"
- [ ] `README.md` 第 1 行是语言切换；折叠线以上（前 30 行）能读到"下载 Release"字样

### 5.2 功能不回归

- [ ] 在干净目录解压后，**双击根目录 `install.bat`** → 弹"安装完成"对话框 → 重启 explorer → 右键任意 `.exe` → "显示更多选项" → 可见 `PATH Assistant`
- [ ] `Add to PATH (current user)` → 新开 cmd → `where <程序名>` 能命中
- [ ] 双击 `verify.bat` → 输出 `Exit code: 0`
- [ ] 双击 `uninstall.bat` → 重启 explorer → 菜单消失；`%LOCALAPPDATA%\PathAdder\` 仍保留
- [ ] 根目录执行 `powershell -NoProfile -STA -File .\PathManager.ps1` → GUI 正常打开，语言跟随系统
- [ ] `com\build.ps1` 在仓库根形态下成功产出 `com\PathAdderShellExt.dll`

### 5.3 `.gitignore` 生效

- [ ] 手动在 `com\` 放一个 `test.dll` → `git status` **不**显示它
- [ ] 手动放 `x.dll.20261004-170350.old` → `git status` **不**显示
- [ ] 根目录有 `.workbuddy/` → `git status` **不**显示
- [ ] **反向检查**：`git check-ignore -v com/build.ps1 com/release-dll.ps1` → **无输出**（证明这两个名字带 `dll` 的脚本没有被误伤）

### 5.4 CI / Release

- [ ] 开一个 PR → `validate` job 绿
- [ ] 故意破坏一处 `.ps1` 语法 → PR 上 `validate` **红**
- [ ] 推 `v1.0.0` 标签 → Actions 自动创建 Release，无需人工点
- [ ] Release 资产列表含 `PathAdder-v1.0.0.zip`（P1 追加：+ `PathAdderShellExt.dll`）
- [ ] 下载该 zip 解压 → `com\PathAdderShellExt.dll` **存在且非空**（> 10 KB）
- [ ] zip 内**不含** `.git/`、`.github/`、`docs/`、`.workbuddy/`、`*.old`
- [ ] Release 正文含 "Install" 段，且第一句就写"解压后运行 install.bat，然后重启 explorer"
- [ ] `VERSION` 内容 == tag 去掉 `v` 前缀（P1）

### 5.5 信任面

- [ ] README 中出现明确表述："只写 `HKCU`，不写 `HKLM`（系统级 PATH 除外且需 UAC）"、"永不写默认动词"、"每次改 PATH 前自动备份"
- [ ] README 有 License 章节，指向 `LICENSE`

---

## 6. 待确认问题

> 以下问题**均不阻塞开工**。已在"主理人已拍板"列标注的项请勿再讨论。

| # | 问题 | PM 建议 | 状态 |
|---|---|---|---|
| Q1 | Release 是否同时提供 zip 与单独 `PathAdderShellExt.dll`？ | **两者都提供**。zip 给新用户；单 DLL 给"已解压、只想升级外壳扩展"的用户。成本几乎为零 | 待定 |
| Q2 | 最低 Windows 版本声明？ | 声明 **Windows 10 1809+ / Windows 11（x64）**。依据：`SHChangeNotify`、`IExplorerCommand`、`%WINDIR%\Microsoft.NET\Framework64\v4.0.30319\csc.exe` 均需 .NET FW 4.x。**明确不支持 Win7/8**，避免无效 issue | 待定 |
| Q3 | 本地分支 `master` 与远端默认分支 `main` 不一致，怎么处理？ | **重命名本地分支为 `main` 后推送**（`git branch -m master main`），保持单主干。不建 `master` 兼容分支 | 待定 |
| Q4 | 是否做代码签名（Authenticode）？ | **本次不做**。签名证书有成本，且脚本型工具主要靠源码可信。README 用"零依赖 + 只写 HKCU + 不上网"替代信任背书。若未来做，优先级低于 Win11 首层菜单 | 待定 |
| Q5 | 版本号单点的**实现形式**（`VERSION` 文件 / `PathAdder.ps1` 内常量 / `.github` 内变量）？ | PM 只要求"单点 + 可被 Actions 读取校验 + 界面可显示"，**具体形式由架构师定** | 待架构师 |
| Q6 | 仓库描述、About 文案是否要同步中文？ | GitHub About 只放英文（`Light right click menu path adder and manager for Windows`，已设置）；中文靠 README.zh-CN 的 `description` 与仓库 Topics | 待定 |
| Q7 | `docs/` 目录是否公开？ | **公开**（有助于展示工程质量），但**不进 Release zip**。内部 PRD 保留在 `docs/` 无妨 | 待定 |
| Q8 | 首个版本号 | **`v1.0.0`**（功能已闭环：双语 + 备份 + GUI + 验证脚本 + COM 扩展） | 待定 |
| Q9 | 是否在 README 放截图？ | P2。若放，**必须脱敏本机路径**（现 README 里出现过 `D:\Tools\ffmpeg-6.0\bin` 之类示例，属虚构路径，可保留） | 待定 |
| Q10 | 文档以英文为基座、中文配套 | — | **已由主理人拍板，不阻塞** |
| Q11 | 协议 GPL-3.0 | — | **已由主理人拍板，不阻塞** |
| Q12 | 应用代码提升到仓库根 | — | **已由主理人拍板，不阻塞** |
| Q13 | 推送到 `w0i0c0o/PathAdder` | — | **已由主理人拍板，不阻塞** |

---

## 7. 交付给架构师的三句话

1. **代码基本不用动**：所有脚本靠 `$PSScriptRoot` 自定位，根化只会让路径更短。要动的只有两份 README + 两份 COM README 里的 `PathAdder\` 文本前缀，以及 `com\restore-menu.ps1` L96 的父目录语义核对。
2. **P0 的硬骨头是 README 的重排与 Release zip 的组装**：现有 876 行英文 README 内容质量足够，问题是"给陌生人看的顺序不对 + 两个致命坑埋在 FAQ 里 + 标题层级断裂"。zip 组装的关键是"必须含预编译 DLL，因为 `.gitignore` 排除了 `*.dll`"。
3. **CI 只需要两个 job，且 validate job 绝不能注册 shell 扩展**：`windows-latest` 上只做语法解析 + 语言包完整性 + 真实编译 DLL，保持无副作用。
