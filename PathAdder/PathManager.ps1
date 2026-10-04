# -----------------------------------------------------------------------------
# PathManager.ps1 - PATH 管理器（WinForms GUI）
#
# 功能：
#   · 展示当前【用户 PATH】与【系统 PATH】条目（带序号）
#   · 展示备份历史，支持「预览内容」与「恢复到此次备份」
#   · 展示变更日志（倒序最近 200 条）
#   · 提供「刷新」「打开备份目录」按钮
#
# 运行环境：Windows PowerShell 5.1（-STA 单线程单元，WinForms 必需）
# -----------------------------------------------------------------------------

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$script:MainScriptPath = $PSCommandPath
if ([string]::IsNullOrWhiteSpace($script:MainScriptPath)) {
    $script:MainScriptPath = $MyInvocation.MyCommand.Path
}
$script:ScriptRoot = Split-Path -Parent $script:MainScriptPath

$script:LibraryPath = Join-Path $script:ScriptRoot 'lib\Common.ps1'
if (-not (Test-Path -LiteralPath $script:LibraryPath -PathType Leaf)) {
    # 注意：此处尚未 dot-source lib\Common.ps1，Show-PathAdderMessageBox 还不存在，
    # 必须用 PowerShell 原生 Write-Error，否则会退化成“找不到命令”的难懂报错。
    Write-Error ('缺少公共函数库：' + $script:LibraryPath + '。请确认 lib\Common.ps1 与 PathManager.ps1 位于同一目录。')
    exit 1
}
. $script:LibraryPath

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# -----------------------------------------------------------------------------
# 字体与文本工具
# -----------------------------------------------------------------------------

<#
.SYNOPSIS
    从候选字体名中选择本机已安装的第一个，找不到则使用默认字体。
#>
function Get-AvailableFont {
    param(
        [Parameter(Mandatory = $false)]
        [string[]]$Candidates = @('Microsoft YaHei UI', 'Microsoft YaHei', 'SimSun'),

        [Parameter(Mandatory = $false)]
        [float]$Size = 9
    )

    try {
        $collection = New-Object System.Drawing.Text.InstalledFontCollection
        $installed = @{}
        foreach ($family in $collection.Families) {
            $installed[$family.Name] = $true
        }

        foreach ($name in $Candidates) {
            if ($installed.ContainsKey($name)) {
                return (New-Object System.Drawing.Font($name, $Size))
            }
        }
    } catch {
        # 退化到默认字体
    }

    return (New-Object System.Drawing.Font([System.Drawing.SystemFonts]::MessageBoxFont.FontFamily, $Size))
}

$script:UiFont = Get-AvailableFont -Candidates @('Microsoft YaHei UI', 'Microsoft YaHei', 'SimSun', 'Segoe UI') -Size 9
$script:MonoFont = Get-AvailableFont -Candidates @('Consolas', 'Courier New', 'Microsoft YaHei', 'SimSun') -Size 10

<#
.SYNOPSIS
    把 PATH 字符串格式化为带序号的多行文本。
#>
function Format-PathListText {
    param(
        [Parameter(Mandatory = $false)]
        [string]$Value
    )

    $entries = @(Split-PathList -Value $Value)
    if ($entries.Count -eq 0) {
        return '(该 PATH 为空)'
    }

    $builder = New-Object System.Text.StringBuilder
    for ($i = 0; $i -lt $entries.Count; $i++) {
        $number = ($i + 1).ToString().PadLeft(3, ' ')
        [void]$builder.AppendLine($number + '. ' + $entries[$i])
    }
    return $builder.ToString()
}

<#
.SYNOPSIS
    读取变更日志，返回倒序的最近 N 条文本行。
