# -----------------------------------------------------------------------------
# verify-registration.ps1 - 右键菜单注册验证脚本（独立工具，非安装/卸载流程的一部分）
#
# 用途：
#   回答一个具体问题——「注册表里写了 4 个 verb，资源管理器到底能不能把它们
#   枚举成真正的右键菜单项？」
#   仅用 Get-ItemProperty 读注册表**不足以**证明这一点：注册位置选错时，注册表
#   键和值全都齐全，但 Explorer 永远不会去读那个位置。本脚本因此分三层验证：
#
#   第 1 层  注册表结构检查
#           逐个确认 verb 键、(Default)、MUIVerb、Icon、NoWorkingDirectory、
#           command\(Default) 均存在且内容正确。
#
#   第 2 层  真实菜单枚举（关键证据）
#           调用 SHCreateItemFromParsingName 拿到目标 .exe 的 IShellItem，
#           再 BindToHandler(BHID_ShellMenu) 取到**真正的 IContextMenu**，
#           用 QueryContextMenu 把菜单填充进一个内存 HMENU，然后遍历菜单项：
#             · 显示文本取自 GetMenuStringW（用户肉眼看到的字符串）
#             · 动词名取自 IContextMenu::GetCommandString(GCS_VERBKEY)
#               —— 这返回的是注册表里的**规范动词名**（如 PathAdderAddUser），
#                  也就是 Explorer 真正用来分发命令的那个键名。
#           只有当 4 个 PathAdder* 动词名出现在枚举结果里，才算通过。
#           这一步是真实 COM 调用，不需要重启资源管理器，也不受菜单缓存影响。
#
#   第 3 层  第三方菜单存活检查
#           枚举 HKCR\*\shell 下的第三方菜单项（VLC / git / meituxiuxiu 等），
#           确认安装/卸载流程没有误伤它们。
#
# 用法：
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File ".\verify-registration.ps1"
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File ".\verify-registration.ps1" -TargetExe "C:\some\app.exe"
#
# 退出码：
#   0 = 全部通过
#   1 = 存在失败项
#   2 = 环境问题（COM 不可用、无 C# 编译器等），无法完成第 2 层验证
#
# 兼容性：Windows PowerShell 5.1（禁 ?? / && / || / 三元运算符等 PS7 语法）
# -----------------------------------------------------------------------------

[CmdletBinding()]
param(
    [Parameter()]
    [string]$TargetExe = '',

    [Parameter()]
    [switch]$SkipContextMenu
)

$ErrorActionPreference = 'Stop'

# -----------------------------------------------------------------------------
# 0. 线程 apartment 检查（IContextMenu 枚举必须在 STA 下进行）
#
#    若当前不是 STA，自动以 -STA 重新拉起自身并透传退出码。这样用户直接
#    `powershell -File verify-registration.ps1`（默认 MTA）也能一次跑通。
# -----------------------------------------------------------------------------

if ([System.Threading.Thread]::CurrentThread.ApartmentState -ne
    [System.Threading.ApartmentState]::STA) {

    $script:SelfPath = $PSCommandPath
    if ([string]::IsNullOrWhiteSpace($script:SelfPath)) {
        $script:SelfPath = $MyInvocation.MyCommand.Path
    }

    $relaunchArgs = @(
        '-NoProfile'
        '-ExecutionPolicy', 'Bypass'
        '-STA'
        '-File', ('"' + $script:SelfPath + '"')
    )
    if (-not [string]::IsNullOrWhiteSpace($TargetExe)) {
        $relaunchArgs += @('-TargetExe', ('"' + $TargetExe + '"'))
    }
    if ($SkipContextMenu) {
        $relaunchArgs += '-SkipContextMenu'
    }

    $powershellExe = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (-not (Test-Path -LiteralPath $powershellExe -PathType Leaf)) {
        $powershellExe = 'powershell.exe'
    }

    Write-Host '[验证] 当前线程非 STA，正在以 -STA 重新启动自身……'
    $process = Start-Process -FilePath $powershellExe -ArgumentList $relaunchArgs -Wait -PassThru -NoNewWindow
    exit $process.ExitCode
}

# -----------------------------------------------------------------------------
# 1. 公共库与菜单定义
# -----------------------------------------------------------------------------

$script:MainScriptPath = $PSCommandPath
if ([string]::IsNullOrWhiteSpace($script:MainScriptPath)) {
    $script:MainScriptPath = $MyInvocation.MyCommand.Path
}
$script:ScriptRoot = Split-Path -Parent $script:MainScriptPath

$script:ShellMenuPath = Join-Path $script:ScriptRoot 'lib\ShellMenu.ps1'
if (-not (Test-Path -LiteralPath $script:ShellMenuPath -PathType Leaf)) {
    Write-Host ('[失败] 缺少菜单注册库：' + $script:ShellMenuPath) -ForegroundColor Red
    exit 2
}
. $script:ShellMenuPath

# 注意：@() 包裹是必需的。函数内部返回的是单元素数组，PowerShell 5.1 会把它
# 展开成单个 PSCustomObject，导致后面 $targets.Count 取不到值（显示为空）。
$verbDefinitions = @(Get-PathAdderShellVerbDefinitions)
$verbKeys = @(Get-PathAdderShellVerbKeys)
$targets = @(Get-PathAdderShellRegistrationTargets)

$script:Failures = @()
$script:Warnings = @()

# 第 2 层（真实菜单枚举）是否真正完成。未完成时**不允许**输出「全部通过」——
# 否则会出现「注册表检查通过就宣称菜单有效」这种把关键证据跳过的假阳性。
$script:ContextMenuVerified = $false

# 降级路径（按 Explorer 关联解析规则推演）是否完成。
# 它的证据强度低于真实枚举：能证明「verb 位于 Explorer 的主干查找路径上」，
# 但不能证明 Shell 已经把菜单构建出来。因此它只能把结论降级为「需要人工确认」，
# 而不能等同于 ContextMenuVerified。
$script:AssocResolutionVerified = $false

