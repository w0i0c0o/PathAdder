<#
.SYNOPSIS
    PATH 助手 —— 右键菜单的操作面板。

.DESCRIPTION
    为什么不用 Windows 原生的 SubCommands 静态级联？

    SubCommands 是 Windows Vista/7 引入的机制：父项写 SubCommands（分号分隔的
    子命令表），子命令挂在 …\父项\shell\<子命令名>\command 下，鼠标悬停时由
    Explorer 自动展开。它在 Windows 7/10 上工作良好，但在 Windows 11 上存在
    明显缺陷 —— 父菜单项能被显示出来，鼠标悬停却完全不展开，且因为父项按约定
    不能带 command，点击也没有任何反应。

    根因：Windows 11 引入了新的上下文菜单管线，传统注册表 verb 由
    "ExplorerCommand verb" 包装器统一呈现，该包装器对 SubCommands 的静态级联
    支持不完整；机器上安装的第三方 IExplorerCommand 扩展越多，失效越明显。

    因此改为本方案：父菜单项带 command，点击后在**光标位置**弹出一个原生
    WinForms ContextMenuStrip。视觉与交互和原生右键子菜单几乎一致，且完全不
    依赖 Explorer 的级联实现，100% 可靠。代价是需要"点击"而非"悬停"。

.PARAMETER Target
    被右键的文件完整路径（由 Explorer 通过 %V 传入）。本脚本会取其所在目录
    作为操作对象。