#>
function Get-ReversedLogLines {
    param(
        [Parameter(Mandatory = $false)]
        [int]$MaxCount = 200
    )

    $logFile = Get-PathAdderLogFilePath
    if (-not (Test-Path -LiteralPath $logFile -PathType Leaf)) {
        return @()
    }

    $lines = @(Get-Content -LiteralPath $logFile -Encoding UTF8 -ErrorAction SilentlyContinue |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

    if ($lines.Count -eq 0) {
        return @()
    }

    if ($lines.Count -gt $MaxCount) {
        $start = $lines.Count - $MaxCount
        $lines = $lines[$start..($lines.Count - 1)]
    }

    $reversed = New-Object System.Collections.ArrayList
    for ($i = $lines.Count - 1; $i -ge 0; $i--) {
        [void]$reversed.Add($lines[$i])
    }

    return $reversed.ToArray()
}

# -----------------------------------------------------------------------------
# 窗体构造
# -----------------------------------------------------------------------------

$script:form = New-Object System.Windows.Forms.Form
$form = $script:form
$form.Text = 'PATH 助手 - PATH 管理器'
$form.Size = New-Object System.Drawing.Size(1080, 720)
$form.MinimumSize = New-Object System.Drawing.Size(880, 560)
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
$form.Font = $script:UiFont

# --- 顶部面板 ---
$topPanel = New-Object System.Windows.Forms.Panel
$topPanel.Dock = [System.Windows.Forms.DockStyle]::Top
$topPanel.Height = 46
$topPanel.Padding = New-Object System.Windows.Forms.Padding(8, 6, 8, 6)

$buttonStrip = New-Object System.Windows.Forms.TableLayoutPanel
$buttonStrip.Dock = [System.Windows.Forms.DockStyle]::Right
$buttonStrip.ColumnCount = 4
$buttonStrip.RowCount = 1
$buttonStrip.AutoSize = $true
$buttonStrip.AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink
$buttonStrip.Margin = New-Object System.Windows.Forms.Padding(0)
[void]$buttonStrip.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 96)))
[void]$buttonStrip.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 150)))
[void]$buttonStrip.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 150)))
[void]$buttonStrip.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 96)))

function New-ManagerButton {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text,

        [Parameter(Mandatory = $false)]
        [int]$Width = 88
    )

    $button = New-Object System.Windows.Forms.Button
    $button.Text = $Text
    $button.Height = 28
    $button.Width = $Width
    $button.Dock = [System.Windows.Forms.DockStyle]::Fill
    $button.Margin = New-Object System.Windows.Forms.Padding(3, 3, 3, 3)
    $button.Font = $script:UiFont
    return $button
}

$btnRefresh = New-ManagerButton -Text '刷新' -Width 88
$btnOpenBackupDir = New-ManagerButton -Text '打开备份目录' -Width 142
$btnOpenLog = New-ManagerButton -Text '打开变更日志' -Width 142
$btnClose = New-ManagerButton -Text '关闭' -Width 88

[void]$buttonStrip.Controls.Add($btnRefresh, 0, 0)
[void]$buttonStrip.Controls.Add($btnOpenBackupDir, 1, 0)
[void]$buttonStrip.Controls.Add($btnOpenLog, 2, 0)
[void]$buttonStrip.Controls.Add($btnClose, 3, 0)

$lblHint = New-Object System.Windows.Forms.Label
$lblHint.Dock = [System.Windows.Forms.DockStyle]::Fill
$lblHint.Text = '提示：修改【系统 PATH】需要管理员权限；任何修改前都会自动备份，可随时在“备份历史”中恢复。'
$lblHint.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$lblHint.AutoEllipsis = $true
$lblHint.Font = $script:UiFont

[void]$topPanel.Controls.Add($lblHint)
[void]$topPanel.Controls.Add($buttonStrip)

# --- 底部状态栏 ---
$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Dock = [System.Windows.Forms.DockStyle]::Bottom
$statusLabel.Height = 26
$statusLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$statusLabel.Padding = New-Object System.Windows.Forms.Padding(8, 0, 0, 0)
$statusLabel.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$statusLabel.Font = $script:UiFont
$statusLabel.Text = '就绪'

# --- 主分割区 ---
# 关键点：SplitContainer 的默认 Size 只有 150x100。Panel1MinSize + Panel2MinSize
# 必须 <= 容器可用尺寸，否则 WinForms 在赋值 Panel2MinSize 时抛
# “SplitterDistance 必须在 Panel1MinSize 和 Width - Panel2MinSize 之间”，脚本直接崩溃。
# 因此必须在设置 MinSize **之前**先给控件一个足够大的显式 Size。
$splitMain = New-Object System.Windows.Forms.SplitContainer
$splitMain.Size = New-Object System.Drawing.Size(1080, 720)
$splitMain.Dock = [System.Windows.Forms.DockStyle]::Fill
$splitMain.Orientation = [System.Windows.Forms.Orientation]::Horizontal
$splitMain.Panel1MinSize = 140
$splitMain.Panel2MinSize = 180

