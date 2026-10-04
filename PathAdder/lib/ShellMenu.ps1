# -----------------------------------------------------------------------------
# PathAdder - 右键菜单注册与 Shell 缓存刷新（lib\ShellMenu.ps1）
#
# 目标运行环境：Windows PowerShell 5.1（严禁 ?? / && / || / 三元运算符等 PS7 语法）
#
# 提供能力：
#   1. Get-PathAdderShellVerbDefinitions      —— 4 个子命令的唯一定义源
#   2. Get-PathAdderShellRegistrationLocation —— 当前注册位置（单一）
#   3. Get-PathAdderShellCleanupLocations     —— 所有需清理的位置（当前 + 历史）
#   4. Install-PathAdderShellMenu             —— 幂等写入 HKCU 下的级联菜单
#   5. Uninstall-PathAdderShellMenu           —— 精确删除本工具自己的键
#   6. Update-PathAdderShellAssociationCache  —— 通知资源管理器刷新关联缓存
#   7. Restart-PathAdderExplorer              —— 重启资源管理器（必须先询问）
#
# -----------------------------------------------------------------------------
# 【注册位置：HKCU\Software\Classes\*\shell\PathAdder】
#
#   `*` 是 Windows 官方支持的「所有文件对象」关联键，覆盖任意扩展名（含 .exe）。
#   早期版本注册在 `exefile\shell`（只影响 .exe）与 `SystemFileAssociations\.exe\shell`
#   （.exe 有关联 ProgID 时的惰性兜底），两处均已废弃：
#     · exefile  —— 需求改为「右键任何文件都能用」，`*` 已覆盖 .exe，重复注册只会
#                   造成同一动作在菜单里出现两次；
#     · SystemFileAssociations\.exe —— 原本就是 .exe 无关联 ProgID 时的兜底，既然
#                   `*` 无条件覆盖所有文件，这条兜底已完全失去意义，彻底移除。
#   单点注册最干净，也最不容易出现菜单重复。
#
#   卸载时必须同时清理这三个位置（当前 + 两个历史），否则老用户升级后会在
#   exefile\shell 与 SystemFileAssociations\.exe\shell 下留下孤儿菜单项。
#
# -----------------------------------------------------------------------------
# 【子菜单实现：点击展开，而非原生 SubCommands 悬停级联】  ← 2026-10-04 变更
#
#   早期版本使用 Windows 原生的 SubCommands 静态级联（悬停展开）：
#
#       父项\SubCommands = "PathAdder.AddUser;PathAdder.AddSystem;…"
#       父项\shell\PathAdder.AddUser\command
#
#   它在 Windows 7/10 上可用，但在 **Windows 11 上实测失败**：父菜单项能显示，
#   鼠标悬停完全不展开；又因 SubCommands 机制要求父项不能带 command，点击也毫无
#   反应 —— 功能彻底不可用。
#
#   根因：Windows 11 改用新的上下文菜单管线，传统注册表 verb 被包装成
#   "ExplorerCommand verb" 统一呈现，该包装器对 SubCommands 静态级联支持不完整；
#   机器上安装的第三方 IExplorerCommand 扩展越多，失效越明显。
#
#   因此改为现方案（可靠优先）：
#
#     HKCU\Software\Classes\*\shell\PathAdder
#         (Default)          = "PATH 助手"
#         MUIVerb            = "PATH 助手"
#         Icon               = "…powershell.exe,0"
#         NoWorkingDirectory = ""
#         └─ command\(Default) = powershell … -File "…\MenuPicker.ps1" -Target "%V"
#
#   点击后由 MenuPicker.ps1 在**光标位置**弹出原生 WinForms ContextMenuStrip，
#   外观与交互和原生右键子菜单基本一致，且不依赖 Explorer 的级联实现。
#   代价：需要「点击」而非「悬停」——这是在 Win11 前提下唯一 100% 可靠的方案。
#
#   升级兼容：安装时会清除上一版残留的 SubCommands 值与 …\shell\ 子命令树；
#   卸载按整棵子树删除 PathAdder，两个历史位置（exefile、SFA）另有清理逻辑。
#
#   未使用 Position="Bottom"：见 install.ps1 说明（可发现性优先于菜单整洁度）。
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# 0. 状态与原生方法
# -----------------------------------------------------------------------------

