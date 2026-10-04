<#
.SYNOPSIS
    强制重新编译并注册 COM 扩展，自动处理「PathAdderShellExt.dll 正被占用」。

.DESCRIPTION
    为什么会被占用：
    .NET 程序集一旦被 explorer.exe 之类的进程 LoadLibrary 加载，Windows 就
    不允许别人再写入它，于是编译时覆盖失败。这不是脚本的 bug，是 COM 加载
    的正常后果 —— 用 regsvr32 /u 是解决不了的（见下方「常见误区」）。

    本脚本的处理顺序：
      1. 检测 DLL 是否被锁
      2. 被锁 -> 重启资源管理器释放锁（会关闭所有文件夹窗口），再检测一次
      3. 若仍被锁 -> 提示是杀毒软件/同步盘在扫描，建议稍后重试或换目录
      4. 编译 -> 注册 -> 提示重启 explorer 验证

.常见误区
    regsvr32 /u "xxx.dll" 対 .NET 程序集是错的！
    报错「找不到入口点 DllUnregisterServer」是必然的，因为 .NET 程序集
    没有 DllRegisterServer / DllUnregisterServer 这两个导出函数，它们由
    mscoree.dll 代理。必须用 RegAsm.exe：
        注销：RegAsm.exe /unregister "path\to.dll"
        注册：RegAsm.exe /codebase  "path\to.dll"
    本脚本内部已经用 RegAsm 处理，不需要你手动执行。

.EXAMPLE
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\rebuild.ps1
#>

[CmdletBinding()]
param(
    # 不询问，直接重启资源管理器
    [switch]$RestartExplorer,
    # 只编译不注册
    [switch]$SkipRegister
)

$ErrorActionPreference = 'Stop'

$dllPath = Join-Path $PSScriptRoot 'PathAdderShellExt.dll'
$dllName = Split-Path -Leaf $dllPath

function Test-DllLocked {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    try {
        $stream = [System.IO.File]::Open($Path, 'Open', 'ReadWrite', 'None')
        $stream.Close()
        $stream.Dispose()
        return $false
    }
    catch {
        return $true
    }
}

function Get-DllHolder {
    param([string]$Name)

    # tasklist /m 能列出把该模块加载进地址空间的进程
    $result = @()
    try {
        $raw = & tasklist.exe /m $Name 2>$null
        if ($raw) {
            foreach ($line in $raw) {
                if ($line -match '^\s*([^\s]+\.exe)\s+(\d+)') {
                    $result += ($matches[1] + ' (pid=' + $matches[2] + ')')
                }
            }
        }
    }
    catch { }
    return $result
}

Write-Host '=== 步骤 1/4：检测 DLL 占用 ===' -ForegroundColor Cyan

if (-not (Test-DllLocked -Path $dllPath)) {
    Write-Host 'DLL 未被占用，可以直接编译。' -ForegroundColor Green
}
else {
    Write-Host 'DLL 被占用，无法覆盖编译。' -ForegroundColor Yellow

    $holders = Get-DllHolder -Name $dllName
    if ($holders.Count -gt 0) {
        Write-Host '占用者：' -ForegroundColor Yellow
        foreach ($h in $holders) { Write-Host ('    ' + $h) -ForegroundColor Gray }
    }
    else {
        Write-Host '（没有任何进程把它当模块加载 —— 说明是纯文件句柄，' -ForegroundColor Gray
        Write-Host '  多半是杀毒软件实时扫描或网盘同步在读写它）' -ForegroundColor Gray
    }

    Write-Host ''
    Write-Host '解决办法：重启资源管理器以释放占用。' -ForegroundColor Yellow

    $go = $RestartExplorer
    if (-not $go) {
        Write-Host '注意：所有已打开的文件夹窗口会被关闭。' -ForegroundColor Yellow
        $ans = Read-Host '现在自动重启资源管理器？(y/N)'
        $go = ($ans -eq 'y' -or $ans -eq 'Y')
    }

    if ($go) {
        Get-Process explorer -ErrorAction SilentlyContinue | Stop-Process -Force
        Start-Sleep -Seconds 3
        Start-Process explorer.exe
        Start-Sleep -Seconds 4
        Write-Host '已重启资源管理器。' -ForegroundColor Green

        if (Test-DllLocked -Path $dllPath) {
            Write-Host ''
            Write-Host '仍然被占用 —— 大概率是杀毒软件或同步盘正在扫描该文件。' -ForegroundColor Red
            Write-Host '可以这样处理：' -ForegroundColor Yellow
            Write-Host '   1) 等 10~30 秒后重跑本脚本；或' -ForegroundColor Gray
            Write-Host '   2) 把整个 PathAdder 目录移到纯英文路径（例如 C:\PathAdder）后重试；或' -ForegroundColor Gray
            Write-Host '   3) 在杀毒软件里把 PathAdder\com 目录加入排除项。' -ForegroundColor Gray

            if (-not $SkipRegister) {
                Write-Host ''
                Write-Host '提示：若 DLL 已经是可用的旧版本，可以只重新注册而不编译：' -ForegroundColor Gray
                Write-Host '   .\register-com.ps1 -SkipBuild' -ForegroundColor Gray
            }
            exit 1
        }
        Write-Host '占用已释放。' -ForegroundColor Green
    }
    else {
        Write-Host '已取消。请手动执行下面命令后重跑本脚本：' -ForegroundColor Yellow
        Write-Host '    Stop-Process -Name explorer -Force; Start-Process explorer.exe' -ForegroundColor Gray
        exit 1
    }
}

# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '=== 步骤 2/4：编译 ===' -ForegroundColor Cyan
& (Join-Path $PSScriptRoot 'build.ps1')
if ($LASTEXITCODE -ne 0) {
    Write-Host ('编译失败，退出码 ' + $LASTEXITCODE) -ForegroundColor Red
    exit $LASTEXITCODE
}

# ---------------------------------------------------------------------------
if ($SkipRegister) {
    Write-Host ''
    Write-Host '已指定 -SkipRegister，跳过注册。' -ForegroundColor Gray
    exit 0
}

Write-Host ''
Write-Host '=== 步骤 3/4：注册并切换菜单 ===' -ForegroundColor Cyan
& (Join-Path $PSScriptRoot 'register-com.ps1') -SkipBuild
if ($LASTEXITCODE -ne 0) {
    Write-Host ('注册失败，退出码 ' + $LASTEXITCODE) -ForegroundColor Red
    exit $LASTEXITCODE
}

# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '=== 步骤 4/4：完成 ===' -ForegroundColor Cyan
Write-Host ''
Write-Host '现在重启资源管理器，然后右键文件 ->「显示更多选项」测试。' -ForegroundColor White
Write-Host '把日志（%TEMP%\PathAdderShellExt.log）贴出来即可定位问题。' -ForegroundColor White
Write-Host ''
Write-Host '想回到「点击弹出」的可用模式：' -ForegroundColor Gray
Write-Host '    .\restore-menu.ps1' -ForegroundColor Gray
Write-Host ''
exit 0
