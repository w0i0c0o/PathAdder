# -----------------------------------------------------------------------------
# install.ps1 - 注册右键菜单（用户级 HKCU，无需管理员）
#
# 用法：
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "…\install.ps1"
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "…\install.ps1" -RestartExplorer
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "…\install.ps1" -NoRestart
#
# 幂等：重复运行不会报错，只会覆盖已有键值。
#
# 注册位置（单一位置，覆盖所有文件类型）：
#   HKCU\Software\Classes\*\shell\PathAdder
#         (Default)/MUIVerb/Icon/SubCommands/NoWorkingDirectory
#         └─ shell\PathAdder.AddUser   -> 添加到 PATH（当前用户）
#            shell\PathAdder.AddSystem -> 添加到 PATH（系统全局，管理员）
#            shell\PathAdder.Remove    -> 从 PATH 中移除此目录
#            shell\PathAdder.Manager   -> 打开 PATH 管理器
#
#   `*` 是 Windows 官方支持的「所有文件对象」关联键，覆盖任意扩展名（含 .exe）。
#   单点注册最干净：早期版本同时注册 exefile\shell 与 SystemFileAssociations\.exe\shell，
#   既重复又会在菜单里出现两份相同动作，已废弃（卸载时仍会清理历史残留）。
#
#   ⚠ 父项 PathAdder **绝不能**有 command 子键，否则 SubCommands 被忽略、级联退化成
#   「点了没反应」的普通菜单项。安装时已主动清除该残留。
#
# 关于 -RestartExplorer / -NoRestart：
#   默认：弹框**询问**是否立即重启资源管理器（默认按钮为「否」）。
#   原因：Windows 11 上 SHChangeNotify 通知并不总是生效，通常需要重启 explorer 才会
#   真正出现在右键菜单里；但重启会关闭所有已打开的文件夹窗口，因此**绝不能未经
#   询问直接重启**。
#     -RestartExplorer  不询问，直接重启（脚本化批量部署用）
#     -NoRestart        不询问也不重启（脚本化且不希望被打断时用）
#
# 关于 -MakeDefault（已废弃，保留参数仅为向后兼容）：
#   本版本**在任何位置都不写入默认动词**。`*\shell` 与 `exefile\shell` 的 (Default)
#   决定文件的双击行为，把它改成我们的菜单项会让用户双击文件时不再打开、而是弹窗改
#   PATH，属于灾难级破坏。指定该开关时只会打印一条说明，不做任何事。
# -----------------------------------------------------------------------------

