# -----------------------------------------------------------------------------
# PathAdder.ps1 - 右键菜单调用的入口脚本（核心引擎）
#
# 用法（由右键菜单或命令行调用）：
#   powershell.exe -ExecutionPolicy Bypass -NoProfile -WindowStyle Hidden -File
#       "…\PathAdder.ps1" -Action Add    -Scope User   -Target "%V"
#       "…\PathAdder.ps1" -Action Add    -Scope System -Target "%V"
#       "…\PathAdder.ps1" -Action Remove -Scope All    -Target "%V"
#       "…\PathAdder.ps1" -Action OpenManager
#       "…\PathAdder.ps1" -Action Restore -Scope System -BackupFile "system-20261002-070000.txt"
#
# 运行环境：Windows PowerShell 5.1（不使用 PS7 专有语法）
# -----------------------------------------------------------------------------

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('Add', 'Remove', 'Restore', 'OpenManager')]
    [string]$Action = 'Add',

    [Parameter(Position = 1)]
    [ValidateSet('User', 'System', 'All')]
    [string]$Scope = 'User',

    [Parameter(Position = 2)]
    [string]$Target = '',

    [Parameter()]
    [string]$BackupFile = '',

    [Parameter()]
    [switch]$Elevated
)

$ErrorActionPreference = 'Stop'

# -----------------------------------------------------------------------------
# 初始化
# -----------------------------------------------------------------------------

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

# -----------------------------------------------------------------------------
# 辅助函数
# -----------------------------------------------------------------------------

<#
.SYNOPSIS
    返回作用范围的中文名称。
#>
function Get-ScopeLabelText {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScopeName
    )

    if ($ScopeName -eq 'System') {
        return '系统 PATH（所有用户）'
    }
    return '用户 PATH（当前用户）'
}

<#
.SYNOPSIS
    根据操作结果生成面向用户的消息文本。
#>
function Get-OperationMessage {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ActionName,

        [Parameter(Mandatory = $true)]
        [string]$ScopeName,

        [Parameter(Mandatory = $false)]
        $Result
    )

    $scopeLabel = Get-ScopeLabelText -ScopeName $ScopeName

    if ($null -eq $Result) {
        return '【' + $scopeLabel + '】未执行。'
    }

    $line = ''
    $status = [string]$Result.Status

    if ($status -eq 'Added') {
        $line = '已成功添加到【' + $scopeLabel + '】。'
    } elseif ($status -eq 'AlreadyExists') {
        $line = '该目录已存在于【' + $scopeLabel + '】中，未做修改。'
    } elseif ($status -eq 'Removed') {
        $line = '已成功从【' + $scopeLabel + '】中移除。'
    } elseif ($status -eq 'NotFound') {
        $line = '该目录不在【' + $scopeLabel + '】中，未做修改。'
    } elseif ($status -eq 'Failed') {
        $line = '操作【' + $scopeLabel + '】失败：' + $Result.Message
    } else {
        $line = '【' + $scopeLabel + '】状态未知：' + $Result.Message
    }

    if (-not [string]::IsNullOrEmpty($Result.BackupFile)) {
        $line = $line + "`r`n备份文件：" + $Result.BackupFile
    }

    return $line
}

<#
.SYNOPSIS
    执行单一作用范围的 Add / Remove。
#>
function Invoke-SingleScopeOperation {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Add', 'Remove')]
        [string]$ActionName,

        [Parameter(Mandatory = $true)]
        [ValidateSet('User', 'System')]
        [string]$ScopeName,

        [Parameter(Mandatory = $true)]
        [string]$Directory
    )

    if ($ActionName -eq 'Add') {
        return (Add-DirectoryToPath -Scope $ScopeName -Directory $Directory)
    }

    return (Remove-DirectoryFromPath -Scope $ScopeName -Directory $Directory)
}

<#
.SYNOPSIS
    统一退出：显示消息并返回退出码。
#>
function Exit-WithMessage {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [string]$Icon = 'Information',

        [Parameter(Mandatory = $false)]
        [int]$ExitCode = 0
    )

    Show-PathAdderMessageBox -Message $Message -Icon $Icon
    exit $ExitCode
}

# -----------------------------------------------------------------------------
# 分支一：打开 PATH 管理器
# -----------------------------------------------------------------------------

if ($Action -eq 'OpenManager') {
    $managerPath = Join-Path $script:ScriptRoot 'PathManager.ps1'
    if (-not (Test-Path -LiteralPath $managerPath -PathType Leaf)) {
        Exit-WithMessage -Message ('未找到 PATH 管理器脚本：' + "`r`n" + $managerPath) -Icon 'Error' -ExitCode 1
    }

    $started = Start-PathAdderScript -ScriptPath $managerPath
    if (-not $started) {
        Exit-WithMessage -Message ('启动 PATH 管理器失败：' + "`r`n" + $managerPath) -Icon 'Error' -ExitCode 1
    }

    exit 0
}