$script:PathAdderShellNativeReady = $false

<#
.SYNOPSIS
    初始化 P/Invoke 原生方法（SHChangeNotify），用于通知 Shell 关联缓存已变更。
.DESCRIPTION
    编译失败（受限环境缺少 C# 编译器等）时不抛异常，仅把
    $script:PathAdderShellNativeReady 置为 $false，调用方自动降级为
    「跳过刷新 + 提示用户手动重启资源管理器」，**绝不让安装因刷新失败而失败**。
#>
function Initialize-PathAdderShellNativeMethods {
    if ($script:PathAdderShellNativeReady) {
        return
    }
    $script:PathAdderShellNativeReady = $false

    if ('PathAdder.ShellNativeMethods' -as [type]) {
        $script:PathAdderShellNativeReady = $true
        return
    }

    $source = @'
using System;
using System.Runtime.InteropServices;

namespace PathAdder
{
    public static class ShellNativeMethods
    {
        // SHCNE_ASSOCCHANGED：通知所有关联（文件扩展名 / ProgID / 动词）已变更。
        // Explorer 收到后会丢弃已缓存的 IContextMenu，下次弹菜单时重新读注册表。
        public const int SHCNE_ASSOCCHANGED = unchecked((int)0x08000000);

        // SHCNF_IDLIST：dwItem1/dwItem2 传 NULL 表示「全局性的关联变更」。
        public const uint SHCNF_IDLIST = 0x0000;

        // SHCNE_UPDATEITEM：针对单个已存在项目的更新（SHCNF_PATHW 语义）。
        public const int SHCNE_UPDATEITEM = unchecked((int)0x00002000);
        public const uint SHCNF_PATHW = 0x0005;

        [DllImport("shell32.dll", SetLastError = false, CharSet = CharSet.Auto)]
        public static extern void SHChangeNotify(
            int wEventId,
            uint uFlags,
            IntPtr dwItem1,
            IntPtr dwItem2);
    }
}
'@

    try {
        Add-Type -TypeDefinition $source -ErrorAction Stop
        $script:PathAdderShellNativeReady = $true
    } catch {
        $script:PathAdderShellNativeReady = $false
    }
}

# -----------------------------------------------------------------------------
# 1. 菜单定义与注册位置
# -----------------------------------------------------------------------------

<#
.SYNOPSIS
    获取 powershell.exe 的完整路径（本模块自足版本，不依赖 Common.ps1 加载顺序）。
#>
function Get-PathAdderPowerShellPath {
    $candidate = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
        return $candidate
    }

    $cmd = Get-Command -Name 'powershell.exe' -ErrorAction SilentlyContinue
    if ($null -ne $cmd) {
        return $cmd.Source
    }

    return 'powershell.exe'
}

<#
.SYNOPSIS
    返回 4 个子命令的定义（安装、卸载、验证共用同一份定义，避免三处漂移）。
