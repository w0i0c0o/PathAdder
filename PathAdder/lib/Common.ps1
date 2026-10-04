# -----------------------------------------------------------------------------
# PathAdder - 公共函数库（lib\Common.ps1）
#
# 目标运行环境：Windows PowerShell 5.1（同时兼容 3.0+）
# 严禁使用 PowerShell 7 专有语法（?? / && / || / 三元运算符 / $PSStyle 等）。
#
# 提供能力：
#   1. 应用数据目录 / 备份目录 / 日志文件路径
#   2. 注册表 PATH 读写（保持原有 REG_EXPAND_SZ / REG_SZ 类型）
#   3. PATH 条目归一化与健壮去重比较
#   4. 修改前自动备份 + 变更日志
#   5. 备份恢复
#   6. 管理员检测与 UAC 自提权
#   7. WM_SETTINGCHANGE 环境变更广播
#   8. WinForms 消息框
#
# 设计原则：先备份再修改；失败要恢复或明确提示；绝不静默破坏已有 PATH。
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# 0. 原生方法（P/Invoke）
# -----------------------------------------------------------------------------

<#
.SYNOPSIS
    初始化 P/Invoke 原生方法（SendMessageTimeout / GetLongPathName）。
.DESCRIPTION
    编译失败（例如没有 C# 编译器）时不会抛异常，仅把 $script:PathAdderNativeReady
    置为 $false，调用方会自动降级为“不广播 / 不转换长路径”，保证功能不中断。
#>
function Initialize-PathAdderNativeMethods {
    if ($script:PathAdderNativeReady) {
        return
    }
    $script:PathAdderNativeReady = $false

    if ('PathAdder.NativeMethods' -as [type]) {
        $script:PathAdderNativeReady = $true
        return
    }

    $source = @'
using System;
using System.Runtime.InteropServices;
using System.Text;

namespace PathAdder
{
    public static class NativeMethods
    {
        [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
        public static extern IntPtr SendMessageTimeout(
            IntPtr hWnd,
            uint Msg,
            UIntPtr wParam,
            string lParam,
            uint fuFlags,
            uint uTimeout,
            out UIntPtr lpdwResult);

        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Auto)]
        public static extern int GetLongPathName(
            string shortPath,
            StringBuilder longPath,
            int bufferSize);
    }
}
'@

    try {
        Add-Type -TypeDefinition $source -ErrorAction Stop
        $script:PathAdderNativeReady = $true
    } catch {
        $script:PathAdderNativeReady = $false
    }
}

if (-not $script:PathAdderNativeReady) {
    $script:PathAdderNativeReady = $false
}

# -----------------------------------------------------------------------------
# 1. 路径与目录
# -----------------------------------------------------------------------------

<#
.SYNOPSIS
    获取本机 Windows PowerShell 5.1 的完整路径（powershell.exe）。
.DESCRIPTION
    优先使用 %WINDIR%\System32\WindowsPowerShell\v1.0\powershell.exe（32/64 位系统
    均存在），找不到时退化为 PATH 中第一个 powershell.exe。
#>
function Get-SystemPowerShellPath {
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
    获取 PathAdder 的应用数据根目录：%LOCALAPPDATA%\PathAdder
#>
function Get-PathAdderAppDataRoot {
    $root = $env:LOCALAPPDATA
    if ([string]::IsNullOrWhiteSpace($root)) {
        $root = Join-Path $env:USERPROFILE 'AppData\Local'
    }

    $target = Join-Path $root 'PathAdder'
    if (-not (Test-Path -LiteralPath $target)) {
        New-Item -Path $target -ItemType Directory -Force | Out-Null
    }
    return $target
}

<#
.SYNOPSIS
    获取备份目录：%LOCALAPPDATA%\PathAdder\backups（不存在则创建）
#>
function Get-PathAdderBackupDirectory {
    $dir = Join-Path (Get-PathAdderAppDataRoot) 'backups'
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -Path $dir -ItemType Directory -Force | Out-Null
    }
    return $dir
}

<#
.SYNOPSIS
    获取变更日志文件路径：%LOCALAPPDATA%\PathAdder\change.log
#>
function Get-PathAdderLogFilePath {
    $root = Get-PathAdderAppDataRoot
    return (Join-Path $root 'change.log')
}

<#
.SYNOPSIS
    把可能的 8.3 短路径还原为长路径（用于兼容右键菜单传入 %1 的旧行为）。
#>
function ConvertTo-LongPath {
    param(
        [Parameter(Mandatory = $false)]
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $Path
    }

    Initialize-PathAdderNativeMethods
    if (-not $script:PathAdderNativeReady) {
        return $Path
    }

    try {
        $buffer = New-Object System.Text.StringBuilder(4096)
        $length = [PathAdder.NativeMethods]::GetLongPathName($Path, $buffer, $buffer.Capacity)
        if ($length -gt 0 -and $length -lt $buffer.Capacity) {
            return $buffer.ToString()
        }
    } catch {
        # 降级：原样返回
    }

    return $Path
}

