<#
.SYNOPSIS
    一键诊断「悬停不展开子菜单」：重编译带日志的 DLL、注册、切换菜单，
    然后等你实测悬停后把 DLL 的运行日志打印出来。

.DESCRIPTION
    为什么需要它：
    上一轮只知道「悬停没有子菜单」，但 GUI 现象无法区分下面三种情况：
      A. explorer 根本没创建 COM 对象（handler 被忽略）
      B. 创建了，但没调用 EnumSubCommands（不认为是级联父项）
      C. 调用了枚举器，但子菜单构建失败
    本脚本通过在 DLL 内写日志来区分这三者。

    ⚠ 本脚本会重启资源管理器（所有文件夹窗口会关闭）。

.EXAMPLE
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\diag-cascade.ps1
#>

[CmdletBinding()]
param(
    # 不自动重启资源管理器（那你得自己重启，否则测的还是旧状态）
    [switch]$NoRestart
)

$ErrorActionPreference = 'Stop'

$logPath = Join-Path $env:TEMP 'PathAdderShellExt.log'

# ---------------------------------------------------------------------------
Write-Host '=== 步骤 1/4：清空旧日志 ===' -ForegroundColor Cyan
if (Test-Path -LiteralPath $logPath -PathType Leaf) {
    Remove-Item -LiteralPath $logPath -Force
    Write-Host ('已删除旧日志：' + $logPath) -ForegroundColor Gray
}
else {
    Write-Host '没有旧日志。' -ForegroundColor Gray
}

# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '=== 步骤 2/4：编译并注册（内部会调用 register-com.ps1）===' -ForegroundColor Cyan
& (Join-Path $PSScriptRoot 'register-com.ps1')
if ($LASTEXITCODE -ne 0) {
    Write-Host ('register-com.ps1 失败，退出码 ' + $LASTEXITCODE) -ForegroundColor Red
    exit $LASTEXITCODE
}

# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '=== 步骤 3/4：重启资源管理器 ===' -ForegroundColor Cyan

if ($NoRestart) {
    Write-Host '你选择了 -NoRestart，请自己执行：' -ForegroundColor Yellow
    Write-Host '    Stop-Process -Name explorer -Force; Start-Process explorer.exe' -ForegroundColor Gray
}
else {
    Write-Host '即将重启资源管理器（文件夹窗口会关闭）。' -ForegroundColor Yellow
    $null = Read-Host '按回车继续，或按 Ctrl+C 取消'
    Get-Process explorer -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Seconds 2
    Start-Process explorer.exe
    Start-Sleep -Seconds 3
    Write-Host '资源管理器已重启。' -ForegroundColor Green
}

# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '=== 步骤 4/4：实测并查看日志 ===' -ForegroundColor Cyan
Write-Host ''
Write-Host '请现在打开任意文件夹，右键一个文件 →「显示更多选项」' -ForegroundColor White
Write-Host '把鼠标【悬停】在「PATH 助手」上一两秒，然后按回车查看日志。' -ForegroundColor White
Write-Host ''
$null = Read-Host '测完后按回车'

Write-Host ''
Write-Host ('日志路径：' + $logPath) -ForegroundColor Gray
Write-Host ''

if (Test-Path -LiteralPath $logPath -PathType Leaf) {
    $lines = Get-Content -LiteralPath $logPath
    Write-Host ('共 ' + $lines.Count + ' 条：') -ForegroundColor Green
    Write-Host '------------------------------------------' -ForegroundColor Gray
    $lines | ForEach-Object { Write-Host ('  ' + $_) }
    Write-Host '------------------------------------------' -ForegroundColor Gray
    Write-Host ''

    $hasCtor = ($lines | Where-Object { $_ -like '*PathAdderCommand 构造*' }).Count -gt 0
    $hasEnum = ($lines | Where-Object { $_ -like '*EnumSubCommands 被调用*' }).Count -gt 0
    $hasNext = ($lines | Where-Object { $_ -like '*SubCommandEnum.Next*' }).Count -gt 0

    Write-Host '自动判读：' -ForegroundColor Cyan
    if (-not $hasCtor) {
        Write-Host '  【情况 A】explorer 从未创建 COM 对象 —— handler 被忽略。' -ForegroundColor Red
        Write-Host '     检查：*\shell\PathAdder 的 ExplorerCommandHandler 是否写对、CLSID 是否已注册。' -ForegroundColor Yellow
    }
    elseif (-not $hasEnum) {
        Write-Host '  【情况 B】对象创建了，但 explorer 没调用 EnumSubCommands。' -ForegroundColor Red
        Write-Host '     说明它没把本项当作级联父项（GetFlags 可能没被采纳）。' -ForegroundColor Yellow
    }
    elseif (-not $hasNext) {
        Write-Host '  【情况 C】枚举器返回了，但 explorer 没调用 Next。' -ForegroundColor Red
        Write-Host '     多半是 IEnumExplorerCommand 的 COM 编组（marshaling）失败。' -ForegroundColor Yellow
    }
    else {
        Write-Host '  【正常】explorer 完整走通了构造 → GetFlags → EnumSubCommands → Next。' -ForegroundColor Green
        Write-Host '     若仍看不到子菜单，问题在 Explorer 渲染层而非本 DLL。' -ForegroundColor Yellow
    }
}
else {
    Write-Host '没有任何日志 —— explorer 完全没有加载这个 DLL（情况 A）。' -ForegroundColor Red
}

Write-Host ''
Write-Host '排查完想回到可用的「点击弹出」模式，运行：' -ForegroundColor Gray
Write-Host '    .\restore-menu.ps1' -ForegroundColor Gray
Write-Host ''
exit 0