.DESCRIPTION
    Key 为 SubCommands 中使用的命名空间动词名（如 PathAdder.AddUser），
    同时也是 `…\PathAdder\shell\` 下的子键名。
#>
function Get-PathAdderShellVerbDefinitions {
    $definitions = @(
        [PSCustomObject] @{
            Key       = 'PathAdder.AddUser'
            Label     = '添加到 PATH（当前用户）'
            Arguments = '-Action Add -Scope User -Target "%V"'
        },
        [PSCustomObject] @{
            Key       = 'PathAdder.AddSystem'
            Label     = '添加到 PATH（系统全局，管理员）'
            Arguments = '-Action Add -Scope System -Target "%V"'
        },
        [PSCustomObject] @{
            Key       = 'PathAdder.Remove'
            Label     = '从 PATH 中移除此目录'
            Arguments = '-Action Remove -Scope All -Target "%V"'
        },
        [PSCustomObject] @{
            Key       = 'PathAdder.Manager'
            Label     = '打开 PATH 管理器'
            Arguments = '-Action OpenManager'
        }
    )

    return $definitions
}

<#
.SYNOPSIS
    返回 4 个子命令的动词名数组（用于 SubCommands 与卸载遍历）。
#>
function Get-PathAdderShellVerbKeys {
    $keys = @()
    foreach ($definition in (Get-PathAdderShellVerbDefinitions)) {
        $keys += $definition.Key
    }
    return $keys
}

<#
.SYNOPSIS
    返回【历史版本】使用过的扁平动词名。
.DESCRIPTION
    早期版本把 4 个菜单项直接注册成扁平 verb（PathAdderAddUser 等），挂在
    exefile\shell 与 SystemFileAssociations\.exe\shell 下。卸载时必须把它们一并
    清掉，否则老用户升级后会留下孤儿菜单项。
#>
function Get-PathAdderShellLegacyVerbKeys {
    return @('PathAdderAddUser', 'PathAdderAddSystem', 'PathAdderRemove', 'PathAdderManager')
}

<#
.SYNOPSIS
    返回级联菜单父项的名称（同时是 `*\shell` 下的子键名）。
#>
function Get-PathAdderShellParentName {
    return 'PathAdder'
}

<#
.SYNOPSIS
    返回级联菜单父项的显示文本。
.DESCRIPTION
    单独抽成函数，让 install.ps1 与 verify-registration.ps1 共用同一个字符串，
    避免验证脚本比对时因为两处字面量不一致而误判。
#>
function Get-PathAdderShellMenuParentLabel {
    return 'PATH 助手'
}

<#
.SYNOPSIS
    返回当前版本的注册位置（HKCU 下的相对子键路径）。
#>
function Get-PathAdderShellRegistrationLocation {
    return ('Software\Classes\*\shell\' + (Get-PathAdderShellParentName))
}

<#
.SYNOPSIS
    返回安装时需要写入的位置列表（当前版本只有一个）。
#>
function Get-PathAdderShellRegistrationTargets {
    $targets = @(
        [PSCustomObject] @{
            Role        = 'Current'
            SubKey      = (Get-PathAdderShellRegistrationLocation)
            Description = '所有文件类型（`*` 覆盖任意扩展名，含 .exe）'
        }
    )

    return $targets
}

<#
.SYNOPSIS
    返回卸载/清理时需要遍历的**全部**位置（当前位置 + 所有历史位置）。
.DESCRIPTION
    每一项含：
      SubKey   —— HKCU 下的相对子键路径
      Mode     —— 'Subtree' 表示整棵子树都是本工具的，可整体删除；
                  'NamedVerbs' 表示只删除 Verbs 列出的同名子键
      Verbs    —— Mode='NamedVerbs' 时要删除的动词名
      Description / IsLegacy

    为什么要带历史位置：用户机器上可能装着旧版本，其注册留在 exefile\shell 与
    SystemFileAssociations\.exe\shell 下。只清当前位置会留下孤儿菜单。
#>
function Get-PathAdderShellCleanupLocations {
    $locations = @(
        [PSCustomObject] @{
            SubKey      = (Get-PathAdderShellRegistrationLocation)
            Mode        = 'Subtree'
            Verbs       = @()
            IsLegacy    = $false
            Description = '当前版本：所有文件类型的级联菜单（整棵子树均为本工具所有）'
        },
        [PSCustomObject] @{
            SubKey      = 'Software\Classes\exefile\shell'
            Mode        = 'NamedVerbs'
            Verbs       = (Get-PathAdderShellLegacyVerbKeys)
            IsLegacy    = $true
            Description = '历史遗留：早期版本扁平注册的 4 个 verb'
        },
        [PSCustomObject] @{
            SubKey      = 'Software\Classes\SystemFileAssociations\.exe\shell'
            Mode        = 'NamedVerbs'
            Verbs       = (Get-PathAdderShellLegacyVerbKeys)
            IsLegacy    = $true
            Description = '历史遗留：早期版本的 .exe 兜底注册'
        }
    )

    return $locations
}

<#
.SYNOPSIS
    构造某个子命令的 command 完整命令行。
.DESCRIPTION
    说明：使用 %V 而非 %1。
      - %V 在 Windows Vista+ 上始终传递「长文件名」，对含中文与空格的路径最稳健；
      - %1 在部分遗留场景会被转成 8.3 短名，可能丢失中文目录名；
      - 脚本内部另有 GetLongPathName 兜底，双保险。
#>
function Get-PathAdderShellCommandLine {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PowerShellPath,

        [Parameter(Mandatory = $true)]
        [string]$EnginePath,

        [Parameter(Mandatory = $true)]
        [string]$Arguments
    )

    return '"' + $PowerShellPath + '"' +
        ' -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File' +
        ' "' + $EnginePath + '" ' + $Arguments
}

# -----------------------------------------------------------------------------
# 2. 安装
# -----------------------------------------------------------------------------

<#
.SYNOPSIS
    把级联菜单写入 HKCU（幂等）。
.DESCRIPTION
    幂等：重复调用只会覆盖同名值，不会报错；CreateSubKey 对已存在的键是「打开或创建」。
    失败时抛异常，由调用方统一弹窗。

    【关于默认动词】本函数**从不写入任何父键的 (Default)** —— 既不动
    `*\shell` 也不动 `exefile\shell` 的默认值。原因：这两个键的默认值决定了文件
    的双击行为，把它改成我们的菜单项会让用户双击文件时不再打开而是弹窗改 PATH。
    这是灾难级的破坏，任何情况下都不应发生。

.OUTPUTS
    包含 Success / ParentSubKey / SubCommands / CommandLines 的对象。
#>
function Install-PathAdderShellMenu {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$EnginePath,

        [Parameter(Mandatory = $false)]
        [string]$PowerShellPath = '',

        [Parameter(Mandatory = $false)]
        [string]$ParentLabel = 'PATH 助手'
    )

    $result = New-Object PSObject -Property @{
        Success         = $false
        EnginePath      = $EnginePath
        PowerShellPath  = $PowerShellPath
        ParentSubKey    = ''
        SubCommands     = ''
        Labels          = @()
        CommandLines    = @()
    }

    if ([string]::IsNullOrWhiteSpace($PowerShellPath)) {
        $PowerShellPath = Get-PathAdderPowerShellPath
        $result.PowerShellPath = $PowerShellPath
    }

    $iconValue = $PowerShellPath + ',0'
    $definitions = Get-PathAdderShellVerbDefinitions
    $parentSubKey = Get-PathAdderShellRegistrationLocation
    $result.ParentSubKey = $parentSubKey

    $verbKeys = @()
    foreach ($definition in $definitions) { $verbKeys += $definition.Key }
    $subCommandsValue = [string]::Join(';', $verbKeys)
    $result.SubCommands = $subCommandsValue

    $labels = @()
    $commandLines = @()

    # ---- 父项 ----
    $parentKey = $null
    try {
        $parentKey = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($parentSubKey)
    } catch {
        throw ('无法创建注册表键：HKCU\' + $parentSubKey + '（' + $_.Exception.Message + '）')
    }

    if ($null -eq $parentKey) {
        throw ('无法创建注册表键：HKCU\' + $parentSubKey)
    }

    try {
        $parentKey.SetValue('', $ParentLabel, [Microsoft.Win32.RegistryValueKind]::String)
        $parentKey.SetValue('MUIVerb', $ParentLabel, [Microsoft.Win32.RegistryValueKind]::String)
        $parentKey.SetValue('Icon', $iconValue, [Microsoft.Win32.RegistryValueKind]::ExpandString)
        # 禁止把被右键文件所在目录设成子进程工作目录（脚本完全按绝对路径工作）
        $parentKey.SetValue('NoWorkingDirectory', '', [Microsoft.Win32.RegistryValueKind]::String)

        # ⚠ 旧版本曾使用 Windows 原生 SubCommands 静态级联（悬停展开）。实测
        #   在 Windows 11 上父项可见但**悬停不展开**，且因父项不能带 command 而点击
        #   也无反应，功能完全不可用。现已改为「点击父项 → MenuPicker 在光标位置
        #   弹出操作菜单」。此处清理上一版遗留的两类数据：
        #     1) SubCommands 值
        #     2) …\PathAdder\shell\ 下的子命令键树
        try { $parentKey.DeleteValue('SubCommands', $false) } catch { }

        try {
            $legacyShell = $parentKey.OpenSubKey('shell', $false)
            if ($null -ne $legacyShell) {
                $legacyShell.Close()
                $parentKey.DeleteSubKeyTree('shell', $false)
            }
        } catch {
            # 没有或删不掉，忽略
        }
    } finally {
        $parentKey.Close()
    }

    # ---- 父项 command：点击后在光标位置弹出操作菜单 ----
    $pickerPath = Join-Path (Split-Path -Parent $EnginePath) 'MenuPicker.ps1'
    if (-not (Test-Path -LiteralPath $pickerPath -PathType Leaf)) {
        throw ('找不到菜单脚本：' + $pickerPath + '。请确认 MenuPicker.ps1 与 PathAdder.ps1 位于同一目录。')
    }

    $pickerCommandKey = $null
    try {
        $pickerCommandKey = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($parentSubKey + '\command')
    } catch {
        throw ('无法创建注册表键：HKCU\' + $parentSubKey + '\command（' + $_.Exception.Message + '）')
    }

    if ($null -eq $pickerCommandKey) {
        throw ('无法创建注册表键：HKCU\' + $parentSubKey + '\command')
    }

    $pickerCommandLine = ''
    try {
        $pickerCommandLine = Get-PathAdderShellCommandLine `
            -PowerShellPath $PowerShellPath `
            -EnginePath $pickerPath `
            -Arguments '-Target "%V"'
        $pickerCommandKey.SetValue('', $pickerCommandLine, [Microsoft.Win32.RegistryValueKind]::String)
    } finally {
        $pickerCommandKey.Close()
    }

    $labels += $ParentLabel
    $commandLines += $pickerCommandLine

    $result.Success = $true
    $result.Labels = $labels
    $result.CommandLines = $commandLines
    return $result
}