<#
.SYNOPSIS
    把右键菜单传入的参数（文件或目录）解析为“所在目录”的绝对路径。
.DESCRIPTION
    处理顺序：去成对引号 -> 展开 $env:XXX / %XXX% -> 还原 8.3 短路径 ->
    校验真绝对路径 -> 校验真实存在 -> 如果是文件则取其所在目录。

    安全约束：默认要求目标**真实存在**且是**真绝对路径**。
    缺失任一条件都返回空字符串，由调用方给出明确报错并退出——这可以阻止
    '...'、'.'、'C:' 之类的参数被解析成脚本当前工作目录后误加入 PATH。

    例外：-AllowMissing 用于 **Remove（清理）** 场景。PATH 里的历史残留条目往往
    对应的目录早已被删除，此时如果还要求“必须存在”，用户就永远无法把它清掉，
    而弹窗却提示“请确认该文件仍然存在”——对 Remove 来说这是完全错误的引导。
    该开关只放行存在性检查，绝对路径/垃圾输入校验依旧严格。
.OUTPUTS
    成功返回规范化目录；失败返回空字符串。
#>
function Resolve-TargetDirectory {
    param(
        [Parameter(Mandatory = $false)]
        [string]$Target,

        [Parameter(Mandatory = $false)]
        [switch]$AllowMissing
    )

    if ([string]::IsNullOrWhiteSpace($Target)) {
        return ''
    }

    # -RequireAbsolute：要求真绝对路径，并拦截纯点/斜杠与盘符相对写法
    $fullPath = ConvertTo-CanonicalDirectory -Path $Target -RequireAbsolute
    if ([string]::IsNullOrWhiteSpace($fullPath)) {
        return ''
    }

    # 目标存在：是目录则原样返回；是文件（如右键点击的 .exe）则返回其所在目录
    if (Test-Path -LiteralPath $fullPath -PathType Container) {
        return $fullPath
    }

    if (Test-Path -LiteralPath $fullPath -PathType Leaf) {
        return (Format-PathAdderDirectory -Path ([System.IO.Path]::GetDirectoryName($fullPath)))
    }

    # 目标不存在
    if ($AllowMissing) {
        # Remove 场景：清理已消失的历史残留条目。无法区分它原本是文件还是目录，
        # 按“指向某个目录”处理，这正是清理场景的典型用法。
        return $fullPath
    }

    return ''
}

<#
.SYNOPSIS
    把任意写法的目录参数规范化为绝对路径。
.DESCRIPTION
    处理：去首尾空白 -> 去成对引号（双引号与单引号）-> 展开 $env:XXX 与 %XXX% ->
    还原 8.3 短路径 -> 取绝对路径 -> 去尾部反斜杠（盘符根目录除外）。
    不要求目录真实存在（移除一个历史遗留 PATH 条目时需要）。

    加 -RequireAbsolute 时额外要求输入为绝对路径，并拦截“仅由空白/点/斜杠组成”
    的垃圾输入——这类字符串经 GetFullPath 会被解析成**当前工作目录**，若不拦截就有
    可能把脚本的 CWD 误加进 PATH。
#>
function ConvertTo-CanonicalDirectory {
    param(
        [Parameter(Mandatory = $false)]
        [string]$Path,

        [Parameter(Mandatory = $false)]
        [switch]$RequireAbsolute
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return ''
    }

    $result = $Path.Trim()

    # 1) 剥离成对引号：同时支持双引号与单引号（可嵌套一层以上）
    $stripping = $true
    while ($stripping) {
        $stripping = $false
        if ($result.Length -ge 2 -and $result.StartsWith('"') -and $result.EndsWith('"')) {
            $result = $result.Substring(1, $result.Length - 2).Trim()
            $stripping = $true
        }
        if ($result.Length -ge 2 -and $result.StartsWith("'") -and $result.EndsWith("'")) {
            $result = $result.Substring(1, $result.Length - 2).Trim()
            $stripping = $true
        }
    }

    # 清理可能残留的单个游离双引号（注意：不清理单引号，避免破坏路径内的撇号）
    $result = $result.Trim('"').Trim()

    if ([string]::IsNullOrWhiteSpace($result)) {
        return ''
    }

    # 2) 垃圾输入防护：仅由 空白 / . / / / \ 组成时 GetFullPath 会解析成当前目录，必须拦截
    if (($result -replace '[\s./\\]', '') -eq '') {
        return ''
    }

    # 3) 展开 PowerShell 风格的 $env:XXX（例如 $env:LOCALAPPDATA\tools）
    try {
        $result = [regex]::Replace($result, '\$env:(\w+)', {
            param($match)
            $name = $match.Groups[1].Value
            $value = [System.Environment]::GetEnvironmentVariable($name)
            if ($null -eq $value) { $match.Value } else { $value }
        })
    } catch {
        # 展开失败则原样使用
    }

    # 4) 展开 Windows 风格的 %XXX%
    try {
        $result = [System.Environment]::ExpandEnvironmentVariables($result)
    } catch {
        # 展开失败则原样使用
    }

    # 5) 还原可能的 8.3 短路径
    $result = ConvertTo-LongPath -Path $result

    if ([string]::IsNullOrWhiteSpace($result)) {
        return ''
    }

    # 6) 绝对路径校验（可选，用于 Add 这类绝不希望牵扯 CWD 的场景）
    if ($RequireAbsolute) {
        # 注意：不能直接用 IsPathRooted()。它把盘符相对写法 "C:" / "C:win" 也算作
        # rooted，而 GetFullPath 会把这类路径按“该驱动器上的当前目录”展开，结果依赖
        # 进程 CWD —— 与我们要杜绝的 "..." 解析成 CWD 是同一类问题。
        # 这里只承认两种真正与 CWD 无关的形式：
        #   · 驱动器 + 分隔符：C:\ 或 C:/
        #   · UNC：\\server\share
        $trulyRooted = $false
        if ($result -match '^[A-Za-z]:[\\/]') {
            $trulyRooted = $true
        } elseif ($result -match '^\\\\') {
            $trulyRooted = $true
        }

        if (-not $trulyRooted) {
            return ''
        }
    }

    try {
        $result = [System.IO.Path]::GetFullPath($result)
    } catch {
        return ''
    }

    return (Format-PathAdderDirectory -Path $result)
}