$splitPaths = New-Object System.Windows.Forms.SplitContainer
$splitPaths.Size = New-Object System.Drawing.Size(1080, 340)
$splitPaths.Dock = [System.Windows.Forms.DockStyle]::Fill
$splitPaths.Orientation = [System.Windows.Forms.Orientation]::Vertical
$splitPaths.Panel1MinSize = 260
$splitPaths.Panel2MinSize = 260

function New-PathListGroup {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Title
    )

    $group = New-Object System.Windows.Forms.GroupBox
    $group.Text = $Title
    $group.Dock = [System.Windows.Forms.DockStyle]::Fill
    $group.Padding = New-Object System.Windows.Forms.Padding(6, 10, 6, 6)
    $group.Font = $script:UiFont

    $textBox = New-Object System.Windows.Forms.TextBox
    $textBox.Multiline = $true
    $textBox.ReadOnly = $true
    $textBox.WordWrap = $false
    $textBox.ScrollBars = [System.Windows.Forms.ScrollBars]::Both
    $textBox.Dock = [System.Windows.Forms.DockStyle]::Fill
    $textBox.BackColor = [System.Drawing.Color]::White
    $textBox.Font = $script:MonoFont
    $textBox.HideSelection = $false

    [void]$group.Controls.Add($textBox)

    return New-Object PSObject -Property @{
        Group   = $group
        TextBox = $textBox
    }
}

$userGroup = New-PathListGroup -Title '用户 PATH (HKCU\Environment)'
$systemGroup = New-PathListGroup -Title '系统 PATH (HKLM\...\Session Manager\Environment)'

[void]$splitPaths.Panel1.Controls.Add($userGroup.Group)
[void]$splitPaths.Panel2.Controls.Add($systemGroup.Group)
[void]$splitMain.Panel1.Controls.Add($splitPaths)

# --- 下方标签页 ---
$tabs = New-Object System.Windows.Forms.TabControl
$tabs.Dock = [System.Windows.Forms.DockStyle]::Fill
$tabs.Font = $script:UiFont

# 备份历史页
$tabBackups = New-Object System.Windows.Forms.TabPage
$tabBackups.Text = '备份历史'
$tabBackups.Padding = New-Object System.Windows.Forms.Padding(6)
$tabBackups.Font = $script:UiFont

$lvBackups = New-Object System.Windows.Forms.ListView
$lvBackups.Dock = [System.Windows.Forms.DockStyle]::Fill
$lvBackups.View = [System.Windows.Forms.View]::Details
$lvBackups.FullRowSelect = $true
$lvBackups.GridLines = $true
$lvBackups.HideSelection = $false
$lvBackups.MultiSelect = $false
$lvBackups.Font = $script:MonoFont
[void]$lvBackups.Columns.Add('备份文件', 260)
[void]$lvBackups.Columns.Add('范围', 70)
[void]$lvBackups.Columns.Add('时间', 170)
[void]$lvBackups.Columns.Add('大小(字节)', 110)
[void]$lvBackups.Columns.Add('完整路径', 520)

$backupButtonPanel = New-Object System.Windows.Forms.Panel
$backupButtonPanel.Dock = [System.Windows.Forms.DockStyle]::Bottom
$backupButtonPanel.Height = 44
$backupButtonPanel.Padding = New-Object System.Windows.Forms.Padding(6)

$backupFlow = New-Object System.Windows.Forms.FlowLayoutPanel
$backupFlow.Dock = [System.Windows.Forms.DockStyle]::Right
$backupFlow.FlowDirection = [System.Windows.Forms.FlowDirection]::LeftToRight
$backupFlow.WrapContents = $false
$backupFlow.AutoSize = $true
$backupFlow.AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink
$backupFlow.Margin = New-Object System.Windows.Forms.Padding(0)

function New-BackupButton {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text,

        [Parameter(Mandatory = $false)]
        [int]$Width = 150
    )

    $button = New-Object System.Windows.Forms.Button
    $button.Text = $Text
    $button.Width = $Width
    $button.Height = 28
    $button.Margin = New-Object System.Windows.Forms.Padding(4, 2, 0, 2)
    $button.Font = $script:UiFont
    return $button
}