# -----------------------------------------------------------------------------
# 3. 卸载
# -----------------------------------------------------------------------------

<#
.SYNOPSIS
    若指定键既无子键也无值，则逐级向上删除（清理安装时创建的空壳）。
.DESCRIPTION
    严格「只删空键」：一旦发现任何子键或值就立刻返回，保留原样。
    因此绝不可能删掉其他程序写入的内容——即使别的程序恰好在同一个父键下注册了
    自己的菜单项，本函数也只会因「非空」而放弃。
#>
function Remove-PathAdderEmptyRegistryKey {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SubKeyPath
    )

    $removed = @()
    $current = $SubKeyPath

    while (-not [string]::IsNullOrWhiteSpace($current)) {
        $readKey = $null
        try {
            $readKey = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($current, $false)
        } catch {
            $readKey = $null
        }

        if ($null -eq $readKey) {
            break
        }

        $isEmpty = $false
        try {
            $isEmpty = (($readKey.ValueCount -eq 0) -and ($readKey.SubKeyCount -eq 0))
        } finally {
            $readKey.Close()
        }

        if (-not $isEmpty) {
            break
        }

        $separatorIndex = $current.LastIndexOf('\')
        if ($separatorIndex -lt 0) {
            break
        }
        $parentPath = $current.Substring(0, $separatorIndex)
        $leafName = $current.Substring($separatorIndex + 1)

        $parentKey = $null
        try {
            $parentKey = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($parentPath, $true)
        } catch {
            $parentKey = $null
        }

        if ($null -eq $parentKey) {
            break
        }

        try {
            $parentKey.DeleteSubKeyTree($leafName, $false)
            $removed += $current
        } catch {
            # 有子键/受保护等，放弃这一层即可
        } finally {
            $parentKey.Close()
        }

        $current = $parentPath
    }

    return $removed
}