<#
.SYNOPSIS
    统一目录格式：去掉尾部反斜杠（盘符根目录除外）。
#>
function Format-PathAdderDirectory {
    param(
        [Parameter(Mandatory = $false)]
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return ''
    }

    $result = $Path.Trim()
    if ($result -match '^[A-Za-z]:\\$') {
        return $result
    }

    return $result.TrimEnd('\')
}

# -----------------------------------------------------------------------------
# 2. PATH 归一化与比较
# -----------------------------------------------------------------------------

<#
.SYNOPSIS
    把 PATH 字符串按分号拆分为条目数组（丢弃空白条目）。
#>
function Split-PathList {
    param(
        [Parameter(Mandatory = $false)]
        [string]$Value
    )

    $list = @()
    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $list
    }

    foreach ($part in ($Value -split ';')) {
        if (-not [string]::IsNullOrWhiteSpace($part)) {
            $list += $part
        }
    }

    return $list
}

<#
.SYNOPSIS
    归一化路径用于比较：去引号 -> 展开环境变量 -> 统一分隔符 -> 去尾部反斜杠 -> 小写。
#>
function ConvertTo-NormalizedPath {
    param(
        [Parameter(Mandatory = $false)]
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return ''
    }

    $result = $Path.Trim()
    $result = $result.Trim().Trim('"').Trim()

    try {
        $result = [System.Environment]::ExpandEnvironmentVariables($result)
    } catch {
        # 展开失败则原样使用
    }

    $result = $result.Trim().Trim('"').Trim()
    $result = $result.Replace('/', '\')

    if ($result -match '^[A-Za-z]:\\$') {
        return $result.ToLowerInvariant()
    }

    return $result.TrimEnd('\').ToLowerInvariant()
}

<#
.SYNOPSIS
    判断目录是否已存在于 PATH 条目列表中（健壮去重比较）。
#>
function Test-PathInList {
    param(
        [Parameter(Mandatory = $false)]
        [string[]]$Entries,

        [Parameter(Mandatory = $false)]
        [string]$Directory
    )

    $target = ConvertTo-NormalizedPath -Path $Directory
    if ([string]::IsNullOrWhiteSpace($target)) {
        return $false
    }

    foreach ($entry in $Entries) {
        $current = ConvertTo-NormalizedPath -Path $entry
        if ($current -eq $target) {
            return $true
        }
    }

    return $false
}

# -----------------------------------------------------------------------------
# 3. 注册表 PATH 读写（保持原有值类型）
# -----------------------------------------------------------------------------

<#
.SYNOPSIS
    把各种写法的值类型名规范化为注册表真实使用的名称。
.DESCRIPTION
    易错点：Microsoft.Win32.RegistryValueKind 的成员名是 ExpandString 而不是
    ExpandSz；在 PowerShell 5.1 中写 ::ExpandSz 不会报错，而是静默返回 $null，
    导致 SetValue 的 3 参数重载解析失败。这里统一做映射，杜绝该问题。

    本工具只处理**字符串型** PATH。对 Unknown/None 采用 REG_EXPAND_SZ 作为新建值
    的默认类型（Windows 惯例）；对 Binary/DWord/QWord 或任何未知名称，不静默兜底，
    而是显式告警后再回退，避免过度自信地写坏数值型注册表值。
#>
function ConvertTo-RegistryValueKindName {
    param(
        [Parameter(Mandatory = $false)]
        [string]$KindName = ''
    )

    if ([string]::IsNullOrWhiteSpace($KindName)) {
        # 未指定类型：按 Windows 惯例，PATH 新建为 REG_EXPAND_SZ
        return 'ExpandString'
    }

    switch ($KindName) {
        'Unknown'      { return 'ExpandString' }   # 值尚不存在，同上按惯例新建
        'None'         { return 'ExpandString' }   # 同上
        'String'       { return 'String' }
        'ExpandString' { return 'ExpandString' }
        'ExpandSz'     { return 'ExpandString' }   # 兼容历史日志中的旧写法
        'MultiString'  { return 'MultiString' }
        default {
            Write-Warning ('PATH 值类型为未知或非字符串型「' + $KindName + '」，本工具只处理字符串型。已回退为 ExpandString，请人工确认 PATH 内容无误后再继续使用。')
            return 'ExpandString'
        }
    }
}

<#
.SYNOPSIS
    把值类型名安全地转换为 Microsoft.Win32.RegistryValueKind 枚举值。
#>
function ConvertTo-RegistryValueKind {
    param(
        [Parameter(Mandatory = $false)]
        [string]$KindName = ''
    )

    $canonical = ConvertTo-RegistryValueKindName -KindName $KindName
    return [System.Enum]::Parse([Microsoft.Win32.RegistryValueKind], $canonical)
}

<#
.SYNOPSIS
    根据作用范围返回注册表子键相对路径。
#>
function Get-PathAdderRegistrySubKeyPath {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('User', 'System')]
        [string]$Scope
    )

    if ($Scope -eq 'User') {
        return 'Environment'
    }

    return 'SYSTEM\CurrentControlSet\Control\Session Manager\Environment'
}