[CmdletBinding()]
param(
    [Parameter()]
    [switch]$MakeDefault,

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

# -----------------------------------------------------------------------------
# 参数互斥校验
# -----------------------------------------------------------------------------

if ($RestartExplorer -and $NoRestart) {
    Show-PathAdderMessageBox -Message ('参数冲突：-RestartExplorer 与 -NoRestart 不能同时使用。' + "`r`n`r`n" +
        '请只指定其中一个，或都不指定（走询问模式）。') -Icon 'Error'
    exit 1
}

# -----------------------------------------------------------------------------
# 前置检查
# -----------------------------------------------------------------------------

$enginePath = Join-Path $script:ScriptRoot 'PathAdder.ps1'
$managerPath = Join-Path $script:ScriptRoot 'PathManager.ps1'

$missing = @()
if (-not (Test-Path -LiteralPath $enginePath -PathType Leaf)) { $missing += 'PathAdder.ps1' }
if (-not (Test-Path -LiteralPath $managerPath -PathType Leaf)) { $missing += 'PathManager.ps1' }
if ($missing.Count -gt 0) {
    $abortMessage = ('安装中止：缺少必要文件 ' + ($missing -join '、') + "`r`n`r`n" +
        '请确认这些文件与 install.ps1 位于同一目录。')
    Show-PathAdderMessageBox -Message $abortMessage -Icon 'Error'
    exit 1
}

$powershellPath = Get-SystemPowerShellPath

# -----------------------------------------------------------------------------
# 写入注册表
# -----------------------------------------------------------------------------

$installResult = $null

try {
    $installResult = Install-PathAdderShellMenu `
        -EnginePath $enginePath `
        -PowerShellPath $powershellPath `
        -ParentLabel (Get-PathAdderShellMenuParentLabel)
} catch {
    Show-PathAdderMessageBox -Message ('安装失败：' + $_.Exception.Message + "`r`n`r`n" +
        '系统右键菜单未被修改。') -Icon 'Error'
    exit 1
}

if (-not $installResult.Success) {
    $failureMessage = '安装失败：注册表写入未完成。' + "`r`n`r`n" +
        '系统右键菜单可能只被部分修改，请运行 uninstall.ps1 后重试。'
    Show-PathAdderMessageBox -Message $failureMessage -Icon 'Error'
    exit 1
}

# -----------------------------------------------------------------------------
# 通知资源管理器刷新（失败不阻断）
# -----------------------------------------------------------------------------

$refreshResult = Update-PathAdderShellAssociationCache

# -----------------------------------------------------------------------------
# 重启资源管理器（默认询问，绝不未经询问直接重启）
# -----------------------------------------------------------------------------

$restartResult = $null
$restartDeclined = $false

if ($NoRestart) {
    $restartDeclined = $true
} elseif ($RestartExplorer) {
    $restartResult = Restart-PathAdderExplorer
} else {
    $askMessage = 'PATH 助手已写入注册表。' + "`r`n`r`n" +
        '是否立即重启资源管理器，使右键菜单生效？' + "`r`n`r`n" +
        '注意：重启资源管理器会关闭所有已打开的文件夹窗口。' + "`r`n" +
        '（若你正在使用文件夹窗口，建议先选「否」，稍后自行重启。）'

    if (Show-PathAdderConfirmBox -Message $askMessage) {
        $restartResult = Restart-PathAdderExplorer
    } else {
        $restartDeclined = $true
    }
}

# -----------------------------------------------------------------------------
# 完成提示（「必须重启资源管理器」为首要信息，放在最前面）
# -----------------------------------------------------------------------------

$restartStatus = ''
if ($null -ne $restartResult) {
    if ($restartResult.Success) {
        $restartStatus = '资源管理器已重启，菜单现在应该可以看到了。'
    } else {
        $restartStatus = '重启资源管理器失败：' + $restartResult.Message
    }
} elseif ($restartDeclined) {
    $restartStatus = '尚未重启资源管理器 —— **这一步通常是必需的**。'
}

$message = 'PATH 助手已安装完成（注册表已写入）。' + "`r`n" +
    '==================================================' + "`r`n" +
    '【下一步：必须重启资源管理器，菜单才会出现】' + "`r`n" +
    '==================================================' + "`r`n" +
    '当前状态：' + $restartStatus + "`r`n`r`n" +
    '请二选一完成重启：' + "`r`n" +
    '  1) 手动执行（PowerShell）：' + "`r`n" +
    '     Stop-Process -Name explorer -Force; Start-Process explorer.exe' + "`r`n" +
    '  2) 注销当前 Windows 账户后重新登录' + "`r`n" +
    '  （SHChangeNotify 通知已发出，但 Windows 11 上它经常不足够，' + "`r`n" +
    '    实测必须重启 explorer 或注销重登才会真正生效。）' + "`r`n`r`n" +
    '==================================================' + "`r`n" +
    '【菜单在哪里】' + "`r`n" +
    '==================================================' + "`r`n" +
    '在任意文件（任意类型，含 .exe）上右键，菜单里会出现一项「PATH 助手」，' + "`r`n" +
    '把鼠标悬停或点开它，即可看到 4 个子项：' + "`r`n" +
    '  · 添加到 PATH（当前用户）' + "`r`n" +
    '  · 添加到 PATH（系统全局，管理员）' + "`r`n" +
    '  · 从 PATH 中移除此目录' + "`r`n" +
    '  · 打开 PATH 管理器' + "`r`n`r`n" +
    'Windows 11 的菜单是分层的，请按以下任一方式查看：' + "`r`n" +
    '  · 右键 →「显示更多选项」' + "`r`n" +
    '  · 选中文件后按 Shift+F10' + "`r`n" +
    '  · 选中文件后按 Shift+方向键' + "`r`n`r`n" +
    '==================================================' + "`r`n" +
    '【安装信息】' + "`r`n" +
    '==================================================' + "`r`n" +
    '注册位置（用户级，无需管理员）：' + "`r`n" +
    '  HKCU\' + $installResult.ParentSubKey + "`r`n" +
    '级联子命令：' + $installResult.SubCommands + "`r`n" +
    '刷新状态：' + $refreshResult.Message + "`r`n" +
    '备份目录：' + (Get-PathAdderBackupDirectory)

if ($MakeDefault) {
    $message = $message + "`r`n`r`n" +
        '提示：-MakeDefault 已废弃且未生效。本工具**在任何位置都不写入默认动词**——' +
        '那会改变文件的双击行为（双击不再打开、而是弹窗改 PATH）。'
}

Show-PathAdderMessageBox -Message $message -Icon 'Information'
exit 0