.EXAMPLE
    powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden `
        -File ".\MenuPicker.ps1" -Target "D:\tools\app.exe"
#>

[CmdletBinding()]
param(
    [string]$Target = ''
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# 1. 依赖检查
# ---------------------------------------------------------------------------
try {
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
    Add-Type -AssemblyName System.Drawing -ErrorAction Stop
}
catch {
    Write-Error ('无法加载 Windows.Forms 组件，PATH 助手菜单无法启动：' + $_.Exception.Message)
    exit 1
}

$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Definition
$enginePath = Join-Path $scriptDirectory 'PathAdder.ps1'

if (-not (Test-Path -LiteralPath $enginePath -PathType Leaf)) {
    [void][System.Windows.Forms.MessageBox]::Show(
        ('找不到 PathAdder.ps1，脚本已移动或损坏。' + [Environment]::NewLine + [Environment]::NewLine +
         '期望位置：' + $enginePath),
        'PATH 助手',
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error)
    exit 1
}

# 当前解释器路径（Explorer 用 powershell.exe -File 启动本脚本，取其自身路径最稳）
$powerShellExe = ''
try {
    $powerShellExe = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
}
catch {
    $powerShellExe = ''
}
if ([string]::IsNullOrWhiteSpace($powerShellExe)) {
    $command = Get-Command -Name 'powershell.exe' -ErrorAction SilentlyContinue
    if ($null -ne $command) { $powerShellExe = $command.Source } else { $powerShellExe = 'powershell.exe' }
}

# ---------------------------------------------------------------------------
# 2. 菜单项定义
#    与 lib\ShellMenu.ps1 中的动词定义保持一一对应（仅表达方式不同）
# ---------------------------------------------------------------------------
# 计算要操作的目录，用作菜单顶部不可点的说明行
$targetDirectory = ''
if (-not [string]::IsNullOrWhiteSpace($Target)) {
    $directory = ''
    if (Test-Path -LiteralPath $Target -PathType Leaf) {
        $directory = [System.IO.Path]::GetDirectoryName($Target)
    }
    elseif (Test-Path -LiteralPath $Target -PathType Container) {
        $directory = $Target
    }
    else {
        try { $directory = [System.IO.Path]::GetDirectoryName($Target) } catch { $directory = '' }
    }
    if ([string]::IsNullOrWhiteSpace($directory)) { $directory = $Target }

    if ($directory.Length -gt 52) {
        $targetDirectory = $directory.Substring(0, 49) + '...'
    }
    else {
        $targetDirectory = $directory
    }
}

$menuSpecifications = @(
    [PSCustomObject] @{
        Label      = '添加到 PATH（当前用户）'
        Args       = @('-Action', 'Add', '-Scope', 'User')
        WithTarget = $true
    },
    [PSCustomObject] @{
        Label      = '添加到 PATH（系统全局，管理员）'
        Args       = @('-Action', 'Add', '-Scope', 'System')
        WithTarget = $true
    },
    [PSCustomObject] @{
        Label      = '从 PATH 中移除此目录'
        Args       = @('-Action', 'Remove', '-Scope', 'All')
        WithTarget = $true
    },
    [PSCustomObject] @{
        Label      = '打开 PATH 管理器'
        Args       = @('-Action', 'OpenManager')
        WithTarget = $false
    }
)

# ---------------------------------------------------------------------------
# 3. 构建菜单
# ---------------------------------------------------------------------------
$selectedSpecification = $null

$ownerForm = New-Object System.Windows.Forms.Form
$ownerForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
$ownerForm.ShowInTaskbar = $false
$ownerForm.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
$ownerForm.Size = New-Object System.Drawing.Size(1, 1)
$ownerForm.Location = New-Object System.Drawing.Point(-32000, -32000)
$ownerForm.Opacity = 0.01

$contextMenu = New-Object System.Windows.Forms.ContextMenuStrip
$contextMenu.ShowImageMargin = $false
$contextMenu.AutoSize = $true
try {
    $contextMenu.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9, [System.Drawing.FontStyle]::Regular)
}
catch {
    # 字体缺失时用系统默认字体，不影响功能
}

# 顶部说明行：让用户确认将要操作的是哪个目录
if ($targetDirectory -ne '') {
    $headerItem = New-Object System.Windows.Forms.ToolStripMenuItem
    $headerItem.Text = $targetDirectory
    $headerItem.Enabled = $false
    $headerItem.ForeColor = [System.Drawing.Color]::Gray
    [void]$contextMenu.Items.Add($headerItem)
    [void]$contextMenu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
}

$clickHandler = {
    param($sender, $eventArgs)
    $script:selectedSpecification = $sender.Tag
    $contextMenu.Close()
}

$index = 0
foreach ($specification in $menuSpecifications) {
    # 在三项 PATH 操作之后插入分隔线，与「打开 PATH 管理器」区分开
    if ($index -eq 3) {
        [void]$contextMenu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
    }

    $item = New-Object System.Windows.Forms.ToolStripMenuItem
    $item.Text = $specification.Label
    $item.Tag = $specification
    $item.add_Click($clickHandler)
    [void]$contextMenu.Items.Add($item)
    $index++
}

# 菜单关闭（选中、按 ESC、点击外部）→ 一并关闭宿主窗体，使 ShowDialog 返回
$contextMenu.add_Closed({
        param($sender, $eventArgs)
        $ownerForm.Close()
    })

$ownerForm.add_Shown({
        $contextMenu.Show(
            [System.Windows.Forms.Cursor]::Position,
            [System.Windows.Forms.ToolStripDropDownDirection]::BelowRight)
    })

# ---------------------------------------------------------------------------
# 4. 显示菜单（阻塞在此，直到菜单关闭）
# ---------------------------------------------------------------------------
try {
    [void]$ownerForm.ShowDialog()
}
catch {
    Write-Error ('菜单显示失败：' + $_.Exception.Message)
}

try { $ownerForm.Dispose() } catch { }
try { $contextMenu.Dispose() } catch { }

# 用户按 ESC 或点击菜单外部 → 什么都不做
if ($null -eq $selectedSpecification) {
    exit 0
}

# ---------------------------------------------------------------------------
# 5. 转交 PathAdder.ps1 执行真正的动作
# ---------------------------------------------------------------------------
$invokeArguments = @($selectedSpecification.Args)
if ($selectedSpecification.WithTarget -and (-not [string]::IsNullOrWhiteSpace($Target))) {
    $invokeArguments += @('-Target', $Target)
}

try {
    & $powerShellExe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File $enginePath @invokeArguments
    exit $LASTEXITCODE
}
catch {
    [void][System.Windows.Forms.MessageBox]::Show(
        ('执行失败：' + $_.Exception.Message),
        'PATH 助手',
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error)
    exit 1
}