# -----------------------------------------------------------------------------
# 分支二：恢复备份
# -----------------------------------------------------------------------------

if ($Action -eq 'Restore') {
    if ([string]::IsNullOrWhiteSpace($BackupFile)) {
        Exit-WithMessage -Message '恢复备份时缺少 -BackupFile 参数，操作已取消。' -Icon 'Error' -ExitCode 1
    }

    $restoreScope = $Scope
    if ($restoreScope -eq 'All') {
        $restoreScope = 'User'
    }

    if ($restoreScope -eq 'System' -and -not (Test-PathAdderAdministrator)) {
        if ($Elevated) {
            Exit-WithMessage -Message ('仍未获得管理员权限，无法恢复【系统 PATH】。' + "`r`n`r`n" +
                '备份文件：' + $BackupFile + "`r`n" +
                '系统 PATH 未被修改。') -Icon 'Warning' -ExitCode 1
        }

        $ok = Invoke-SelfElevation -ScriptPath $script:MainScriptPath -ArgumentList @(
            '-Action', 'Restore',
            '-Scope', 'System',
            '-BackupFile', $BackupFile,
            '-Elevated'
        )

        if ($ok) {
            Exit-WithMessage -Message ('已请求管理员权限以恢复【系统 PATH】。' + "`r`n`r`n" +
                '备份文件：' + $BackupFile + "`r`n`r`n" +
                '请在 UAC 提示中点击“是”，随后会弹出恢复结果。') -Icon 'Information' -ExitCode 0
        }

        Exit-WithMessage -Message ('恢复【系统 PATH】需要管理员权限，但提权失败或已被取消。' + "`r`n`r`n" +
            '备份文件：' + $BackupFile + "`r`n" +
            '系统 PATH 未被修改。') -Icon 'Warning' -ExitCode 1
    }

    try {
        $restoreResult = Restore-PathBackup -BackupFileName $BackupFile
    } catch {
        Exit-WithMessage -Message ('恢复失败，PATH 未被修改。' + "`r`n`r`n" +
            '备份文件：' + $BackupFile + "`r`n" +
            '错误信息：' + $_.Exception.Message) -Icon 'Error' -ExitCode 1
    }

    $scopeLabel = Get-ScopeLabelText -ScopeName $restoreResult.Scope
    Exit-WithMessage -Message ('已恢复【' + $scopeLabel + '】。' + "`r`n`r`n" +
        '恢复自备份：' + $restoreResult.RestoredFrom + "`r`n" +
        '本次恢复前的 PATH 已备份为：' + $restoreResult.BackupFile + "`r`n`r`n" +
        '新打开的命令行窗口将使用恢复后的 PATH。') -Icon 'Information' -ExitCode 0
}

# -----------------------------------------------------------------------------
# 分支三：Add / Remove
# -----------------------------------------------------------------------------

# 3.1 解析目标目录
#     Remove 允许目标已不存在（-AllowMissing）：PATH 里的历史残留条目往往对应的目录
#     早已删除，若还要求“必须存在”，用户就永远无法把它清掉。
#     Add 保持严格：目标必须是真实存在的文件或目录。
$directory = ''
if ($Action -eq 'Remove') {
    $directory = Resolve-TargetDirectory -Target $Target -AllowMissing
} else {
    $directory = Resolve-TargetDirectory -Target $Target
}

if ([string]::IsNullOrWhiteSpace($directory)) {
    $reason = '请确认该文件或目录存在，并使用完整的绝对路径（例如 D:\Tools\bin\myapp.exe）。'
    if ($Action -eq 'Remove') {
        $reason = '移除操作允许目标已不存在，但仍需提供完整的绝对路径（例如 D:\Tools\bin）。'
    }
    Exit-WithMessage -Message ('无法解析目标文件或目录：' + "`r`n" + $Target + "`r`n`r`n" +
        $reason + "`r`n" + 'PATH 未被修改。') -Icon 'Error' -ExitCode 1
}

# 3.2 仅系统级：需要管理员，先自提权（提权后由子进程完成全部工作并弹窗）
if ($Scope -eq 'System' -and -not (Test-PathAdderAdministrator)) {
    if ($Elevated) {
        Exit-WithMessage -Message ('仍未获得管理员权限，无法修改【系统 PATH】。' + "`r`n`r`n" +
            '目录：' + $directory + "`r`n`r`n" +
            '请让管理员账户执行此操作，或改用“添加到 PATH（当前用户）”。' + "`r`n" +
            '系统 PATH 未被修改。') -Icon 'Warning' -ExitCode 1
    }

    $elevated = Invoke-SelfElevation -ScriptPath $script:MainScriptPath -ArgumentList @(
        '-Action', $Action,
        '-Scope', 'System',
        '-Target', $directory,
        '-Elevated'
    )

    if ($elevated) {
        # 提权进程会自行弹窗，这里静默退出
        exit 0
    }

    $verb = '添加'
    if ($Action -eq 'Remove') {
        $verb = '移除'
    }

    Exit-WithMessage -Message ('需要管理员权限才能' + $verb + '【系统 PATH】，但提权失败或你在 UAC 提示中选择了“否”。' + "`r`n`r`n" +
        '目录：' + $directory + "`r`n`r`n" +
        '系统 PATH 未被修改。如需免管理员操作，请使用“添加到 PATH（当前用户）”。') -Icon 'Warning' -ExitCode 1
}