<#
.SYNOPSIS
    打开 PATH 所在的注册表键。
#>
function Open-PathAdderRegistryKey {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('User', 'System')]
        [string]$Scope,

        [Parameter(Mandatory = $false)]
        [switch]$Writable
    )

    $subKeyPath = Get-PathAdderRegistrySubKeyPath -Scope $Scope

    if ($Scope -eq 'User') {
        if ($Writable) {
            return [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($subKeyPath, $true)
        }
        return [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($subKeyPath, $false)
    }

    if ($Writable) {
        return [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($subKeyPath, $true)
    }
    return [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($subKeyPath, $false)
}

<#
.SYNOPSIS
    读取指定作用范围的 PATH，返回包含 Value / Kind / Exists 的对象。
.DESCRIPTION
    易错点：Path 可能是 REG_EXPAND_SZ，也可能是 REG_SZ，甚至不存在。
    这里同时读取值（GetValue）与类型（GetValueKind），写回时原样保持类型。
#>
function Get-EnvironmentPathInfo {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('User', 'System')]
        [string]$Scope
    )

    $result = New-Object PSObject -Property @{
        Scope   = $Scope
        Exists  = $false
        Value   = ''
        Kind    = 'Unknown'
        Error   = ''
        Entries = @()
    }

    $key = $null
    try {
        $key = Open-PathAdderRegistryKey -Scope $Scope
    } catch {
        $result.Error = $_.Exception.Message
        return $result
    }

    if ($null -eq $key) {
        $result.Error = '无法打开注册表键（不存在或无读取权限）。'
        return $result
    }

    try {
        $value = $key.GetValue('Path', $null)
        if ($null -ne $value) {
            $result.Exists = $true
            $result.Value = [string]$value
        }

        try {
            $kind = $key.GetValueKind('Path')
            if ($null -ne $kind) {
                $result.Kind = $kind.ToString()
            }
        } catch {
            # 值不存在时 GetValueKind 会抛异常，保持 Unknown
            $result.Kind = 'Unknown'
        }

        # 规范化：Unknown / None 时回退到 REG_EXPAND_SZ（Windows 上 Path 最常见的类型）
        $result.Kind = ConvertTo-RegistryValueKindName -KindName $result.Kind

        $result.Entries = @(Split-PathList -Value $result.Value)
    } finally {
        $key.Close()
    }

    return $result
}

<#
.SYNOPSIS
    写入指定作用范围的 PATH，并保持原有值类型。
#>
function Set-EnvironmentPathValue {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('User', 'System')]
        [string]$Scope,

        [Parameter(Mandatory = $true)]
        [string]$Value,

        [Parameter(Mandatory = $false)]
        [string]$Kind = 'ExpandString'
    )

    $key = $null
    try {
        $key = Open-PathAdderRegistryKey -Scope $Scope -Writable
    } catch {
        throw ('打开注册表写入失败（需要管理员权限？）：' + $_.Exception.Message)
    }

    if ($null -eq $key) {
        throw ('打开注册表写入失败：无法获取 ' + $Scope + ' 级 Environment 键的可写句柄。')
    }

    try {
        $valueKind = ConvertTo-RegistryValueKind -KindName $Kind
        $key.SetValue('Path', $Value, $valueKind)
    } finally {
        $key.Close()
    }
}

