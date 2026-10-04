<#
.SYNOPSIS
    注册 PathAdder COM 外壳扩展，并切换到「原生悬停级联」模式。

.DESCRIPTION
    做四件事：
      1. 编译（若 DLL 不存在或源码更新）
      2. regasm /codebase 注册 COM 类（写 HKLM，需管理员）
      3. 把 *\shell\PathAdder 从「command 弹出菜单」切换为
         ExplorerCommandHandler = {CLSID}（由 Explorer 原生枚举子命令）
      4. 通知资源管理器刷新

    切换是可逆的：运行 restore-menu.ps1 可回到 MenuPicker 模式。

    ⚠ 重要前提（Windows 11）：
    本方式注册的处理程序只出现在【经典菜单】（「显示更多选项」/ Shift+F10）中。
    若要让菜单出现在 Win11 的第一层（新版精简菜单），必须额外做 MSIX 打包并
    在 Package.appxmanifest 中声明 desktop4:FileExplorerContextMenus。
    详见 README-COM.md。

.EXAMPLE
    # 必须以管理员身份运行
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\register-com.ps1
#>

[CmdletBinding()]
param(
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'

# 父命令 CLSID（与 PathAdderShellExt.cs 中的 PathAdderCommand 一致）
$parentClsid = '{1C789ABD-65D1-5FAD-8B98-52595EBB290B}'
$verbKey = 'Software\Classes\*\shell\PathAdder'

# ---------------------------------------------------------------------------
# 0. 管理员检查（regasm 要写 HKLM）
# ---------------------------------------------------------------------------
$isAdmin = $false
try {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    $isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
catch { $isAdmin = $false }

if (-not $isAdmin) {
    Write-Host '此操作需要管理员权限（regasm 要写 HKLM 注册 COM 类）。' -ForegroundColor Red
    Write-Host '请右键 PowerShell / 终端 →「以管理员身份运行」，再执行本脚本。' -ForegroundColor Yellow
    exit 1
}

# ---------------------------------------------------------------------------
# 1. 编译
# ---------------------------------------------------------------------------
$dllPath = Join-Path $PSScriptRoot 'PathAdderShellExt.dll'
$sourcePath = Join-Path $PSScriptRoot 'PathAdderShellExt.cs'

if ($SkipBuild) {
    Write-Host '已指定 -SkipBuild，跳过编译。' -ForegroundColor Gray
}
else {
    Write-Host '=== 步骤 1/4：编译 ===' -ForegroundColor Cyan
    & (Join-Path $PSScriptRoot 'build.ps1')
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

if (-not (Test-Path -LiteralPath $dllPath -PathType Leaf)) {
    Write-Host ('DLL 不存在：' + $dllPath) -ForegroundColor Red
    exit 1
}

# ---------------------------------------------------------------------------
# 2. regasm 注册
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '=== 步骤 2/4：COM 注册（regasm）===' -ForegroundColor Cyan

$regasmPath = ''
$frameworkRoot = Join-Path $env:WINDIR 'Microsoft.NET\Framework64'
foreach ($dir in @(Get-ChildItem -LiteralPath $frameworkRoot -Directory | Sort-Object Name -Descending)) {
    $candidate = Join-Path $dir.FullName 'RegAsm.exe'
    if (Test-Path -LiteralPath $candidate -PathType Leaf) { $regasmPath = $candidate; break }
}

if ([string]::IsNullOrWhiteSpace($regasmPath)) {
    Write-Host '未找到 RegAsm.exe。' -ForegroundColor Red
    exit 1
}

& $regasmPath /codebase /nologo "$dllPath"
if ($LASTEXITCODE -ne 0) {
    Write-Host ('regasm 注册失败，退出码 ' + $LASTEXITCODE) -ForegroundColor Red
    exit $LASTEXITCODE
}
Write-Host 'COM 类已注册。' -ForegroundColor Green

# ---------------------------------------------------------------------------
# 3. 切换为 ExplorerCommandHandler
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '=== 步骤 3/4：切换菜单位为原生级联（全量清理 + 单点写入）===' -ForegroundColor Cyan

# ---------------------------------------------------------------------------
# 3.1 全量清理：把历史上可能注册过的 PathAdder 菜单键统统抹掉。
#
#     ⚠ 本次排障的关键结论（务必保留这条注释）：
#       同一个菜单键如果【同时】存在 command 子键 和 ExplorerCommandHandler 值，
#       Explorer 会把同一 CLSID 实例化两遍 —— 一遍按普通动词（只调 GetState /
#       Invoke），一遍按级联父项（调 GetFlags / GetTitle / EnumSubCommands）。
#       实测现象就是：父项「PATH 助手」看得见，但【悬停永远不展开子菜单】，
#       因为负责枚举的那一路根本没拿到枚举结果。
#       因此必须先清理干净，再单点写入，绝不允许两者并存。
# ---------------------------------------------------------------------------
$stalePaths = @(
    'Software\Classes\*\shell\PathAdder',
    'Software\Classes\exefile\shell\PathAdder',
    'Software\Classes\Directory\shell\PathAdder',
    'Software\Classes\AllFilesystemObjects\shell\PathAdder'
)
$scopes = @(
    @{ Label = 'HKLM'; Root = ([Microsoft.Win32.Registry]::LocalMachine) },
    @{ Label = 'HKCU'; Root = ([Microsoft.Win32.Registry]::CurrentUser) }
)

foreach ($scope in $scopes) {
    foreach ($rel in $stalePaths) {
        $exists = $false
        try {
            $probe = $scope.Root.OpenSubKey($rel)
            if ($null -ne $probe) { $probe.Close(); $exists = $true }
        }
        catch { $exists = $false }

        if (-not $exists) { continue }

        Write-Host ('  发现残留键：' + $scope.Label + '\' + $rel) -ForegroundColor DarkYellow

        try {
            $k = $scope.Root.OpenSubKey($rel, $true)

            $names = @($k.GetValueNames())
            if ($names -contains 'ExplorerCommandHandler') {
                $k.DeleteValue('ExplorerCommandHandler', $false)
                Write-Host ('    已删除 ExplorerCommandHandler 值') -ForegroundColor Gray
            }

            $subs = @($k.GetSubKeyNames())
            if ($subs -contains 'command') {
                $k.DeleteSubKeyTree('command')
                Write-Host ('    已删除 command 子键（它与 ExplorerCommandHandler 互斥）') -ForegroundColor Gray
            }

            $remainSubs = @($k.GetSubKeyNames()).Count
            $remainVals = @($k.GetValueNames()).Count
            $k.Close()

            if (($remainSubs -eq 0) -and ($remainVals -eq 0)) {
                $scope.Root.DeleteSubKeyTree($rel, $false)
                Write-Host ('    该键已空，整体移除（避免二次注册）') -ForegroundColor Gray
            }
        }
        catch {
            Write-Host ('    清理时跳过：' + $_.Exception.Message) -ForegroundColor DarkYellow
        }
    }
}

# ---------------------------------------------------------------------------
# 3.2 单点写入：只在 HKLM 落一个权威键（regasm 已确保是管理员，写 HKLM 一致）
# ---------------------------------------------------------------------------
$newKey = $null
try { $newKey = $scopes[0].Root.CreateSubKey($verbKey) } catch { $newKey = $null }
if ($null -eq $newKey) { $newKey = $scopes[1].Root.CreateSubKey($verbKey) }

if ($null -eq $newKey) {
    Write-Host '创建菜单键失败：HKLM 与 HKCU 都写不进去。' -ForegroundColor Red
    exit 1
}

try {
    $newKey.SetValue('', 'PATH 助手', [Microsoft.Win32.RegistryValueKind]::String)
    $newKey.SetValue('MUIVerb', 'PATH 助手', [Microsoft.Win32.RegistryValueKind]::String)
    $newKey.SetValue('ExplorerCommandHandler', $parentClsid, [Microsoft.Win32.RegistryValueKind]::String)
    $newKey.SetValue('Position', 'Bottom', [Microsoft.Win32.RegistryValueKind]::String)
    Write-Host ('已写入 ExplorerCommandHandler = ' + $parentClsid) -ForegroundColor Green
}
finally {
    $newKey.Close()
}

# 3.3 回读自检：任一项不通过就立刻报出来，不要等到用户发现「没有子菜单」
Write-Host ''
Write-Host '=== 写入回读自检 ===' -ForegroundColor Cyan
$check = $scopes[0].Root.OpenSubKey($verbKey)
if ($null -eq $check) {
    Write-Host '✗ 菜单键不存在。' -ForegroundColor Red
    exit 1
}
$actualHandler = $check.GetValue('ExplorerCommandHandler', '')
$actualCommand = ''
try { $actualCommand = $check.OpenSubKey('command', $false) } catch { }
$check.Close()

if ($actualHandler -ne $parentClsid) {
    Write-Host ('✗ ExplorerCommandHandler 不对：实际=「' + $actualHandler + '」') -ForegroundColor Red
    exit 1
}
if ($null -ne $actualCommand) {
    Write-Host '✗ command 子键仍然存在，与 ExplorerCommandHandler 互斥，必须删除。' -ForegroundColor Red
    exit 1
}
Write-Host '✓ 菜单键完整：ExplorerCommandHandler 正确，且没有残留 command 子键。' -ForegroundColor Green

# ---------------------------------------------------------------------------
# 4. 通知刷新
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '=== 步骤 4/4：通知资源管理器 ===' -ForegroundColor Cyan

$refreshed = $false
try {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class PathAdderNotify {
    [DllImport("shell32.dll", CharSet=CharSet.Auto)]
    public static extern void SHChangeNotify(uint wEventId, uint uFlags, IntPtr dwItem1, IntPtr dwItem2);
    public const uint SHCNE_ASSOCCHANGED = 0x08000000;
    public const uint SHCNF_IDLIST = 0x0000;
}
'@ -ErrorAction Stop
    [PathAdderNotify]::SHChangeNotify([PathAdderNotify]::SHCNE_ASSOCCHANGED, [PathAdderNotify]::SHCNF_IDLIST, [IntPtr]::Zero, [IntPtr]::Zero)
    $refreshed = $true
}
catch {
    Write-Host ('刷新通知失败（不影响注册结果）：' + $_.Exception.Message) -ForegroundColor Yellow
}

Write-Host ''
Write-Host '========== 注册完成 ==========' -ForegroundColor Green
Write-Host ''
Write-Host '⚠ 必须重启资源管理器，否则加载的还是旧代码 / 菜单不会变化：' -ForegroundColor Yellow
Write-Host '    Stop-Process -Name explorer -Force; Start-Process explorer.exe' -ForegroundColor Gray
Write-Host ''
Write-Host '验证三步：' -ForegroundColor Cyan
Write-Host '  1) 右键任意文件 →「显示更多选项」→ 鼠标【悬停】到「PATH 助手」上' -ForegroundColor Gray
Write-Host '  2) 子菜单应展开出 4 项 + 1 条分隔线' -ForegroundColor Gray
Write-Host '  3) 若没展开，看诊断日志：' -ForegroundColor Gray
Write-Host '        type "%TEMP%\PathAdderShellExt.log"' -ForegroundColor Gray
Write-Host ''
Write-Host '日志判读（关键）：' -ForegroundColor Cyan
Write-Host '  · 出现「SubCommandEnum.Next」→ 级联成功与否看 Expando；' -ForegroundColor Gray
Write-Host '  · 只有 GetFlags/GetTitle/EnumSubCommands，没有 Next → Explorer 没当它是级联父项；' -ForegroundColor Gray
Write-Host '  · 出现两次「PathAdderCommand 构造」→ 菜单被重复注册了（command 与 handler 并存），' -ForegroundColor Gray
Write-Host '    本脚本的 3.1 清理步骤就是修这个的；若仍出现请检查其它位置的同名键。' -ForegroundColor Gray
Write-Host '  · 日志完全为空 → explorer 从未加载本 DLL，检查菜单键是否被别的脚本删掉了。' -ForegroundColor Gray
Write-Host ''
Write-Host '想回到「点击弹出菜单」这种不依赖 Explorer 级联的方式：' -ForegroundColor Gray
Write-Host '    .\restore-menu.ps1' -ForegroundColor Gray
Write-Host ''

exit 0
