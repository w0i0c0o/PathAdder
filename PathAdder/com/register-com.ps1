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
Write-Host '=== 步骤 3/4：切换菜单位为原生级联 ===' -ForegroundColor Cyan

$key = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($verbKey)
try {
    # 先移除 MenuPicker 模式的 command（两者并存时行为不确定）
    try {
        $stale = $key.OpenSubKey('command', $false)
        if ($null -ne $stale) {
            $stale.Close()
            $key.DeleteSubKeyTree('command', $false)
            Write-Host '已移除 MenuPicker 模式的 command 子键。' -ForegroundColor Gray
        }
    }
    catch { }

    $key.SetValue('ExplorerCommandHandler', $parentClsid, [Microsoft.Win32.RegistryValueKind]::String)
    $key.SetValue('MUIVerb', 'PATH 助手', [Microsoft.Win32.RegistryValueKind]::String)
    Write-Host ('ExplorerCommandHandler = ' + $parentClsid) -ForegroundColor Green
}
finally {
    $key.Close()
}

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
Write-Host '⚠ 必须重启资源管理器，否则菜单不会变化：' -ForegroundColor Yellow
Write-Host '    Stop-Process -Name explorer -Force; Start-Process explorer.exe' -ForegroundColor Gray
Write-Host ''
Write-Host '验证：右键任意文件 →「显示更多选项」→' -ForegroundColor Cyan
Write-Host '      鼠标【悬停】在「PATH 助手」上，应展开 4 个子菜单项。' -ForegroundColor Cyan
Write-Host ''
Write-Host '若悬停仍不展开，或想回到原来的点击弹出方式：' -ForegroundColor Gray
Write-Host '    .\restore-menu.ps1' -ForegroundColor Gray
Write-Host ''

exit 0