# -----------------------------------------------------------------------------
# 4. 备份与日志
# -----------------------------------------------------------------------------

<#
.SYNOPSIS
    追加一行变更日志。
.DESCRIPTION
    日志行格式（人可读且可解析）：
    [yyyy-MM-dd HH:mm:ss] 动作=Add 范围=User 目录=D:\bin 备份=user-20261002-070000.txt 类型=ExpandString
#>
function Write-PathAdderLog {
    param(
        [Parameter(Mandatory = $false)]
        [string]$Scope = '-',

        [Parameter(Mandatory = $false)]
        [string]$Action = '-',

        [Parameter(Mandatory = $false)]
        [string]$Directory = '-',

        [Parameter(Mandatory = $false)]
        [string]$BackupFile = '-',

        [Parameter(Mandatory = $false)]
        [string]$Kind = '-'
    )

    $logFile = Get-PathAdderLogFilePath
    $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = '[' + $stamp + '] 动作=' + $Action +
            ' 范围=' + $Scope +
            ' 目录=' + $Directory +
            ' 备份=' + $BackupFile +
            ' 类型=' + $Kind

    try {
        Add-Content -LiteralPath $logFile -Value $line -Encoding UTF8 -ErrorAction Stop
    } catch {
        # 日志失败不应阻断主流程
    }
}

<#
.SYNOPSIS
    在修改 PATH 之前备份当前 PATH 值，并记录日志。
.OUTPUTS
    包含 FileName / FullPath 的对象。
#>
function Backup-EnvironmentPath {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('User', 'System')]
        [string]$Scope,

        [Parameter(Mandatory = $false)]
        [string]$Action = 'Unknown',

        [Parameter(Mandatory = $false)]
        [string]$Directory = '-',

        [Parameter(Mandatory = $false)]
        [string]$CurrentValue = '',

        [Parameter(Mandatory = $false)]
        [string]$Kind = 'ExpandString'
    )

    $backupDir = Get-PathAdderBackupDirectory
    $prefix = $Scope.ToLowerInvariant()
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'

    $fileName = $prefix + '-' + $stamp + '.txt'
    $fullPath = Join-Path $backupDir $fileName
    $index = 1
    while (Test-Path -LiteralPath $fullPath) {
        $fileName = $prefix + '-' + $stamp + '-' + $index + '.txt'
        $fullPath = Join-Path $backupDir $fileName
        $index = $index + 1
    }

    $content = ''
    if ($null -ne $CurrentValue) {
        $content = [string]$CurrentValue
    }

    Set-Content -LiteralPath $fullPath -Value $content -Encoding UTF8 -ErrorAction Stop

    Write-PathAdderLog -Scope $Scope -Action $Action -Directory $Directory -BackupFile $fileName -Kind $Kind

    return New-Object PSObject -Property @{
        FileName = $fileName
        FullPath = $fullPath
    }
}

<#
.SYNOPSIS
    从变更日志中查找某次备份对应的 PATH 值类型（用于恢复时保持类型）。
#>
function Get-BackupKindFromLog {
    param(
        [Parameter(Mandatory = $false)]
        [string]$BackupFileName
    )

    if ([string]::IsNullOrWhiteSpace($BackupFileName)) {
        return ''
    }

    $logFile = Get-PathAdderLogFilePath
    if (-not (Test-Path -LiteralPath $logFile)) {
        return ''
    }

    $pattern = '备份=' + [regex]::Escape($BackupFileName) + '\s+类型=(\S+)'
    $lines = @(Get-Content -LiteralPath $logFile -Encoding UTF8 -ErrorAction SilentlyContinue)

    for ($i = $lines.Count - 1; $i -ge 0; $i--) {
        if ($lines[$i] -match $pattern) {
            return $matches[1]
        }
    }

    return ''
}

<#
.SYNOPSIS
    列出所有备份文件（按修改时间倒序）。
#>
function Get-PathAdderBackups {
    $dir = Get-PathAdderBackupDirectory
    $files = @(Get-ChildItem -LiteralPath $dir -Filter '*.txt' -File -ErrorAction SilentlyContinue |
        Sort-Object -Property LastWriteTime -Descending)

    $items = @()
    foreach ($file in $files) {
        $scopeKey = 'User'
        $scopeLabel = '用户'
        if ($file.Name.ToLowerInvariant().StartsWith('system-')) {
            $scopeKey = 'System'
            $scopeLabel = '系统'
        }

        $items += New-Object PSObject -Property @{
            FileName      = $file.Name
            FullPath      = $file.FullName
            Scope         = $scopeKey
            ScopeLabel    = $scopeLabel
            LastWriteTime = $file.LastWriteTime
            Length        = $file.Length
        }
    }

    return $items
}

<#
.SYNOPSIS
    恢复到某次备份。