# 3.3 用户级 / 系统级（已具备权限）
if ($Scope -ne 'All') {
    try {
        $result = Invoke-SingleScopeOperation -ActionName $Action -ScopeName $Scope -Directory $directory
    } catch {
        Exit-WithMessage -Message ('操作失败，PATH 未被修改。' + "`r`n`r`n" +
            '目录：' + $directory + "`r`n" +
            '错误信息：' + $_.Exception.Message) -Icon 'Error' -ExitCode 1
    }

    $head = ''
    if ($result.Status -eq 'Added' -or $result.Status -eq 'Removed') {
        $head = '操作成功。'
    } elseif ($result.Status -eq 'AlreadyExists' -or $result.Status -eq 'NotFound') {
        $head = '无需修改。'
    } else {
        $head = '操作未完成。'
    }

    $icon = 'Information'
    $exitCode = 0
    if ($result.Status -eq 'Failed') {
        $icon = 'Error'
        $exitCode = 1
    }

    $tail = ''
    if ($result.Status -eq 'Added' -or $result.Status -eq 'Removed') {
        $tail = "`r`n`r`n" + '新打开的命令行窗口（cmd / PowerShell）即可生效；已打开的窗口需重启。'
    }

    Exit-WithMessage -Message ($head + "`r`n`r`n" +
        '目录：' + $directory + "`r`n`r`n" +
        (Get-OperationMessage -ActionName $Action -ScopeName $Scope -Result $result) +
        $tail) -Icon $icon -ExitCode $exitCode
}

# 3.4 Both（All）：先做免管理员的用户级，再处理系统级
$userResult = $null
try {
    $userResult = Invoke-SingleScopeOperation -ActionName $Action -ScopeName 'User' -Directory $directory
} catch {
    $userResult = New-Object PSObject -Property @{
        Status     = 'Failed'
        Directory  = $directory
        BackupFile = ''
        Message    = $_.Exception.Message
    }
}

$systemNote = ''
$systemResult = $null

if (Test-PathAdderAdministrator) {
    try {
        $systemResult = Invoke-SingleScopeOperation -ActionName $Action -ScopeName 'System' -Directory $directory
    } catch {
        $systemResult = New-Object PSObject -Property @{
            Status     = 'Failed'
            Directory  = $directory
            BackupFile = ''
            Message    = $_.Exception.Message
        }
    }
} elseif ($Elevated) {
    $systemNote = "`r`n" + '（未获得管理员权限，【系统 PATH】未处理。）'
} else {
    $ok = Invoke-SelfElevation -ScriptPath $script:MainScriptPath -ArgumentList @(
        '-Action', $Action,
        '-Scope', 'System',
        '-Target', $directory,
        '-Elevated'
    )

    if ($ok) {
        $systemNote = "`r`n" + '（已请求管理员权限处理【系统 PATH】，请在 UAC 提示中点击“是”，随后会有单独的结果提示。）'
    } else {
        $systemNote = "`r`n" + '（【系统 PATH】需要管理员权限，提权失败或已被取消，未作改动。）'
    }
}

$combinedMessage = '目录：' + $directory + "`r`n`r`n" +
    (Get-OperationMessage -ActionName $Action -ScopeName 'User' -Result $userResult) + "`r`n"

if ($null -ne $systemResult) {
    $combinedMessage = $combinedMessage + "`r`n" + (Get-OperationMessage -ActionName $Action -ScopeName 'System' -Result $systemResult)
} else {
    $combinedMessage = $combinedMessage + $systemNote
}

$allOk = $true
if ($userResult.Status -eq 'Failed') {
    $allOk = $false
}
if ($null -ne $systemResult -and $systemResult.Status -eq 'Failed') {
    $allOk = $false
}

$icon = 'Information'
$exitCode = 0
if (-not $allOk) {
    $icon = 'Error'
    $exitCode = 1
}

$combinedMessage = $combinedMessage + "`r`n`r`n" + '新打开的命令行窗口即可生效；已打开的窗口需重启。'

Exit-WithMessage -Message $combinedMessage -Icon $icon -ExitCode $exitCode