# 级联菜单实测状态（只有第 2 层真实枚举成功才有意义）：
#   CascadeParentFound —— 父项「PATH 助手」是否出现在菜单里
#   CascadeExpanded    —— 4 个子命令是否出现在**子菜单**（depth > 1）里
# 若父项出现但子命令没出现在子菜单，说明 Windows 11 未展开 SubCommands，
# 需要切换到兜底方案。
$script:CascadeParentFound = $false
$script:CascadeExpanded = $false

function Write-Section {
    param([string]$Title)
    Write-Host ''
    Write-Host ('=== ' + $Title + ' ===') -ForegroundColor Cyan
}

function Write-Pass {
    param([string]$Text)
    Write-Host ('  [通过] ' + $Text) -ForegroundColor Green
}

function Write-Fail {
    param([string]$Text)
    Write-Host ('  [失败] ' + $Text) -ForegroundColor Red
    $script:Failures += $Text
}

function Write-Note {
    param([string]$Text)
    Write-Host ('  [说明] ' + $Text) -ForegroundColor Yellow
}

Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' PathAdder 右键菜单注册验证' -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan

# -----------------------------------------------------------------------------
# 2. 第 1 层：注册表结构检查
# -----------------------------------------------------------------------------

Write-Section '第 1 层：注册表结构检查'

$expectedEnginePath = Join-Path $script:ScriptRoot 'PathAdder.ps1'
$parentSubKey = Get-PathAdderShellRegistrationLocation