.DESCRIPTION
    “恢复”同样是一次修改，因此会先把当前 PATH 再备份一次，然后覆盖写入。
#>
function Restore-PathBackup {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BackupFileName
    )

    $backupDir = Get-PathAdderBackupDirectory
    $fullPath = Join-Path $backupDir $BackupFileName
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        throw ('备份文件不存在：' + $fullPath)
    }

    $scope = 'User'
    if ($BackupFileName.ToLowerInvariant().StartsWith('system-')) {
        $scope = 'System'
    }

    $content = ''
    $raw = Get-Content -LiteralPath $fullPath -Raw -Encoding UTF8 -ErrorAction Stop
    if ($null -ne $raw) {
        $content = ([string]$raw).TrimEnd([char[]]@([char]13, [char]10))
    }

    $kind = Get-BackupKindFromLog -BackupFileName $BackupFileName
    if ([string]::IsNullOrWhiteSpace($kind) -or $kind -eq 'Unknown') {
        $currentInfo = Get-EnvironmentPathInfo -Scope $scope
        $kind = $currentInfo.Kind
    }
    $kind = ConvertTo-RegistryValueKindName -KindName $kind

    # 恢复之前先备份当前值
    $currentInfo = Get-EnvironmentPathInfo -Scope $scope
    $backup = Backup-EnvironmentPath -Scope $scope -Action 'Restore' `
        -Directory ('恢复自 ' + $BackupFileName) `
        -CurrentValue $currentInfo.Value `
        -Kind $currentInfo.Kind

    Set-EnvironmentPathValue -Scope $scope -Value $content -Kind $kind
    Publish-EnvironmentChange -Scope $scope -Value $content

    return New-Object PSObject -Property @{
        Scope          = $scope
        RestoredFrom   = $BackupFileName
        BackupFile     = $backup.FileName
        RestoredValue  = $content
    }
}

# -----------------------------------------------------------------------------
# 5. 广播环境变更
# -----------------------------------------------------------------------------

<#
.SYNOPSIS
    更新当前进程环境变量，并向所有顶层窗口广播 WM_SETTINGCHANGE。
#>
function Publish-EnvironmentChange {
    param(
        [Parameter(Mandatory = $false)]
        [ValidateSet('User', 'System')]
        [string]$Scope = 'User',

        [Parameter(Mandatory = $false)]
        [string]$Value = ''
    )

    # 1) 更新【当前进程】的环境变量。
    #    注意：绝不能用 Environment.SetEnvironmentVariable(name, value, 'User'/'Machine')，
    #    该重载会【回写注册表】，并把 REG_EXPAND_SZ 悄悄改成 REG_SZ，破坏“保持原有值类型”
    #    这一要求。这里只用默认的 Process 目标（仅内存，不碰注册表）。
    $combined = ''
    try {
        $machine = [System.Environment]::GetEnvironmentVariable('Path', 'Machine')
        $user = [System.Environment]::GetEnvironmentVariable('Path', 'User')
        if ([string]::IsNullOrEmpty($machine)) {
            $combined = $user
        } elseif ([string]::IsNullOrEmpty($user)) {
            $combined = $machine
        } else {
            $combined = $machine + ';' + $user
        }
    } catch {
        $combined = ''
    }

    if ($combined -ne '') {
        try {
            [System.Environment]::SetEnvironmentVariable('Path', $combined)
            $env:Path = $combined
        } catch {
            # 忽略：仅影响当前进程
        }
    }

    # 3) 广播 WM_SETTINGCHANGE，让资源管理器/已打开程序感知
    Initialize-PathAdderNativeMethods
    if (-not $script:PathAdderNativeReady) {
        return
    }

    try {
        $hwndBroadcast = [IntPtr]0xffff
        $WM_SETTINGCHANGE = [uint32]0x001A
        $SMTO_ABORTIFHUNG = [uint32]0x0002
        $result = [UIntPtr]::Zero

        [void][PathAdder.NativeMethods]::SendMessageTimeout(
            $hwndBroadcast,
            $WM_SETTINGCHANGE,
            [UIntPtr]::Zero,
            'Environment',
            $SMTO_ABORTIFHUNG,
            [uint32]5000,
            [ref]$result)
    } catch {
        # 广播失败不影响注册表结果
    }
}

# -----------------------------------------------------------------------------
# 6. 管理员检测与 UAC 自提权
# -----------------------------------------------------------------------------

<#
.SYNOPSIS
    判断当前进程是否以管理员身份运行。
#>
function Test-PathAdderAdministrator {
    try {
        $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object System.Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        return $false
    }
}

<#
.SYNOPSIS
    以管理员身份重新启动指定脚本（触发 UAC 弹窗）。
.DESCRIPTION
    必须同时满足三个条件，缺一不可：
      1. UseShellExecute = $true —— 否则 Verb 会被忽略，根本不会提权；
      2. Verb = 'runas'          —— 这是真正触发 UAC 提权的开关；
      3. 进程通过 Start() 启动   —— 用户点“否”时抛 Win32Exception。
.OUTPUTS
    $true 表示已成功启动提权进程；$false 表示用户取消 UAC 或提权失败。
#>
function Invoke-SelfElevation {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptPath,

        [Parameter(Mandatory = $false)]
        [string[]]$ArgumentList = @()
    )

    $quotedArgs = New-Object System.Collections.ArrayList
    foreach ($arg in $ArgumentList) {
        $escaped = ([string]$arg) -replace '"', '\"'
        [void]$quotedArgs.Add('"' + $escaped + '"')
    }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = Get-SystemPowerShellPath
    $psi.Arguments = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $ScriptPath + '" ' + ($quotedArgs -join ' ')
    $psi.UseShellExecute = $true
    # 关键：Verb='runas' 才是触发 UAC 的开关。缺少这一行时，前面所有配置都只是
    # “以当前用户权限再开一个 powershell”，系统 PATH 写入依旧会被拒绝。
    $psi.Verb = 'runas'
    $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
    $psi.WorkingDirectory = (Split-Path -Parent $ScriptPath)

    try {
        [void][System.Diagnostics.Process]::Start($psi)
        return $true
    } catch {
        # 用户在 UAC 中点了“否”，或当前账户无法提权
        return $false
    }
}

<#
.SYNOPSIS
    以独立（隐藏控制台）进程启动指定 PowerShell 脚本。
#>
function Start-PathAdderScript {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptPath,

        [Parameter(Mandatory = $false)]
        [string[]]$ArgumentList = @()
    )

    $quotedArgs = New-Object System.Collections.ArrayList
    foreach ($arg in $ArgumentList) {
        $escaped = ([string]$arg) -replace '"', '\"'
        [void]$quotedArgs.Add('"' + $escaped + '"')
    }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = Get-SystemPowerShellPath
    $psi.Arguments = '-NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $ScriptPath + '" ' + ($quotedArgs -join ' ')
    $psi.UseShellExecute = $true
    $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
    $psi.WorkingDirectory = (Split-Path -Parent $ScriptPath)

    try {
        [void][System.Diagnostics.Process]::Start($psi)
        return $true
    } catch {
        return $false
    }
}

# -----------------------------------------------------------------------------
# 7. 消息框
# -----------------------------------------------------------------------------

<#
.SYNOPSIS
    弹出统一的 Windows 消息框（标题统一为“PATH 助手”）。
#>
function Show-PathAdderMessageBox {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [string]$Title = 'PATH 助手',

        [Parameter(Mandatory = $false)]
        [ValidateSet('Information', 'Warning', 'Error', 'Question')]
        [string]$Icon = 'Information'
    )

    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
    } catch {
        Write-Host ('[PATH 助手] ' + $Message)
        return
    }

    $iconType = [System.Windows.Forms.MessageBoxIcon]::Information
    if ($Icon -eq 'Warning') {
        $iconType = [System.Windows.Forms.MessageBoxIcon]::Warning
    } elseif ($Icon -eq 'Error') {
        $iconType = [System.Windows.Forms.MessageBoxIcon]::Error
    } elseif ($Icon -eq 'Question') {
        $iconType = [System.Windows.Forms.MessageBoxIcon]::Question
    }

    try {
        [void][System.Windows.Forms.MessageBox]::Show(
            $Message,
            $Title,
            [System.Windows.Forms.MessageBoxButtons]::OK,
            $iconType)
    } catch {
        Write-Host ('[PATH 助手] ' + $Message)
    }
}

# -----------------------------------------------------------------------------
# 8. PATH 修改操作
# -----------------------------------------------------------------------------

<#
.SYNOPSIS
    把目录添加到指定作用范围的 PATH。
.DESCRIPTION
    流程：读取 -> 判重（命中则直接返回 AlreadyExists，不写注册表、不备份）
    -> 备份 -> 写注册表（保持原类型）-> 广播。
.OUTPUTS
    包含 Status / Scope / Directory / BackupFile / Message 的对象。
#>
function Add-DirectoryToPath {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('User', 'System')]
        [string]$Scope,

        [Parameter(Mandatory = $true)]
        [string]$Directory
    )

    $result = New-Object PSObject -Property @{
        Status     = 'Failed'
        Scope      = $Scope
        Directory  = $Directory
        BackupFile = ''
        NewValue   = ''
        Message    = ''
    }

    if ([string]::IsNullOrWhiteSpace($Directory)) {
        $result.Message = '目录为空，无法添加。'
        return $result
    }

    # 规范化：去引号 -> 展开环境变量 -> 还原短名 -> 绝对路径 -> 去尾斜杠
    # -RequireAbsolute：拒绝相对路径与垃圾输入，绝不把当前工作目录牵扯进来
    $target = ConvertTo-CanonicalDirectory -Path $Directory -RequireAbsolute
    if ([string]::IsNullOrWhiteSpace($target)) {
        $result.Message = '目录路径无效（必须是一个可用的绝对路径）：' + $Directory
        return $result
    }
    $result.Directory = $target

    if (-not (Test-Path -LiteralPath $target -PathType Container)) {
        $result.Message = '目录不存在：' + $target
        return $result
    }

    $info = Get-EnvironmentPathInfo -Scope $Scope
    if (-not [string]::IsNullOrEmpty($info.Error)) {
        $result.Message = '读取 PATH 失败：' + $info.Error
        return $result
    }

    if (Test-PathInList -Entries $info.Entries -Directory $target) {
        $result.Status = 'AlreadyExists'
        $result.Message = '该目录已存在于 PATH 中，未做修改。'
        return $result
    }

    $newValue = ''
    if ([string]::IsNullOrWhiteSpace($info.Value)) {
        $newValue = $target
    } else {
        $newValue = $info.Value.TrimEnd(';') + ';' + $target
    }

    $backup = Backup-EnvironmentPath -Scope $Scope -Action 'Add' -Directory $target `
        -CurrentValue $info.Value -Kind $info.Kind
    $result.BackupFile = $backup.FileName

    try {
        Set-EnvironmentPathValue -Scope $Scope -Value $newValue -Kind $info.Kind
    } catch {
        $result.Status = 'Failed'
        $result.Message = '写入 PATH 失败（已保留备份 ' + $backup.FileName + '）：' + $_.Exception.Message
        Write-PathAdderLog -Scope $Scope -Action 'AddFailed' -Directory $target -BackupFile $backup.FileName -Kind $info.Kind
        return $result
    }

    Publish-EnvironmentChange -Scope $Scope -Value $newValue

    $result.Status = 'Added'
    $result.NewValue = $newValue
    $result.Message = '已添加到 PATH。'
    return $result
}

