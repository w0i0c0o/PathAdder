# -----------------------------------------------------------------------------
# uninstall.ps1 - 清除右键菜单（用户级 HKCU，无需管理员）
#
# 用法：
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "…\uninstall.ps1"
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "…\uninstall.ps1" -RestartExplorer
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "…\uninstall.ps1" -NoRestart
#
# 幂等：菜单项不存在时也不会报错，并提示「无需卸载」。
#
# 清理范围（当前位置 + **所有历史位置**，保证老版本升级不留孤儿菜单）：
#   1. HKCU\Software\Classes\*\shell\PathAdder                  （当前，整棵子树）
#   2. HKCU\Software\Classes\exefile\shell\PathAdder*           （历史扁平 verb ×4）
#   3. HKCU\Software\Classes\SystemFileAssociations\.exe\shell\PathAdder*（历史 ×4）
#   以及卸载后已变空的父键（只删空键）
#
#   绝不触碰：HKLM 的任何键、任何其他程序注册的菜单项、
#             `*\shell` / `exefile\shell` 的默认值（默认动词，决定双击行为）。
#
# 注意：卸载只删除右键菜单，不会删除 %LOCALAPPDATA%\PathAdder 下的备份与日志，
#       以便你在需要时仍能恢复 PATH。如需彻底清理，请手动删除该目录。
# -----------------------------------------------------------------------------

[CmdletBinding()]
param(
    [Parameter()]
    [switch]$RestartExplorer,

    [Parameter()]
    [switch]$NoRestart
)

$ErrorActionPreference = 'Stop'

$script:MainScriptPath = $PSCommandPath
if ([string]::IsNullOrWhiteSpace($script:MainScriptPath)) {
    $script:MainScriptPath = $MyInvocation.MyCommand.Path
}
$script:ScriptRoot = Split-Path -Parent $script:MainScriptPath

$script:LibraryPath = Join-Path $script:ScriptRoot 'lib\Common.ps1'
if (-not (Test-Path -LiteralPath $script:LibraryPath -PathType Leaf)) {
    Write-Error ('缺少公共函数库：' + $script:LibraryPath)
    exit 1
}
. $script:LibraryPath

$script:ShellMenuPath = Join-Path $script:ScriptRoot 'lib\ShellMenu.ps1'
if (-not (Test-Path -LiteralPath $script:ShellMenuPath -PathType Leaf)) {
    Write-Error ('缺少菜单注册库：' + $script:ShellMenuPath)
    exit 1
}
. $script:ShellMenuPath

try {
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
} catch {
    # 无 WinForms 时退化为控制台输出
}

if ($RestartExplorer -and $NoRestart) {
    Show-PathAdderMessageBox -Message ('参数冲突：-RestartExplorer 与 -NoRestart 不能同时使用。') -Icon 'Error'
    exit 1
}

# -----------------------------------------------------------------------------
# 执行卸载
# -----------------------------------------------------------------------------

$uninstallResult = $null

try {
    $uninstallResult = Uninstall-PathAdderShellMenu
} catch {
    Show-PathAdderMessageBox -Message ('卸载失败：' + $_.Exception.Message) -Icon 'Error'
    exit 1
}

# -----------------------------------------------------------------------------
# 通知刷新 + 询问是否重启资源管理器
# -----------------------------------------------------------------------------

$refreshResult = $null
$restartResult = $null
$restartDeclined = $false

if ($uninstallResult.RemovedCount -gt 0) {
    $refreshResult = Update-PathAdderShellAssociationCache

    if ($NoRestart) {
        $restartDeclined = $true
    } elseif ($RestartExplorer) {
        $restartResult = Restart-PathAdderExplorer
    } else {
        $askMessage = 'PATH 助手的右键菜单已移除。' + "`r`n`r`n" +
            '是否立即重启资源管理器，让菜单变化生效？' + "`r`n`r`n" +
            '注意：重启资源管理器会关闭所有已打开的文件夹窗口。'

        if (Show-PathAdderConfirmBox -Message $askMessage) {
            $restartResult = Restart-PathAdderExplorer
        } else {
            $restartDeclined = $true
        }
    }
} else {
    $restartDeclined = $true
}

# -----------------------------------------------------------------------------
# 结果提示
# -----------------------------------------------------------------------------

$message = ''

if ($uninstallResult.RemovedCount -gt 0) {
    $message = 'PATH 助手的右键菜单已移除。' + "`r`n" +
        '==================================================' + "`r`n" +
        '【下一步：建议重启资源管理器】' + "`r`n" +
        '==================================================' + "`r`n"
    if ($null -ne $restartResult) {
        if ($restartResult.Success) {
            $message = $message + '资源管理器已重启。' + "`r`n`r`n"
        } else {
            $message = $message + '重启失败：' + $restartResult.Message + "`r`n`r`n"
        }
    } elseif ($restartDeclined) {
        $message = $message + '尚未重启资源管理器。若要立即生效，请执行：' + "`r`n" +
            '  Stop-Process -Name explorer -Force; Start-Process explorer.exe' + "`r`n" +
            '或注销后重新登录。' + "`r`n`r`n"
    }

    $message = $message +
        '已清理的位置（共 ' + $uninstallResult.LocationsScanned.Count + ' 处扫描，' +
        '删除 ' + $uninstallResult.RemovedCount + ' 项）：' + "`r`n"
    foreach ($location in $uninstallResult.LocationsScanned) {
        $message = $message + '  · HKCU\' + $location + "`r`n"
    }
    $message = $message + "`r`n"
} else {
    $message = '未发现 PATH 助手的右键菜单项，无需卸载（重复运行不会报错）。' + "`r`n`r`n"
}

if ($uninstallResult.Failed.Count -gt 0) {
    $message = $message + '以下项删除失败：' + ($uninstallResult.Failed -join '、') + "`r`n`r`n"
}

if ($uninstallResult.PrunedEmptyKeys.Count -gt 0) {
    $message = $message + '已回收安装时创建的空键：' + "`r`n" +
        '  ' + ($uninstallResult.PrunedEmptyKeys -join "`r`n  ") + "`r`n`r`n"
}

if ($null -ne $refreshResult) {
    $message = $message + '刷新状态：' + $refreshResult.Message + "`r`n`r`n"
}

$message = $message +
    '已保留（未触碰）：系统原有的 open / runas / runasuser 菜单，' +
    '以及其他程序注册的右键菜单项。' + "`r`n" +
    '备份与日志保留在：' + "`r`n" + (Get-PathAdderAppDataRoot) + "`r`n`r`n" +
    '如需彻底清理，请手动删除上述目录。'

Show-PathAdderMessageBox -Message $message -Icon 'Information'
exit 0
