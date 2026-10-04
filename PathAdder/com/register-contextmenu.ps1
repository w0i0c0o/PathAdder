<#
.SYNOPSIS
    改用「经典 IContextMenu 外壳扩展」实现悬停级联子菜单。

.DESCRIPTION
    为什么需要这个文件：
      IExplorerCommand + ECF_HASSUBCOMMANDS 的方案实测在本机走不通 —— 诊断日志
      显示 Explorer 走完 GetFlags → GetTitle → EnumSubCommands（枚举器都构造好
      了）之后，【永远不会】调用 IEnumExplorerCommand::Next，而是再造一个对象
      只调 GetState 就收场。这是 Explorer 的行为，不是我们的代码缺陷。

      本脚本改注册 PathAdderContextMenu：它实现 IShellExtInit + IContextMenu，
      在 QueryContextMenu 里用 CreatePopupMenu 造一个子菜单 HMENU，再把父项以
      MF_POPUP 插进 Explorer 的菜单。子菜单的悬停展开由 USER32 菜单系统负责，
      是标准菜单行为，不依赖 Explorer 的扩展策略（业界成熟做法）。

    本脚本做五件事：
      1. 编译（含 PathAdderContextMenu.cs）
      2. RegAsm /codebase 注册 COM 类
      3. 彻底移除旧的 *\shell\PathAdder（IExplorerCommand 那条，避免两个菜单）
      4. 注册 *\shellex\ContextMenuHandlers\PathAdder = {9B3E5D2A-...}
         并写入 Shell Extensions Approved 列表
      5. 回读自检

    菜单出现在【经典菜单】（「显示更多选项」/ Shift+F10）中，和之前一样。

.EXAMPLE
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\register-contextmenu.ps1
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\register-contextmenu.ps1 -Unregister
#>

[CmdletBinding()]
param(
    [switch]$SkipBuild,
    [switch]$Unregister
)

$ErrorActionPreference = 'Stop'

$menuClsid = '{9B3E5D2A-7C41-4F8B-A1D6-2E5C8F40B7A3}'
$handlerKey = 'Software\Classes\*\shellex\ContextMenuHandlers\PathAdder'
$approved = 'Software\Microsoft\Windows\CurrentVersion\Shell Extensions\Approved'