<#
.SYNOPSIS
    精确删除本工具在所有位置（当前 + 历史）注册的全部菜单项（幂等）。
.DESCRIPTION
    安全边界（硬性约束）：
      - 整棵子树只删 `*\shell\PathAdder`（该名称专属于本工具）；
      - 历史位置只删 LegacyVerbKeys 列出的 4 个扁平同名子键；
      - 绝不动 HKLM，绝不删除任何「不叫我们名字」的兄弟键
        （例如 `*\shell` 下 meituxiuxiu / git / VLC 等第三方菜单）；
      - **从不写入或清除任何父键的 (Default)**（默认动词是文件双击行为，不能碰）；
      - 键不存在时静默跳过（重复卸载不报错）。
.OUTPUTS
    包含 Success / RemovedCount / Failed / RemovedItems / PrunedEmptyKeys /
    LocationsScanned 的对象。
#>
function Uninstall-PathAdderShellMenu {
    [CmdletBinding()]
    param()

    $result = New-Object PSObject -Property @{
        Success          = $false
        RemovedCount     = 0
        Failed           = @()
        RemovedItems     = @()
        PrunedEmptyKeys  = @()
        LocationsScanned = @()
    }

    $locations = Get-PathAdderShellCleanupLocations

    $removedCount = 0
    $failed = @()
    $removedItems = @()
    $pruned = @()
    $scanned = @()

    foreach ($location in $locations) {
        $scanned += $location.SubKey

        if ($location.Mode -eq 'Subtree') {
            # 整棵子树都是本工具的，直接删
            $parentKey = $null
            try {
                $parentKey = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($location.SubKey, $false)
            } catch {
                $parentKey = $null
            }

            if ($null -eq $parentKey) {
                continue
            }
            $parentKey.Close()

            $separatorIndex = $location.SubKey.LastIndexOf('\')
            if ($separatorIndex -lt 0) {
                continue
            }
            $containerPath = $location.SubKey.Substring(0, $separatorIndex)
            $leafName = $location.SubKey.Substring($separatorIndex + 1)

            $containerKey = $null
            try {
                $containerKey = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($containerPath, $true)
            } catch {
                $containerKey = $null
            }

            if ($null -eq $containerKey) {
                continue
            }

            try {
                $containerKey.DeleteSubKeyTree($leafName, $false)
                $removedCount = $removedCount + 1
                $removedItems += ('HKCU\' + $location.SubKey + '（整棵子树）')
            } catch {
                $failed += ($location.SubKey)
            } finally {
                $containerKey.Close()
            }

            continue
        }

        # Mode = 'NamedVerbs'：只删同名子键
        $baseKey = $null
        try {
            $baseKey = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($location.SubKey, $true)
        } catch {
            $baseKey = $null
        }

        if ($null -eq $baseKey) {
            continue
        }

        try {
            foreach ($verbKey in $location.Verbs) {
                $existing = $null
                try {
                    $existing = $baseKey.OpenSubKey($verbKey, $false)
                } catch {
                    $existing = $null
                }

                if ($null -eq $existing) {
                    continue
                }
                $existing.Close()

                try {
                    $baseKey.DeleteSubKeyTree($verbKey, $false)
                    $removedCount = $removedCount + 1
                    $removedItems += ('HKCU\' + $location.SubKey + '\' + $verbKey)
                } catch {
                    $failed += ($location.SubKey + '\' + $verbKey)
                }
            }
        } finally {
            $baseKey.Close()
        }

        # 自底向上回收安装时创建的空父键（只删空键）
        $pruned += Remove-PathAdderEmptyRegistryKey -SubKeyPath $location.SubKey
    }

    $result.Success = ($failed.Count -eq 0)
    $result.RemovedCount = $removedCount
    $result.Failed = $failed
    $result.RemovedItems = $removedItems
    $result.PrunedEmptyKeys = $pruned
    $result.LocationsScanned = $scanned
    return $result
}

# -----------------------------------------------------------------------------
# 4. Shell 缓存刷新与资源管理器重启
# -----------------------------------------------------------------------------

<#
.SYNOPSIS
    通知资源管理器「文件关联 / 动词已变更」，使其丢弃缓存的右键菜单。
.DESCRIPTION
    首选 SHChangeNotify(SHCNE_ASSOCCHANGED, SHCNF_IDLIST, NULL, NULL)，
    随后补一次 SHCNE_UPDATEITEM 催促刷新（不同 Windows 版本对前者响应略有差异）。

    ⚠ 实测结论：在 Windows 11 上这个通知**并不可靠**，很多时候必须重启
    explorer 进程或注销重登才会真正生效。因此调用方在拿到本结果后，
    仍应引导用户完成重启（见 Restart-PathAdderExplorer 与 install.ps1）。

    降级策略：Add-Type 编译失败或调用抛异常时返回 Refreshed = $false 与手动指引，
    **绝不抛异常终止安装/卸载**。
#>
function Update-PathAdderShellAssociationCache {
    [CmdletBinding()]
    param()

    $result = New-Object PSObject -Property @{
        Refreshed = $false
        Message   = ''
    }

    Initialize-PathAdderShellNativeMethods
    if (-not $script:PathAdderShellNativeReady) {
        $result.Message = '未能加载 shell32 互操作程序集，已跳过资源管理器刷新。' +
            '请手动重启资源管理器或注销后重新登录。'
        return $result
    }

    try {
        [void][PathAdder.ShellNativeMethods]::SHChangeNotify(
            [int][PathAdder.ShellNativeMethods]::SHCNE_ASSOCCHANGED,
            [uint32][PathAdder.ShellNativeMethods]::SHCNF_IDLIST,
            [IntPtr]::Zero,
            [IntPtr]::Zero)

        [void][PathAdder.ShellNativeMethods]::SHChangeNotify(
            [int][PathAdder.ShellNativeMethods]::SHCNE_UPDATEITEM,
            [uint32][PathAdder.ShellNativeMethods]::SHCNF_PATHW,
            [IntPtr]::Zero,
            [IntPtr]::Zero)

        $result.Refreshed = $true
        $result.Message = '已通知资源管理器刷新文件关联（SHCNE_ASSOCCHANGED + SHCNE_UPDATEITEM）。'
    } catch {
        $result.Refreshed = $false
        $result.Message = '通知资源管理器刷新失败（不影响菜单注册结果）：' +
            $_.Exception.Message +
            '请手动重启资源管理器或注销后重新登录。'
    }

    return $result
}

<#
.SYNOPSIS
    弹出 Yes/No 确认框；无图形界面时安全降级为「否」。
.DESCRIPTION
    默认按钮设为「否」（Button2），避免用户直接回车时误触发破坏性操作。
.OUTPUTS
    $true = 用户选择「是」；$false = 选择「否」或无图形界面。
#>
function Show-PathAdderConfirmBox {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [string]$Title = 'PATH 助手'
    )

    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
    } catch {
        Write-Host ('[PATH 助手] ' + $Message)
        Write-Host '[PATH 助手] 当前环境无图形界面，已按「否」处理（不会重启资源管理器）。'
        return $false
    }

    try {
        $answer = [System.Windows.Forms.MessageBox]::Show(
            $Message,
            $Title,
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Question,
            [System.Windows.Forms.MessageBoxDefaultButton]::Button2)

        if ($answer -eq [System.Windows.Forms.DialogResult]::Yes) {
            return $true
        }
        return $false
    } catch {
        Write-Host ('[PATH 助手] ' + $Message)
        Write-Host '[PATH 助手] 无法显示确认框，已按「否」处理（不会重启资源管理器）。'
        return $false
    }
}

<#
.SYNOPSIS
    重启资源管理器进程（会关闭所有已打开的文件夹窗口，调用前必须先询问用户）。
.DESCRIPTION
    流程：Stop-Process -Name explorer -Force -> 等待 2 秒 -> Start-Process explorer.exe。
    只捕获异常，不向上抛出——重启失败不影响安装结果，改为提示手动重启。
.OUTPUTS
    包含 Success / Message / ProcessCount 的对象。
#>
function Restart-PathAdderExplorer {
    [CmdletBinding()]
    param()

    $result = New-Object PSObject -Property @{
        Success      = $false
        Message      = ''
        ProcessCount = 0
    }

    try {
        $processes = @(Get-Process -Name 'explorer' -ErrorAction SilentlyContinue)
        $result.ProcessCount = $processes.Count

        Stop-Process -Name 'explorer' -Force -ErrorAction Stop
        Start-Sleep -Seconds 2
        Start-Process -FilePath 'explorer.exe' -ErrorAction Stop

        $result.Success = $true
        $result.Message = '资源管理器已重启（原 ' + $processes.Count + ' 个 explorer 进程）。'
    } catch {
        $result.Success = $false
        $result.Message = '重启资源管理器失败（菜单注册不受影响）：' + $_.Exception.Message +
            "`r`n" + '请手动执行：Stop-Process -Name explorer -Force; Start-Process explorer.exe'
    }

    return $result
}