$btnPreview = New-BackupButton -Text '预览内容' -Width 120
$btnRestore = New-BackupButton -Text '恢复到此次备份' -Width 150
$btnRefreshBackups = New-BackupButton -Text '刷新备份列表' -Width 130

[void]$backupFlow.Controls.Add($btnPreview)
[void]$backupFlow.Controls.Add($btnRestore)
[void]$backupFlow.Controls.Add($btnRefreshBackups)
[void]$backupButtonPanel.Controls.Add($backupFlow)

[void]$tabBackups.Controls.Add($lvBackups)
[void]$tabBackups.Controls.Add($backupButtonPanel)

# 变更日志页
$tabLog = New-Object System.Windows.Forms.TabPage
$tabLog.Text = '变更日志'
$tabLog.Padding = New-Object System.Windows.Forms.Padding(6)
$tabLog.Font = $script:UiFont

$logHeader = New-Object System.Windows.Forms.Label
$logHeader.Dock = [System.Windows.Forms.DockStyle]::Top
$logHeader.Height = 28
$logHeader.Text = '最近 200 条（倒序，最新在最上方）  日志格式：[时间] 动作=… 范围=… 目录=… 备份=… 类型=…'
$logHeader.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$logHeader.AutoEllipsis = $true
$logHeader.Font = $script:UiFont

$txtLog = New-Object System.Windows.Forms.TextBox
$txtLog.Multiline = $true
$txtLog.ReadOnly = $true
$txtLog.WordWrap = $false
$txtLog.ScrollBars = [System.Windows.Forms.ScrollBars]::Both
$txtLog.Dock = [System.Windows.Forms.DockStyle]::Fill
$txtLog.BackColor = [System.Drawing.Color]::White
$txtLog.Font = $script:MonoFont
$txtLog.HideSelection = $false

[void]$tabLog.Controls.Add($txtLog)
[void]$tabLog.Controls.Add($logHeader)

[void]$tabs.TabPages.Add($tabBackups)
[void]$tabs.TabPages.Add($tabLog)
[void]$splitMain.Panel2.Controls.Add($tabs)

[void]$form.Controls.Add($splitMain)
[void]$form.Controls.Add($statusLabel)
[void]$form.Controls.Add($topPanel)

# -----------------------------------------------------------------------------
# 数据加载
# -----------------------------------------------------------------------------

<#
.SYNOPSIS
    刷新 PATH 列表、备份列表与日志。
#>
function Refresh-ManagerData {
    $isAdmin = Test-PathAdderAdministrator

    $userInfo = Get-EnvironmentPathInfo -Scope 'User'
    $systemInfo = Get-EnvironmentPathInfo -Scope 'System'

    $userGroup.Group.Text = '用户 PATH (HKCU\Environment)  共 ' + @(Split-PathList -Value $userInfo.Value).Count + ' 项'
    $systemGroup.Group.Text = '系统 PATH (HKLM\...\Session Manager\Environment)  共 ' + @(Split-PathList -Value $systemInfo.Value).Count + ' 项'

    $userGroup.TextBox.Text = Format-PathListText -Value $userInfo.Value

    if (-not [string]::IsNullOrEmpty($systemInfo.Error)) {
        $systemGroup.TextBox.Text = '(读取失败：' + $systemInfo.Error + ')'
    } else {
        $systemGroup.TextBox.Text = Format-PathListText -Value $systemInfo.Value
    }

    # 备份列表
    $lvBackups.BeginUpdate()
    $lvBackups.Items.Clear()
    $backups = @(Get-PathAdderBackups)
    foreach ($item in $backups) {
        $lvItem = New-Object System.Windows.Forms.ListViewItem($item.FileName)
        [void]$lvItem.SubItems.Add($item.ScopeLabel)
        [void]$lvItem.SubItems.Add($item.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))
        [void]$lvItem.SubItems.Add($item.Length.ToString())
        [void]$lvItem.SubItems.Add($item.FullPath)
        $lvItem.Tag = $item
        [void]$lvBackups.Items.Add($lvItem)
    }
    $lvBackups.EndUpdate()

    # 日志
    $logLines = @(Get-ReversedLogLines -MaxCount 200)
    if ($logLines.Count -eq 0) {
        $txtLog.Text = '(暂无变更日志。执行过添加/移除/恢复操作后，这里会显示记录。)'
    } else {
        $txtLog.Text = [string]::Join([System.Environment]::NewLine, $logLines)
    }

    $adminText = '否'
    if ($isAdmin) {
        $adminText = '是'
    }

    $statusLabel.Text = '用户 PATH：' + @(Split-PathList -Value $userInfo.Value).Count + ' 项    |    ' +
        '系统 PATH：' + @(Split-PathList -Value $systemInfo.Value).Count + ' 项    |    ' +
        '备份：' + $backups.Count + ' 个    |    ' +
        '当前为管理员：' + $adminText + '    |    ' +
        '备份目录：' + (Get-PathAdderBackupDirectory)
}