<#
.SYNOPSIS
    把目录从指定作用范围的 PATH 中移除。
.OUTPUTS
    包含 Status / Scope / Directory / BackupFile / Message 的对象。
#>
function Remove-DirectoryFromPath {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('User', 'System')]
        [string]$Scope,

        [Parameter(Mandatory = $true)]
        [string]$Directory
    )

    $result = New-Object PSObject -Property @{
        Status     = 'Failed'
        Scope      = $Scope
        Directory  = $Directory
        BackupFile = ''
        NewValue   = ''
        Message    = ''
    }

    if ([string]::IsNullOrWhiteSpace($Directory)) {
        $result.Message = '目录为空，无法移除。'
        return $result
    }

    # 与 Add 保持一致的规范化（移除时允许目录已不存在）
    # -RequireAbsolute 同样生效：盘符相对写法 "C:" 会被按 CWD 展开，若放行，一次
    # 右键“移除”就可能静默删掉一个合法的 PATH 条目，属于不可接受的破坏。
    $target = ConvertTo-CanonicalDirectory -Path $Directory -RequireAbsolute
    if ([string]::IsNullOrWhiteSpace($target)) {
        $result.Message = '目录路径无效（必须是一个绝对路径）：' + $Directory
        return $result
    }
    $result.Directory = $target

    $info = Get-EnvironmentPathInfo -Scope $Scope
    if (-not [string]::IsNullOrEmpty($info.Error)) {
        $result.Message = '读取 PATH 失败：' + $info.Error
        return $result
    }

    $targetNormalized = ConvertTo-NormalizedPath -Path $target

    $kept = New-Object System.Collections.ArrayList
    $removed = $false
    foreach ($entry in $info.Entries) {
        $entryNormalized = ConvertTo-NormalizedPath -Path $entry
        if ($entryNormalized -eq $targetNormalized) {
            $removed = $true
            continue
        }
        [void]$kept.Add($entry)
    }

    if (-not $removed) {
        $result.Status = 'NotFound'
        $result.Message = '该目录不在 PATH 中，未做修改。'
        return $result
    }

    $newValue = [string]::Join(';', ($kept.ToArray()))

    $backup = Backup-EnvironmentPath -Scope $Scope -Action 'Remove' -Directory $target `
        -CurrentValue $info.Value -Kind $info.Kind
    $result.BackupFile = $backup.FileName

    try {
        Set-EnvironmentPathValue -Scope $Scope -Value $newValue -Kind $info.Kind
    } catch {
        $result.Status = 'Failed'
        $result.Message = '写入 PATH 失败（已保留备份 ' + $backup.FileName + '）：' + $_.Exception.Message
        Write-PathAdderLog -Scope $Scope -Action 'RemoveFailed' -Directory $target -BackupFile $backup.FileName -Kind $info.Kind
        return $result
    }

    Publish-EnvironmentChange -Scope $Scope -Value $newValue

    $result.Status = 'Removed'
    $result.NewValue = $newValue
    $result.Message = '已从 PATH 中移除。'
    return $result
}