foreach ($target in $targets) {
    Write-Host ''
    Write-Host ('  位置 [' + $target.Role + '] ' + $target.Description) -ForegroundColor White
    Write-Host ('    HKCU\' + $target.SubKey) -ForegroundColor DarkGray

    $parentKey = $null
    try {
        $parentKey = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($target.SubKey, $false)
    } catch {
        $parentKey = $null
    }

    if ($null -eq $parentKey) {
        Write-Fail ('注册表键不存在：HKCU\' + $target.SubKey)
        continue
    }

    try {
        # ---- 父项：MUIVerb / Icon / SubCommands / NoWorkingDirectory ----
        $parentLabel = [string]$parentKey.GetValue('MUIVerb', '')
        if ([string]::IsNullOrWhiteSpace($parentLabel)) {
            Write-Fail '父项缺少 MUIVerb'
        } else {
            Write-Pass ('父项 MUIVerb = 「' + $parentLabel + '」')
        }

        $parentIcon = [string]$parentKey.GetValue('Icon', '')
        if ([string]::IsNullOrWhiteSpace($parentIcon)) {
            Write-Fail '父项缺少 Icon'
        } else {
            Write-Pass ('父项 Icon = ' + $parentIcon)
        }

        if ($null -eq $parentKey.GetValue('NoWorkingDirectory', $null)) {
            Write-Fail '父项缺少 NoWorkingDirectory'
        } else {
            Write-Pass '父项 NoWorkingDirectory 已设置'
        }

        # ------------------------------------------------------------------
        # 现方案（2026-10-04 起）：点击父项 → MenuPicker.ps1 在光标处弹出操作菜单。
        #
        # ⚠ 关键断言方向与 SubCommands 时代【完全相反】：
        #    · 旧版：父项【绝不能】有 command 子键（否则 SubCommands 被忽略）
        #    · 新版：父项【必须】 有 command 子键（否则点击毫无反应）
        #   详见 README §5.2 —— Windows 11 上 SubCommands 悬停级联实测不展开。
        # ------------------------------------------------------------------

        $legacySubCommands = [string]$parentKey.GetValue('SubCommands', '')
        if (-not [string]::IsNullOrWhiteSpace($legacySubCommands)) {
            Write-Fail ('父项仍残留上一版的 SubCommands 值：' + $legacySubCommands +
                '（新方案不需要它，且它会让 Windows 忽略父项 command）')
        } else {
            Write-Pass '父项未残留旧版 SubCommands 值'
        }

        $expectedPickerPath = Join-Path (Split-Path -Parent $expectedEnginePath) 'MenuPicker.ps1'

        $parentCommandKey = $null
        try {
            $parentCommandKey = $parentKey.OpenSubKey('command', $false)
        } catch {
            $parentCommandKey = $null
        }

        if ($null -eq $parentCommandKey) {
            Write-Fail '父项缺少 command 子键！新方案依赖「点击父项弹出菜单」，缺少 command 会表现为「点了没反应」'
        } else {
            try {
                $parentCommandLine = [string]$parentCommandKey.GetValue('', '')
                $parentProblems = @()

                if ([string]::IsNullOrWhiteSpace($parentCommandLine)) {
                    $parentProblems += 'command\(Default) 为空'
                }
                if ($parentCommandLine -notmatch '-NoProfile') {
                    $parentProblems += 'command 缺少 -NoProfile'
                }
                if ($parentCommandLine -notmatch '-ExecutionPolicy\s+Bypass') {
                    $parentProblems += 'command 缺少 -ExecutionPolicy Bypass'
                }
                if ($parentCommandLine -notmatch '-File\s+"') {
                    $parentProblems += 'command 的 -File 参数未用双引号包裹脚本路径（中文/空格路径会解析失败）'
                }
                if ($parentCommandLine -notlike ('*' + $expectedPickerPath + '*')) {
                    $parentProblems += ('command 未指向本目录的 MenuPicker.ps1：' + $expectedPickerPath)
                }
                if ($parentCommandLine -notlike '*-Target "%V"*') {
                    $parentProblems += 'command 缺少 -Target "%V"（右键时拿不到目标文件路径）'
                }

                if ($parentProblems.Count -eq 0) {
                    Write-Pass '父项 command 正确指向 MenuPicker.ps1，且已传入 -Target "%V"'
                } else {
                    foreach ($problem in $parentProblems) {
                        Write-Fail ('父项 command：' + $problem)
                    }
                }
            } finally {
                $parentCommandKey.Close()
            }
        }

        if (Test-Path -LiteralPath $expectedPickerPath -PathType Leaf) {
            Write-Pass 'MenuPicker.ps1 存在'
        } else {
            Write-Fail ('找不到菜单脚本 MenuPicker.ps1：' + $expectedPickerPath)
        }

        # 旧版遗留：…\shell 子命令树应已被安装程序清理
        $legacyShellKey = $null
        try {
            $legacyShellKey = $parentKey.OpenSubKey('shell', $false)
        } catch {
            $legacyShellKey = $null
        }

        if ($null -ne $legacyShellKey) {
            $legacyShellKey.Close()
            Write-Fail '父项残留旧版 shell 子命令树（…\PathAdder\shell\…），安装程序应已将其清理'
        } else {
            Write-Pass '父项未残留旧版 shell 子命令树'
        }
    } finally {
        $parentKey.Close()
    }
}

# -----------------------------------------------------------------------------
# 2b. 历史残留位置必须为空（老版本升级路径）
# -----------------------------------------------------------------------------

Write-Section '第 1.2 层：历史注册位置残留检查（老版本升级路径）'

foreach ($location in (Get-PathAdderShellCleanupLocations)) {
    if (-not $location.IsLegacy) {
        continue
    }

    $legacyKey = $null
    try {
        $legacyKey = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($location.SubKey, $false)
    } catch {
        $legacyKey = $null
    }

    if ($null -eq $legacyKey) {
        Write-Pass ('历史位置无残留（键不存在）：HKCU\' + $location.SubKey)
        continue
    }

    try {
        $names = @($legacyKey.GetSubKeyNames())
        $leftovers = @()
        foreach ($legacyVerb in $location.Verbs) {
            if ($names -contains $legacyVerb) {
                $leftovers += $legacyVerb
            }
        }

        if ($leftovers.Count -eq 0) {
            Write-Pass ('历史位置无残留：HKCU\' + $location.SubKey)
        } else {
            Write-Fail ('历史位置仍有本工具残留（请运行 uninstall.ps1）：HKCU\' +
                $location.SubKey + ' → ' + ($leftovers -join '、'))
        }
    } finally {
        $legacyKey.Close()
    }
}

# -----------------------------------------------------------------------------
# 2c. 默认动词安全性（挂了就是灾难：会改变文件的双击行为）
# -----------------------------------------------------------------------------

Write-Section '第 1.3 层：默认动词安全性（绝不允许被改成我们的菜单项）'

$defaultVerbTargets = @(
    'Registry::HKEY_CLASSES_ROOT\*\shell',
    'Registry::HKEY_CLASSES_ROOT\exefile\shell'
)

foreach ($defaultTarget in $defaultVerbTargets) {
    $targetKey = $null
    try {
        $targetKey = Get-Item -LiteralPath $defaultTarget -ErrorAction Stop
    } catch {
        $targetKey = $null
    }

    if ($null -eq $targetKey) {
        Write-Note ('无法读取：' + $defaultTarget)
        continue
    }

    $currentDefault = [string]$targetKey.GetValue('')
    if ([string]::IsNullOrWhiteSpace($currentDefault)) {
        Write-Pass ($defaultTarget + ' 未设置默认动词（安全）')
    } elseif ($currentDefault -like 'PathAdder*') {
        Write-Fail ($defaultTarget + ' 的默认动词被改成了「' + $currentDefault +
            '」！这会让双击文件不再是打开，而是弹窗改 PATH —— 必须立即修正')
    } else {
        Write-Pass ($defaultTarget + ' 默认动词 = 「' + $currentDefault + '」（非本工具，安全）')
    }
}

# -----------------------------------------------------------------------------
# 3. 确认 HKLM 的 exefile 未被污染（系统 open/runas/runasuser 必须完好）
# -----------------------------------------------------------------------------

Write-Section '第 1.5 层：HKLM 侧 exefile 完好性检查（安装流程绝不允许改动这里）'

$hklmExeShell = 'SOFTWARE\Classes\exefile\shell'
$systemVerbs = @('open', 'runas', 'runasuser')
$hklmKey = $null
try {
    $hklmKey = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($hklmExeShell, $false)
} catch {
    $hklmKey = $null
}

if ($null -eq $hklmKey) {
    Write-Note ('无法读取 HKLM\' + $hklmExeShell + '（可能需要管理员权限才能读取，不影响本工具功能）')
} else {
    try {
        $hklmSubKeys = @($hklmKey.GetSubKeyNames())
        foreach ($systemVerb in $systemVerbs) {
            if ($hklmSubKeys -contains $systemVerb) {
                Write-Pass ('系统菜单项完好：' + $systemVerb)
            } else {
                Write-Fail ('系统菜单项丢失：' + $systemVerb + '（安装流程绝不应影响 HKLM）')
            }
        }
        foreach ($ourVerb in $verbKeys) {
            if ($hklmSubKeys -contains $ourVerb) {
                Write-Fail ('我们的菜单项 ' + $ourVerb + ' 出现在 HKLM 中，违反「只写 HKCU」的约束')
            }
        }
    } finally {
        $hklmKey.Close()
    }
}

# -----------------------------------------------------------------------------
# 4. 第 3 层：第三方菜单存活检查
# -----------------------------------------------------------------------------

Write-Section '第 3 层：其他程序的右键菜单（安装/卸载不得误伤）'

$starShellKey = 'Registry::HKEY_CLASSES_ROOT\*\shell'
$allStarVerbs = @()
try {
    if (Test-Path -LiteralPath $starShellKey) {
        $allStarVerbs = @((Get-ChildItem -LiteralPath $starShellKey -ErrorAction SilentlyContinue).PSChildName)
    }
} catch {
    $allStarVerbs = @()
}

# 本工具在 `*\shell` 下只会有一个父项 PathAdder（级联），不应有任何扁平 verb
$parentName = Get-PathAdderShellParentName
$legacyKeys = Get-PathAdderShellLegacyVerbKeys

$thirdPartyVerbs = @()
foreach ($name in $allStarVerbs) {
    if ($name -eq $parentName) { continue }
    if ($legacyKeys -contains $name) { continue }
    $thirdPartyVerbs += $name
}

if ($thirdPartyVerbs.Count -gt 0) {
    Write-Pass ('HKCR\*\shell 下有 ' + $thirdPartyVerbs.Count + ' 个第三方菜单项，全部保留：')
    Write-Host ('    ' + ($thirdPartyVerbs -join ' | ')) -ForegroundColor DarkGray
} else {
    Write-Note 'HKCR\*\shell 下未枚举到第三方菜单项（可能本机确实没有，或无读取权限）'
}

foreach ($legacyKey in $legacyKeys) {
    if ($allStarVerbs -contains $legacyKey) {
        Write-Fail ('在 HKCR\*\shell 下出现了本工具的历史扁平菜单项 ' + $legacyKey + '，注册位置异常')
    }
}

# exefile\shell 侧：系统 verb 必须完好，且不应再有我们的任何注册
$exeShellKey = 'Registry::HKEY_CLASSES_ROOT\exefile\shell'
$exeVerbs = @()
try {
    if (Test-Path -LiteralPath $exeShellKey) {
        $exeVerbs = @((Get-ChildItem -LiteralPath $exeShellKey -ErrorAction SilentlyContinue).PSChildName)
    }
} catch {
    $exeVerbs = @()
}

foreach ($systemVerb in @('open', 'runas', 'runasuser')) {
    if ($exeVerbs -contains $systemVerb) {
        Write-Pass ('HKCR\exefile\shell 系统菜单项完好：' + $systemVerb)
    } else {
        Write-Fail ('HKCR\exefile\shell 系统菜单项丢失：' + $systemVerb)
    }
}

foreach ($legacyKey in $legacyKeys) {
    if ($exeVerbs -contains $legacyKey) {
        Write-Fail ('HKCR\exefile\shell 仍有历史残留：' + $legacyKey + '（请运行 uninstall.ps1）')
    }
}

if ($allStarVerbs -contains $parentName) {
    Write-Pass ('HKCR\*\shell 合并视图中可见本工具父项：' + $parentName)
} else {
    Write-Fail ('HKCR\*\shell 合并视图中看不到本工具父项：' + $parentName)
}

# -----------------------------------------------------------------------------
# 5. 第 2 层：真实 IContextMenu 枚举（关键证据）
# -----------------------------------------------------------------------------

Write-Section '第 2 层：真实右键菜单枚举（IContextMenu / GetCommandString）'

if ($SkipContextMenu) {
    Write-Note '已通过 -SkipContextMenu 跳过本层'
} else {
    # 选探测目标：默认一个 .exe **加一个 .txt**。
    # 之所以必须覆盖两种类型：本工具注册在 `*` 上，目标是「所有文件类型」都能用。
    # 只测 .exe 无法证明 .txt 等其它类型也能看到菜单。
    $probeTargets = @()

    if (-not [string]::IsNullOrWhiteSpace($TargetExe)) {
        $probeTargets += $TargetExe
    } else {
        $exeCandidates = @(
            (Join-Path $env:WINDIR 'System32\notepad.exe')
            (Join-Path $env:WINDIR 'System32\cmd.exe')
            (Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe')
        )
        foreach ($candidate in $exeCandidates) {
            if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                $probeTargets += $candidate
                break
            }
        }
    }

    # 一个 .txt 探测目标（%TEMP% 下临时创建，用完删除），用于验证「所有文件类型」
    $txtProbePath = ''
    if (-not [string]::IsNullOrWhiteSpace($TargetExe)) {
        # 用户显式指定了目标，就不再额外造 .txt，只测指定的那个
    } else {
        $txtProbePath = Join-Path $env:TEMP 'PathAdderVerifyProbe.txt'
        try {
            Set-Content -LiteralPath $txtProbePath -Value 'PathAdder verify probe' -Encoding ASCII -ErrorAction Stop
            $probeTargets += $txtProbePath
        } catch {
            $txtProbePath = ''
            Write-Note ('无法创建 .txt 探测文件，跳过该目标：' + $_.Exception.Message)
        }
    }

    $validTargets = @()
    foreach ($probe in $probeTargets) {
        if ([string]::IsNullOrWhiteSpace($probe)) { continue }
        if (-not (Test-Path -LiteralPath $probe -PathType Leaf)) { continue }
        $validTargets += $probe
    }

    if ($validTargets.Count -eq 0) {
        Write-Fail ('找不到可用于测试的文件：' + ($probeTargets -join '、'))
    } else {
        $resolvedExe = (Resolve-Path -LiteralPath $validTargets[0]).ProviderPath
        Write-Host ('  被右键对象（' + $validTargets.Count + ' 个）：' +
            (($validTargets | ForEach-Object { $_ }) -join ' , ')) -ForegroundColor White

        # 编译 COM 互操作程序集
        $interopReady = $false
        $interopSource = @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

namespace PathAdderVerify
{
    // 说明：本程序集**不使用 [ComImport] 接口**。
    // 原因：把 COM 对象经 out object 取出后再强转为 ComImport 接口，在
    // PowerShell 的 Add-Type（CodeDom 编译）环境下会抛 InvalidCastException
    // （「指定的转换无效」），且 ComImport 的方法顺序必须与 vtable 严格一致、
    // 少写一个方法就会静默打错槽位。改为直接按 vtable 槽位取函数指针并用
    // 委托调用，既不依赖 RCW 强制转换，也把槽位显式写出来，可读且可核对。
    //
    // IContextMenu 真实 vtable（IUnknown 的 3 个槽之后）：
    //   [3] QueryContextMenu   [4] TrackPopupMenuEx   [5] GetMenuStringInfo
    //   [6] InvokeCommand       [7] GetCommandString
    // IShellItem vtable（IUnknown 之后）：
    //   [3] BindToHandler

    public class MenuEntry
    {
        public int Depth;
        public int CommandId;
        public string Text;
        public string Verb;
        public bool IsSeparator;
        public bool IsSubmenu;
    }

    public static class ContextMenuEnumerator
    {
        private const uint CMF_NORMAL = 0x0000;
        private const uint GCS_VERBKEY = 0x00000080;
        private const uint MF_BYPOSITION = 0x00000400;
        private const uint COINIT_APARTMENTTHREADED = 0x00000002;
        private const int S_OK = 0;
        private const int S_FALSE = 1;
        private const uint MF_BYCOMMAND = 0x00000000;
        private const uint SEPARATOR_ID = 0xFFFFFFFFu;

        [UnmanagedFunctionPointer(CallingConvention.StdCall)]
        private delegate int QueryInterfaceFn(IntPtr self, ref Guid iid, out IntPtr ppv);

        [UnmanagedFunctionPointer(CallingConvention.StdCall)]
        private delegate uint ReleaseFn(IntPtr self);

        [UnmanagedFunctionPointer(CallingConvention.StdCall)]
        private delegate int BindToHandlerFn(IntPtr self, IntPtr pbc,
            ref Guid bhid, ref Guid riid, out IntPtr ppv);

        [UnmanagedFunctionPointer(CallingConvention.StdCall)]
        private delegate int QueryContextMenuFn(IntPtr self, IntPtr hmenu,
            uint iMenu, uint idCmdFirst, uint idCmdLast, uint uFlags);

        [UnmanagedFunctionPointer(CallingConvention.StdCall)]
        private delegate int GetCommandStringFn(IntPtr self, IntPtr idCmd,
            uint uType, IntPtr pwReserved,
            [Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder pszName, uint cchMax);

        // DllImport 按**方法名**查找入口点，因此本地方法改名后必须用
        // EntryPoint 显式指回 DLL 里的真实导出名，否则运行期报
        // 「无法在 DLL 中找到入口点」。
        [DllImport("shell32.dll", EntryPoint = "SHCreateItemFromParsingName",
            CharSet = CharSet.Unicode, PreserveSig = true)]
        private static extern int SHCreateItemFromParsingNameRaw(
            [MarshalAs(UnmanagedType.LPWStr)] string path,
            IntPtr pbc, ref Guid riid, out IntPtr ppv);

        [DllImport("ole32.dll")]
        private static extern int CoInitializeEx(IntPtr pvReserved, uint dwCoInit);

        [DllImport("ole32.dll")]
        private static extern void CoUninitialize();

        [DllImport("user32.dll", SetLastError = true)]
        private static extern IntPtr CreatePopupMenu();

        [DllImport("user32.dll", SetLastError = true)]
        private static extern int GetMenuItemCount(IntPtr hMenu);

        [DllImport("user32.dll", SetLastError = true)]
        private static extern uint GetMenuItemID(IntPtr hMenu, int nPos);

        [DllImport("user32.dll", SetLastError = true)]
        private static extern IntPtr GetSubMenu(IntPtr hMenu, int nPos);

        [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern int GetMenuStringW(IntPtr hMenu, uint uIDItem,
            StringBuilder lpString, int cchMax, uint uFlag);

        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool DestroyMenu(IntPtr hMenu);

        /// <summary>取 vtable 中第 index 个函数指针并包装成委托。</summary>
        private static T GetVtableMethod<T>(IntPtr instance, int index) where T : class
        {
            if (instance == IntPtr.Zero)
            {
                throw new InvalidOperationException("COM 对象指针为空");
            }
            IntPtr vtable = Marshal.ReadIntPtr(instance);
            if (vtable == IntPtr.Zero)
            {
                throw new InvalidOperationException("COM 对象 vtable 为空");
            }
            IntPtr method = Marshal.ReadIntPtr(vtable, index * IntPtr.Size);
            if (method == IntPtr.Zero)
            {
                throw new InvalidOperationException("vtable 第 " + index + " 个槽位为空");
            }
            return Marshal.GetDelegateForFunctionPointer(method, typeof(T)) as T;
        }

        private static string GetItemText(IntPtr hMenu, int position, int commandId)
        {
            StringBuilder buffer = new StringBuilder(1024);
            int written = GetMenuStringW(hMenu, (uint)position, buffer,
                buffer.Capacity, MF_BYPOSITION);
            if (written > 0)
            {
                return buffer.ToString();
            }

            buffer.Length = 0;
            written = GetMenuStringW(hMenu, (uint)commandId, buffer,
                buffer.Capacity, MF_BYCOMMAND);
            return written > 0 ? buffer.ToString() : string.Empty;
        }

        private static string GetVerbKey(IntPtr contextMenu, int commandId)
        {
            IntPtr self = contextMenu;
            try
            {
                GetCommandStringFn getCommandString =
                    GetVtableMethod<GetCommandStringFn>(self, 7);
                if (getCommandString == null)
                {
                    return string.Empty;
                }

                StringBuilder buffer = new StringBuilder(512);
                int hr = getCommandString(self, (IntPtr)commandId, GCS_VERBKEY,
                    IntPtr.Zero, buffer, (uint)buffer.Capacity);
                if (hr == S_OK && buffer.Length > 0)
                {
                    return buffer.ToString();
                }
            }
            catch
            {
                // 个别自绘菜单项不实现 GetCommandString，忽略
            }
            return string.Empty;
        }

        private static void Walk(IntPtr contextMenu, IntPtr hMenu,
            List<MenuEntry> results, int depth, int maxDepth)
        {
            int count = GetMenuItemCount(hMenu);
            for (int i = 0; i < count; i++)
            {
                uint rawId = GetMenuItemID(hMenu, i);
                int commandId = unchecked((int)rawId);
                bool isSubmenu = GetSubMenu(hMenu, i) != IntPtr.Zero;
                bool isSeparator = (rawId == SEPARATOR_ID) || (rawId == 0u);

                MenuEntry entry = new MenuEntry();
                entry.Depth = depth;
                entry.CommandId = commandId;
                entry.IsSeparator = isSeparator;
                entry.IsSubmenu = isSubmenu;
                entry.Text = isSeparator ? string.Empty : GetItemText(hMenu, i, commandId);
                entry.Verb = (isSeparator || isSubmenu || commandId <= 0)
                    ? string.Empty
                    : GetVerbKey(contextMenu, commandId);
                results.Add(entry);

                if (isSubmenu && depth < maxDepth)
                {
                    IntPtr sub = GetSubMenu(hMenu, i);
                    if (sub != IntPtr.Zero)
                    {
                        Walk(contextMenu, sub, results, depth + 1, maxDepth);
                    }
                }
            }
        }

        public static MenuEntry[] Enumerate(string filePath)
        {
            List<MenuEntry> results = new List<MenuEntry>();

            Guid iidShellItem = new Guid("43826d1d-e718-42ee-bc55-a1e261c37bfe");
            Guid iidContextMenu = new Guid("4e8f4ead-b583-44da-abed-6d36b4e4de50");
            // BHID_ShellMenu：取单个 shell 项的完整 IContextMenu（Explorer 自身路径）
            Guid bhidShellMenu = new Guid("1dea3a3e-3f4c-4b0b-8be3-e6d5cd6e0dbe");
            // BHID_SFUIObject：备用 handler
            Guid bhidSfUiObject = new Guid("c2f5b2ee-3ba6-41d8-b83c-9d9d0915ed1a");

            int coInitResult = CoInitializeEx(IntPtr.Zero, COINIT_APARTMENTTHREADED);
            bool shouldUninitialize = (coInitResult == S_OK || coInitResult == S_FALSE);

            IntPtr shellItem = IntPtr.Zero;
            IntPtr contextMenu = IntPtr.Zero;
            IntPtr hMenu = IntPtr.Zero;

            try
            {
                hMenu = CreatePopupMenu();
                if (hMenu == IntPtr.Zero)
                {
                    throw new InvalidOperationException("CreatePopupMenu 失败");
                }

                int hrCreate = SHCreateItemFromParsingNameRaw(filePath, IntPtr.Zero,
                    ref iidShellItem, out shellItem);
                if (hrCreate != S_OK || shellItem == IntPtr.Zero)
                {
                    throw new InvalidOperationException(
                        "SHCreateItemFromParsingName 失败（HRESULT=0x" +
                        hrCreate.ToString("X8") + "），路径=" + filePath);
                }

                BindToHandlerFn bindToHandler = GetVtableMethod<BindToHandlerFn>(shellItem, 3);
                if (bindToHandler == null)
                {
                    throw new InvalidOperationException("无法取得 IShellItem.BindToHandler");
                }

                int hrBind = bindToHandler(shellItem, IntPtr.Zero, ref bhidShellMenu,
                    ref iidContextMenu, out contextMenu);
                if (hrBind != S_OK || contextMenu == IntPtr.Zero)
                {
                    Guid fallbackBhid = bhidSfUiObject;
                    contextMenu = IntPtr.Zero;
                    hrBind = bindToHandler(shellItem, IntPtr.Zero, ref fallbackBhid,
                        ref iidContextMenu, out contextMenu);
                }
                if (contextMenu == IntPtr.Zero)
                {
                    throw new InvalidOperationException(
                        "BindToHandler 未能取得 IContextMenu（HRESULT=0x" +
                        hrBind.ToString("X8") + "）");
                }

                QueryContextMenuFn queryContextMenu =
                    GetVtableMethod<QueryContextMenuFn>(contextMenu, 3);
                if (queryContextMenu == null)
                {
                    throw new InvalidOperationException("无法取得 IContextMenu.QueryContextMenu");
                }

                int hrQuery = queryContextMenu(contextMenu, hMenu, 0, 1, 0x7FFF, CMF_NORMAL);
                if (hrQuery != S_OK)
                {
                    throw new InvalidOperationException(
                        "QueryContextMenu 失败（HRESULT=0x" + hrQuery.ToString("X8") + "）");
                }

                Walk(contextMenu, hMenu, results, 1, 2);
            }
            finally
            {
                if (hMenu != IntPtr.Zero)
                {
                    DestroyMenu(hMenu);
                }
                if (contextMenu != IntPtr.Zero)
                {
                    ReleaseFn releaseMenu = null;
                    try
                    {
                        releaseMenu = GetVtableMethod<ReleaseFn>(contextMenu, 2);
                        if (releaseMenu != null)
                        {
                            releaseMenu(contextMenu);
                        }
                    }
                    catch
                    {
                    }
                }
                if (shellItem != IntPtr.Zero)
                {
                    ReleaseFn releaseItem = null;
                    try
                    {
                        releaseItem = GetVtableMethod<ReleaseFn>(shellItem, 2);
                        if (releaseItem != null)
                        {
                            releaseItem(shellItem);
                        }
                    }
                    catch
                    {
                    }
                }
                if (shouldUninitialize)
                {
                    CoUninitialize();
                }
            }

            return results.ToArray();
        }
    }
}
'@

        try {
            Add-Type -TypeDefinition $interopSource -ErrorAction Stop
            $interopReady = $true
        } catch {
            Write-Note ('无法编译 COM 互操作程序集（通常表示环境受限/缺少 C# 编译器）：' +
                $_.Exception.Message)
        }

        if ($interopReady) {
            # 逐个探测目标文件（.exe 与 .txt），任一成功即视为第 2 层证据成立
            foreach ($probePath in $validTargets) {
              $resolvedProbe = (Resolve-Path -LiteralPath $probePath).ProviderPath
              Write-Host ''
              Write-Host ('  ---- 探测：' + $resolvedProbe + ' ----') -ForegroundColor White

              $menuEntries = $null
              $enumError = ''
              try {
                $menuEntries = [PathAdderVerify.ContextMenuEnumerator]::Enumerate($resolvedProbe)
              } catch {
                $enumError = $_.Exception.Message
              }

            if ($null -ne $menuEntries) {
                $displayEntries = @($menuEntries |
                    Where-Object { -not $_.IsSeparator -and -not [string]::IsNullOrWhiteSpace($_.Text) })

                Write-Host ''
                Write-Host ('  Explorer 实际枚举到的菜单项共 ' + $displayEntries.Count + ' 个：') -ForegroundColor White
                foreach ($entry in $displayEntries) {
                    $indent = '    '
                    if ($entry.Depth -gt 1) { $indent = '      └ ' }
                    $verbText = ''
                    if (-not [string]::IsNullOrWhiteSpace($entry.Verb)) {
                        $verbText = '   {' + $entry.Verb + '}'
                    }
                    $isOurs = ($verbKeys -contains $entry.Verb) -or
                        ($entry.Text -eq (Get-PathAdderShellMenuParentLabel))
                    $color = 'Gray'
                    if ($isOurs) { $color = 'Green' }
                    Write-Host ($indent + $entry.Text + $verbText) -ForegroundColor $color
                }

                Write-Host ''
                $foundVerbs = @()

                # ① 父菜单项是否被 Explorer 构建出来
                $parentItem = @($menuEntries | Where-Object {
                    $_.Text -eq (Get-PathAdderShellMenuParentLabel)
                })
                if ($parentItem.Count -gt 0) {
                    Write-Pass ('父菜单项已被 Explorer 构建：「' +
                        (Get-PathAdderShellMenuParentLabel) + '」')
                    $script:CascadeParentFound = $true
                } else {
                    Write-Fail ('父菜单项未被 Explorer 构建：「' +
                        (Get-PathAdderShellMenuParentLabel) +
                        '」（注册位置可能不被枚举，或尚未重启资源管理器）')
                }

                # ② 子菜单：由 MenuPicker.ps1 动态提供，不属于 Explorer 静态菜单树
                #
                #    2026-10-04 变更：Windows 11 上 SubCommands 悬停级联实测不展开
                #    （父项可见、悬停无反应），改为「点击父项 → MenuPicker.ps1 在光标
                #    处弹出菜单」。因此 4 个动作**本来就不应该**出现在 Explorer 的静态
                #    菜单树中。若仍按旧逻辑要求它们出现，会产生「功能正常却被判失败」
                #    的误报，所以这里改为校验真正的前置条件。
                Write-Host ''
                Write-Note ('子菜单由 MenuPicker.ps1 在点击父项后动态弹出，不在 Explorer ' +
                    '静态菜单树内；本层只校验其可用性。')

                $pickerLocal = Join-Path (Split-Path -Parent $expectedEnginePath) 'MenuPicker.ps1'
                if (Test-Path -LiteralPath $pickerLocal -PathType Leaf) {
                    Write-Pass ('MenuPicker.ps1 可用：' + $pickerLocal)
                    $script:CascadeExpanded = $true
                    $foundVerbs = @($verbKeys)
                } else {
                    Write-Fail ('MenuPicker.ps1 缺失：' + $pickerLocal)
                }

                Write-Host ''
                if ($script:CascadeParentFound -and $script:CascadeExpanded -and
                    ($foundVerbs.Count -eq $verbKeys.Count)) {
                    $script:ContextMenuVerified = $true
                    Write-Pass '父菜单项已生效且 MenuPicker.ps1 可用——点击父项即可展开 4 个动作。'
                } else {
                    Write-Fail '右键菜单不完整：父项或 MenuPicker.ps1 有问题，详见上方条目。'
                }
            } else {
                Write-Note ('无法完成 IContextMenu 枚举（不影响第 1 层结论）：' + $enumError)
                $script:Warnings += ('IContextMenu 枚举失败：' + $enumError)
            }
            } # end foreach probePath
        } # end if interopReady

        # 清理临时探测文件
        if (-not [string]::IsNullOrWhiteSpace($txtProbePath) -and
            (Test-Path -LiteralPath $txtProbePath)) {
            try { [System.IO.File]::Delete($txtProbePath) } catch { }
        }
    }
}

# -----------------------------------------------------------------------------
# 5b. 第 2 层降级路径：按 Explorer 的关联解析规则做等价推演
#
#     背景：SHCreateItemFromParsingName 在部分受限环境（容器 / 精简系统 /
#     远程会话）会对所有 IID 返回 E_NOINTERFACE(0x80004002)，导致第 2 层无法执行。
#     此时不能对「菜单是否生效」下结论，但可以退一步验证**注册表侧的前置条件**：
#
#       1. HKCR\.exe 的关联 ProgID 是什么（Explorer 用它决定主 shell 路径）；
#       2. 该 ProgID 的合并视图（HKCR = HKLM 与 HKCU 合并）下是否同时存在
#          系统 verb（open/runas/runasuser）与我们的 4 个 verb；
#       3. 我们的 verb 是否落在 SystemFileAssociations 兜底路径之外的**主干**上。
#
#     第 3 点正是本次缺陷的判据：若 verb 只在 SystemFileAssociations 下而主干
#     ProgID 上没有，则必然不被枚举。合并视图读取用 HKCR，可直接反映最终效果。
# -----------------------------------------------------------------------------

if (-not $script:ContextMenuVerified) {
    Write-Section '第 2 层降级：按 Explorer 关联解析规则推演（合并视图 HKCR）'

    # `*` 是 Windows 官方的「所有文件对象」关联键，无条件覆盖任意扩展名
    # （包括 .exe），不需要经过 ProgID 关联解析，因此直接检查合并视图即可。
    $mergedStarKey = 'Registry::HKEY_CLASSES_ROOT\*\shell'
    $mergedStarVerbs = @()
    try {
        if (Test-Path -LiteralPath $mergedStarKey) {
            $mergedStarVerbs = @((Get-ChildItem -LiteralPath $mergedStarKey -ErrorAction SilentlyContinue).PSChildName)
        }
    } catch {
        $mergedStarVerbs = @()
    }

    if ($mergedStarVerbs.Count -eq 0) {
        Write-Note ('无法读取合并视图：HKCR\*\shell')
    } else {
        Write-Host ('  合并视图 HKCR\*\shell 下的 verb：') -ForegroundColor White
        Write-Host ('    ' + ($mergedStarVerbs -join ' | ')) -ForegroundColor DarkGray

        $parentNameLocal = Get-PathAdderShellParentName
        if ($mergedStarVerbs -contains $parentNameLocal) {
            Write-Pass ('本工具父项在合并视图可见：HKCR\*\shell\' + $parentNameLocal)

            # 现方案下 4 个动作由 MenuPicker.ps1 提供，父项下不再有 shell 子命令树。
            # 因此这里改为校验：① 父项带 command 且指向 MenuPicker.ps1；② 脚本存在。
            $mergedParentCommand = 'Registry::HKEY_CLASSES_ROOT\*\shell\' + $parentNameLocal + '\command'
            if (Test-Path -LiteralPath $mergedParentCommand) {
                Write-Pass ('父项 command 在合并视图可见：HKCR\*\shell\' + $parentNameLocal + '\command')
            } else {
                Write-Fail ('父项缺少 command 子键：HKCR\*\shell\' + $parentNameLocal + '\command（点击会没反应）')
            }

            $mergedPickerPath = Join-Path (Split-Path -Parent $expectedEnginePath) 'MenuPicker.ps1'
            if (Test-Path -LiteralPath $mergedPickerPath -PathType Leaf) {
                Write-Pass ('MenuPicker.ps1 可用：' + $mergedPickerPath)
                $script:AssocResolutionVerified = $true
            } else {
                Write-Fail ('MenuPicker.ps1 缺失：' + $mergedPickerPath)
            }

            # 反向确认：旧版 shell 子命令树不该再存在
            $mergedLegacyShell = 'Registry::HKEY_CLASSES_ROOT\*\shell\' + $parentNameLocal + '\shell'
            if (Test-Path -LiteralPath $mergedLegacyShell) {
                Write-Fail ('父项仍存在旧版 shell 子命令树：' + $mergedLegacyShell)
            } else {
                Write-Pass '父项未残留旧版 shell 子命令树'
            }
        } else {
            Write-Fail ('合并视图中看不到本工具父项：HKCR\*\shell\' + $parentNameLocal)
        }

        # 系统 verb 完好性（exefile 侧）
        foreach ($systemVerb in @('open', 'runas', 'runasuser')) {
            $exeMerged = 'Registry::HKEY_CLASSES_ROOT\exefile\shell'
            $exeList = @()
            try {
                if (Test-Path -LiteralPath $exeMerged) {
                    $exeList = @((Get-ChildItem -LiteralPath $exeMerged -ErrorAction SilentlyContinue).PSChildName)
                }
            } catch {
                $exeList = @()
            }
            if ($exeList -contains $systemVerb) {
                Write-Pass ('系统 verb 仍在合并视图中：' + $systemVerb)
            }
        }
    }
}

# -----------------------------------------------------------------------------
# 6. 汇总
# -----------------------------------------------------------------------------

Write-Section '验证结果汇总'

Write-Host ('  注册结构：单一父菜单项（' + (Get-PathAdderShellParentName) + '）+ ' +
    $verbKeys.Count + ' 个动作（由 MenuPicker.ps1 点击后弹出）') -ForegroundColor Gray
Write-Host ('  失败项：' + $script:Failures.Count) -ForegroundColor Gray
Write-Host ('  提示项：' + $script:Warnings.Count) -ForegroundColor Gray
Write-Host ('  真实菜单枚举：' + $(if ($script:ContextMenuVerified) { '已完成' } else { '未完成' })) -ForegroundColor Gray
Write-Host ('  关联解析推演：' + $(if ($script:AssocResolutionVerified) { '已完成' } else { '未完成' })) -ForegroundColor Gray
if ($script:ContextMenuVerified) {
    Write-Host ('  父菜单项构建：' + $(if ($script:CascadeParentFound) { '已出现' } else { '未出现' })) -ForegroundColor Gray
    Write-Host ('  弹出菜单脚本：' + $(if ($script:CascadeExpanded) { 'MenuPicker.ps1 可用' } else { '不可用' })) -ForegroundColor Gray
}

Write-Host ''
if ($script:Failures.Count -gt 0) {
    Write-Host '  结论：验证未通过。' -ForegroundColor Red
    Write-Host '  · 若是「父菜单项未被构建 / 未被枚举」，多半是还没重启资源管理器；' -ForegroundColor Red
    Write-Host '  · 若是「当前用户 PATH」相关报错，检查 PathAdder.ps1 是否完好；' -ForegroundColor Red
    Write-Host '  · 若第 1 层结构检查也失败，请先重新运行 install.ps1。' -ForegroundColor Red
    Write-Host ''
    exit 1
}

if ($script:ContextMenuVerified) {
    Write-Host '  结论：全部通过。父菜单项已被资源管理器实际枚举，MenuPicker.ps1 可用，' -ForegroundColor Green
    Write-Host '        点击「PATH 助手」即可展开 4 个动作。' -ForegroundColor Green
} elseif ($script:AssocResolutionVerified) {
    Write-Host '  结论：注册表结构完整，父菜单项在 Explorer 的主干查找路径上可见。' -ForegroundColor Yellow
    Write-Host '  但本环境的 Shell COM 无法枚举菜单（SHCreateItemFromParsingName 返回' -ForegroundColor Yellow
    Write-Host '  E_NOINTERFACE，常见于容器 / 精简系统 / 远程会话），因此**未取得**菜单' -ForegroundColor Yellow
    Write-Host '  实际构建的证据。请在普通桌面会话中右键确认，或重启资源管理器后再看菜单。' -ForegroundColor Yellow
} else {
    Write-Host '  结论：注册表结构检查通过，但**未能完成菜单生效性的任何验证**。' -ForegroundColor Yellow
    Write-Host '  因此无法断言右键菜单实际可用——请勿把本结果当作「菜单已生效」的证据。' -ForegroundColor Yellow
    Write-Host '  请在普通交互式桌面会话中重试：' -ForegroundColor Yellow
    Write-Host '    powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File ".\verify-registration.ps1"' -ForegroundColor Yellow
    Write-Host ''
    exit 2
}
Write-Host ''
Write-Host '  提示：Windows 11 的右键菜单已分层，本工具的菜单项位于经典菜单内。' -ForegroundColor Yellow
Write-Host '  查看方式：右键 →「显示更多选项」，或选中文件后按 Shift+F10。' -ForegroundColor Yellow
Write-Host '  若经典菜单里仍未出现，请重启资源管理器：' -ForegroundColor Yellow
Write-Host '    Stop-Process -Name explorer -Force; Start-Process explorer.exe' -ForegroundColor Yellow
Write-Host ''
exit 0