<#
.SYNOPSIS
    弹出一个只读文本预览窗体。
#>
function Show-TextPreviewForm {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Title,

        [Parameter(Mandatory = $true)]
        [string]$Content
    )

    $previewForm = New-Object System.Windows.Forms.Form
    $previewForm.Text = $Title
    $previewForm.Size = New-Object System.Drawing.Size(820, 540)
    $previewForm.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterParent
    $previewForm.Font = $script:UiFont

    $previewBox = New-Object System.Windows.Forms.TextBox
    $previewBox.Multiline = $true
    $previewBox.ReadOnly = $true
    $previewBox.WordWrap = $false
    $previewBox.ScrollBars = [System.Windows.Forms.ScrollBars]::Both
    $previewBox.Dock = [System.Windows.Forms.DockStyle]::Fill
    $previewBox.Font = $script:MonoFont
    $previewBox.BackColor = [System.Drawing.Color]::White
    $previewBox.Text = $Content

    [void]$previewForm.Controls.Add($previewBox)
    [void]$previewForm.ShowDialog($script:form)
}

# -----------------------------------------------------------------------------
# 事件处理
# -----------------------------------------------------------------------------

$btnRefresh.Add_Click({
    try {
        Refresh-ManagerData
    } catch {
        [void][System.Windows.Forms.MessageBox]::Show($script:form,
            ('刷新失败：' + $_.Exception.Message),
            'PATH 助手',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error)
    }
})

$btnRefreshBackups.Add_Click({
    try {
        Refresh-ManagerData
    } catch {
        [void][System.Windows.Forms.MessageBox]::Show($script:form,
            ('刷新失败：' + $_.Exception.Message),
            'PATH 助手',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error)
    }
})

$btnOpenBackupDir.Add_Click({
    $dir = Get-PathAdderBackupDirectory
    try {
        Start-Process -FilePath 'explorer.exe' -ArgumentList ('"' + $dir + '"')
    } catch {
        [void][System.Windows.Forms.MessageBox]::Show($script:form,
            ('无法打开目录：' + $dir + "`r`n" + $_.Exception.Message),
            'PATH 助手',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error)
    }
})

$btnOpenLog.Add_Click({
    $logFile = Get-PathAdderLogFilePath
    if (-not (Test-Path -LiteralPath $logFile -PathType Leaf)) {
        [void][System.Windows.Forms.MessageBox]::Show($script:form,
            '暂无变更日志文件，执行过 PATH 修改后会自动生成。',
            'PATH 助手',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information)
        return
    }

    try {
        Start-Process -FilePath 'notepad.exe' -ArgumentList ('"' + $logFile + '"')
    } catch {
        [void][System.Windows.Forms.MessageBox]::Show($script:form,
            ('无法打开日志文件：' + $logFile),
            'PATH 助手',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error)
    }
})

$btnClose.Add_Click({
    $script:form.Close()
})