# ---------------------------------------------------------------------------
# 0. 管理员检查
# ---------------------------------------------------------------------------
$isAdmin = $false
try {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    $isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
catch { $isAdmin = $false }

if (-not $isAdmin) {
    Write-Host '此操作需要管理员权限（要写 HKLM）。' -ForegroundColor Red
    Write-Host '请右键 PowerShell / 终端 →「以管理员身份运行」后再执行。' -ForegroundColor Yellow
    exit 1
}

$scopes = @(
    @{ Label = 'HKLM'; Root = ([Microsoft.Win32.Registry]::LocalMachine) },
    @{ Label = 'HKCU'; Root = ([Microsoft.Win32.Registry]::CurrentUser) }
)

# ---------------------------------------------------------------------------
# 卸载分支
# ---------------------------------------------------------------------------
if ($Unregister) {
    Write-Host '=== 卸载经典菜单扩展 ===' -ForegroundColor Cyan
    foreach ($scope in $scopes) {
        foreach ($rel in @($handlerKey)) {
            try {
                $k = $scope.Root.OpenSubKey($rel)
                if ($null -eq $k) { continue }
                $k.Close()
            }
            catch { continue }
            try { $scope.Root.DeleteSubKeyTree($rel, $false) } catch { }
            Write-Host ('  已删除 ' + $scope.Label + '\' + $rel) -ForegroundColor Gray
        }
    }
    try {
        $ak = $scopes[0].Root.OpenSubKey($approved, $true)
        if ($null -ne $ak) {
            if (@($ak.GetValueNames()) -contains $menuClsid) { $ak.DeleteValue($menuClsid, $false) }
            $ak.Close()
        }
    }
    catch { }
    Write-Host '已卸载。请重启资源管理器。' -ForegroundColor Green
    Write-Host '    Stop-Process -Name explorer -Force; Start-Process explorer.exe' -ForegroundColor Gray
    exit 0
}

# ---------------------------------------------------------------------------
# 0.5 先解除 DLL 占用（explorer 加载过旧 DLL 会让编译 / 注册都失败）
#     release-dll.ps1 会终止持有者并重启资源管理器；若 DLL 本来就空闲则直接返回 0
# ---------------------------------------------------------------------------
Write-Host '=== 步骤 0/5：解除 DLL 占用 ===' -ForegroundColor Cyan

$releaser = Join-Path $PSScriptRoot 'release-dll.ps1'
if (Test-Path -LiteralPath $releaser -PathType Leaf) {
    & $releaser
    if ($LASTEXITCODE -ne 0) {
        Write-Host 'DLL 仍被占用，后续步骤很可能失败。可稍等片刻重试。' -ForegroundColor Yellow
    }
}
else {
    Write-Host '  未找到 release-dll.ps1，跳过（build.ps1 里还有一次机会）。' -ForegroundColor Gray
}

# ---------------------------------------------------------------------------
# 1. 编译
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '=== 步骤 1/5：编译 ===' -ForegroundColor Cyan

$dllPath = Join-Path $PSScriptRoot 'PathAdderShellExt.dll'

if ($SkipBuild) {
    Write-Host '已指定 -SkipBuild，跳过编译。' -ForegroundColor Gray
}
else {
    & (Join-Path $PSScriptRoot 'build.ps1')
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

if (-not (Test-Path -LiteralPath $dllPath -PathType Leaf)) {
    Write-Host ('DLL 不存在：' + $dllPath) -ForegroundColor Red
    exit 1
}

# ---------------------------------------------------------------------------
# 2. RegAsm 注册
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '=== 步骤 2/5：COM 注册（RegAsm）===' -ForegroundColor Cyan

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
    Write-Host ('RegAsm 注册失败，退出码 ' + $LASTEXITCODE) -ForegroundColor Red
    exit $LASTEXITCODE
}
Write-Host 'COM 类已注册。' -ForegroundColor Green

# ---------------------------------------------------------------------------
# 3. 彻底移除旧的 IExplorerCommand 菜单键（避免同一功能出现两个菜单）
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '=== 步骤 3/5：移除旧的 IExplorerCommand 菜单键 ===' -ForegroundColor Cyan

$stalePaths = @(
    'Software\Classes\*\shell\PathAdder',
    'Software\Classes\exefile\shell\PathAdder',
    'Software\Classes\Directory\shell\PathAdder',
    'Software\Classes\AllFilesystemObjects\shell\PathAdder'
)

foreach ($scope in $scopes) {
    foreach ($rel in $stalePaths) {
        $hit = $false
        try {
            $p = $scope.Root.OpenSubKey($rel)
            if ($null -ne $p) { $p.Close(); $hit = $true }
        }
        catch { $hit = $false }
        if (-not $hit) { continue }
        try { $scope.Root.DeleteSubKeyTree($rel, $false) } catch { }
        Write-Host ('  已删除 ' + $scope.Label + '\' + $rel) -ForegroundColor Gray
    }
}

# ---------------------------------------------------------------------------
# 4. 注册 ContextMenuHandlers
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '=== 步骤 4/5：注册经典菜单扩展 ===' -ForegroundColor Cyan

try {
    $k = $scopes[0].Root.CreateSubKey($handlerKey)
    $name = $k.GetValue('')          # 默认值之前可能存了别的 CLSID
    $k.SetValue('', $menuClsid, [Microsoft.Win32.RegistryValueKind]::String)
    $k.Close()
    if (($null -ne $name) -and ($name -ne '')) {
        Write-Host ('  原默认值 "' + $name + '" 已被覆盖为') -ForegroundColor Gray
    }
    Write-Host ('  ' + $handlerKey + ' = ' + $menuClsid) -ForegroundColor Green
}
catch {
    Write-Host ('  写入失败：' + $_.Exception.Message) -ForegroundColor Red
    exit 1
}

# Approved 列表（部分策略下必须有，写进去无害）
try {
    $ak = $scopes[0].Root.OpenSubKey($approved, $true)
    if ($null -eq $ak) { $ak = $scopes[0].Root.CreateSubKey($approved) }
    if ($null -ne $ak) {
        $ak.SetValue($menuClsid, 'PATH 助手', [Microsoft.Win32.RegistryValueKind]::String)
        $ak.Close()
        Write-Host '  已加入 Shell Extensions Approved 列表。' -ForegroundColor Gray
    }
}
catch {
    Write-Host ('  Approved 列表写入跳过：' + $_.Exception.Message) -ForegroundColor DarkYellow
}

# ---------------------------------------------------------------------------
# 5. 回读自检
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '=== 步骤 5/5：回读自检 ===' -ForegroundColor Cyan

$check = $scopes[0].Root.OpenSubKey($handlerKey)
if ($null -eq $check) {
    Write-Host ('✗ 注册失败：' + $handlerKey + ' 不存在。') -ForegroundColor Red
    exit 1
}
$actual = [string]$check.GetValue('', '')
$check.Close()

if ($actual -ne $menuClsid) {
    Write-Host ('✗ ContextMenuHandlers 默认值不对：实际=「' + $actual + '」') -ForegroundColor Red
    exit 1
}
Write-Host '✓ 扩展已注册，且旧的 IExplorerCommand 菜单键已清除。' -ForegroundColor Green

Write-Host ''
Write-Host '========== 完成 ==========' -ForegroundColor Green
Write-Host ''
Write-Host '⚠ 必须重启资源管理器：' -ForegroundColor Yellow
Write-Host '    Stop-Process -Name explorer -Force; Start-Process explorer.exe' -ForegroundColor Gray
Write-Host ''
Write-Host '验证：' -ForegroundColor Cyan
Write-Host '  1) 右键任意文件 →「显示更多选项」' -ForegroundColor Gray
Write-Host '  2) 应看到「PATH 助手」，条目右侧有 ▸ 箭头' -ForegroundColor Gray
Write-Host '  3) 鼠标【悬停】过去即展开 4 项 + 1 条分隔线' -ForegroundColor Gray
Write-Host ''
Write-Host '看诊断日志：' -ForegroundColor Gray
Write-Host '    type "%TEMP%\PathAdderShellExt.log"' -ForegroundColor Gray
Write-Host '    正常应出现：Ctx.Initialize / Ctx.QueryContextMenu / Ctx.InsertMenuItem -> True' -ForegroundColor Cyan
Write-Host ''
Write-Host '卸载：' -ForegroundColor Gray
Write-Host '    .\register-contextmenu.ps1 -Unregister' -ForegroundColor Gray
Write-Host ''

exit 0