$btnPreview.Add_Click({
    if ($lvBackups.SelectedItems.Count -eq 0) {
        [void][System.Windows.Forms.MessageBox]::Show($script:form,
            '请先在列表中选中一条备份记录。',
            'PATH 助手',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information)
        return
    }

    $item = $lvBackups.SelectedItems[0].Tag
    $content = ''
    try {
        $raw = Get-Content -LiteralPath $item.FullPath -Raw -Encoding UTF8 -ErrorAction Stop
        if ($null -ne $raw) {
            $content = [string]$raw
        }
        if ([string]::IsNullOrWhiteSpace($content)) {
            $content = '(该备份内容为空，说明当时 PATH 为空值。)'
        }
    } catch {
        [void][System.Windows.Forms.MessageBox]::Show($script:form,
            ('读取备份失败：' + $_.Exception.Message),
            'PATH 助手',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error)
        return
    }

    Show-TextPreviewForm -Title ('备份预览 - ' + $item.FileName) -Content $content
})

$btnRestore.Add_Click({
    if ($lvBackups.SelectedItems.Count -eq 0) {
        [void][System.Windows.Forms.MessageBox]::Show($script:form,
            '请先在列表中选中一条备份记录。',
            'PATH 助手',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information)
        return
    }

    $item = $lvBackups.SelectedItems[0].Tag
    $scopeLabel = '用户 PATH'
    if ($item.Scope -eq 'System') {
        $scopeLabel = '系统 PATH'
    }

    $answer = [System.Windows.Forms.MessageBox]::Show($script:form,
        ('确定要把【' + $scopeLabel + '】恢复到备份 ' + $item.FileName + ' 吗？' + "`r`n`r`n" +
            '恢复前会先自动备份当前的 ' + $scopeLabel + '，然后用备份内容覆盖。' + "`r`n" +
            '时间：' + $item.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss') + "`r`n" +
            '大小：' + $item.Length + ' 字节'),
        'PATH 助手',
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question)

    if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) {
        return
    }

    if ($item.Scope -eq 'System' -and -not (Test-PathAdderAdministrator)) {
        $enginePath = Join-Path $script:ScriptRoot 'PathAdder.ps1'
        $ok = Invoke-SelfElevation -ScriptPath $enginePath -ArgumentList @(
            '-Action', 'Restore',
            '-Scope', 'System',
            '-BackupFile', $item.FileName,
            '-Elevated'
        )

        if ($ok) {
            [void][System.Windows.Forms.MessageBox]::Show($script:form,
                ('已请求管理员权限以恢复【系统 PATH】。' + "`r`n`r`n" +
                    '备份文件：' + $item.FileName + "`r`n`r`n" +
                    '请在 UAC 提示中点击“是”，随后会弹出恢复结果。完成后点击「刷新」查看最新状态。'),
                'PATH 助手',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information)
        } else {
            [void][System.Windows.Forms.MessageBox]::Show($script:form,
                ('恢复【系统 PATH】需要管理员权限，但提权失败或已被取消。' + "`r`n`r`n" +
                    '备份文件：' + $item.FileName + "`r`n" +
                    '系统 PATH 未被修改。'),
                'PATH 助手',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning)
        }
        return
    }

    try {
        $restoreResult = Restore-PathBackup -BackupFileName $item.FileName
        Refresh-ManagerData
        [void][System.Windows.Forms.MessageBox]::Show($script:form,
            ('已恢复【' + $scopeLabel + '】。' + "`r`n`r`n" +
                '恢复自：' + $restoreResult.RestoredFrom + "`r`n" +
                '恢复前的 PATH 已备份为：' + $restoreResult.BackupFile),
            'PATH 助手',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information)
    } catch {
        [void][System.Windows.Forms.MessageBox]::Show($script:form,
            ('恢复失败，PATH 未被修改。' + "`r`n`r`n" + '错误信息：' + $_.Exception.Message),
            'PATH 助手',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error)
    }
})

$lvBackups.Add_DoubleClick({
    if ($lvBackups.SelectedItems.Count -eq 0) {
        return
    }
    $btnPreview.PerformClick()
})

$form.Add_Load({
    try {
        $splitMain.SplitterDistance = 330
    } catch {
        # SplitterDistance 超出范围时忽略，使用默认值
    }
    try {
        $splitPaths.SplitterDistance = [int]($splitPaths.Width / 2)
    } catch {
        # 同上
    }

    try {
        Refresh-ManagerData
    } catch {
        $statusLabel.Text = '初始化失败：' + $_.Exception.Message
    }
})

# -----------------------------------------------------------------------------
# 启动
# -----------------------------------------------------------------------------

[void]$form.ShowDialog()
