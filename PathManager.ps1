# -----------------------------------------------------------------------------
# PathManager.ps1 - PATH Manager (WinForms GUI)
#
# Purpose:
#   * Show the current User PATH and System PATH entries (numbered)
#   * Show the backup history, with "preview contents" and "restore to this
#     backup" actions
#   * Show the change log (most recent 200 entries, newest first)
#   * Provide "Refresh" / "Open backup folder" buttons
#   * Provide a language selector that re-labels the whole UI in place
#
# Runtime: Windows PowerShell 5.1 (-STA single-threaded apartment, required by
# WinForms)
# -----------------------------------------------------------------------------

[CmdletBinding()]
param(
    [string]$Language = ''
)

$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    Appends a diagnostic line to %TEMP%\PathAdderShellExt.log, prefixed with Mgr.
.DESCRIPTION
    The format is identical to the Ctx.* lines written by Helper.Log on the C#
    side:
        HH:mm:ss.fff pid=<pid>  prefix  message
    This script is launched by explorer through a hidden powershell window, so
    any unhandled exception only shows up as "nothing happens when I click".
    Writing to the log is the only way to find the cause afterwards.
#>
function Write-PathAdderManagerLog {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    try {
        $logPath = Join-Path $env:TEMP 'PathAdderShellExt.log'
        $line = (Get-Date -Format 'HH:mm:ss.fff') + ' pid=' + $PID + '  Mgr. ' + $Message
        Add-Content -LiteralPath $logPath -Value $line -Encoding UTF8 -ErrorAction Stop
    } catch {
        # A log that cannot be written must never break the main flow
    }
}

<#
.SYNOPSIS
    Script-level error fallback.
.DESCRIPTION
    A trap is used here instead of wrapping the hundreds of lines below into one
    try { } block: that would require re-indenting everything, and in a script
    that cannot really be run on this machine the risk of introducing layout
    mistakes is too high. In PowerShell 5.1 the trap is an equivalent script
    level fallback and, combined with $ErrorActionPreference = 'Stop', catches
    every terminating error.
#>
trap {
    $managerError = (T 'Mgr.Msg.StartupFailed' @($_.Exception.Message))
    if ($null -ne $_.InvocationInfo -and -not [string]::IsNullOrWhiteSpace($_.InvocationInfo.PositionMessage)) {
        $managerError = $managerError + '  ' + (T 'Mgr.Msg.ErrorLocation' @($_.InvocationInfo.PositionMessage -replace "\s+", ' '))
    }

    Write-PathAdderManagerLog -Message $managerError

    # Failures happening before lib\Common.ps1 is dot-sourced have no
    # Show-PathAdderMessageBox yet; those fall back to native Write-Error
    # (stderr) plus exit code 1.
    $hasMessageBox = $false
    try {
        $hasMessageBox = ($null -ne (Get-Command -Name 'Show-PathAdderMessageBox' -ErrorAction SilentlyContinue))
    } catch {
        $hasMessageBox = $false
    }

    if ($hasMessageBox) {
        try {
            Show-PathAdderMessageBox -Message $managerError -Title (T 'Mgr.Title.StartupFailed') -Icon 'Error'
        } catch {
            # A failed popup must not throw again and hide the original exception
        }
    } else {
        Write-Error -Message $managerError -ErrorAction Continue
    }

    exit 1
}

Write-PathAdderManagerLog -Message 'PathManager.ps1 starting'

$script:MainScriptPath = $PSCommandPath
if ([string]::IsNullOrWhiteSpace($script:MainScriptPath)) {
    $script:MainScriptPath = $MyInvocation.MyCommand.Path
}
$script:ScriptRoot = Split-Path -Parent $script:MainScriptPath

# --- Localization bootstrap ---------------------------------------------------
# Must happen before any user-visible text is produced (including the error
# message for a missing lib\Common.ps1 below).
$global:PathAdderRootDirectory = $script:ScriptRoot
. (Join-Path $script:ScriptRoot 'lib\i18n.ps1')
Initialize-PathAdderI18n -Language $Language | Out-Null

$script:LibraryPath = Join-Path $script:ScriptRoot 'lib\Common.ps1'
if (-not (Test-Path -LiteralPath $script:LibraryPath -PathType Leaf)) {
    # Note: lib\Common.ps1 is not dot-sourced yet, so Show-PathAdderMessageBox
    # does not exist here. The native Write-Error must be used, otherwise the
    # failure degenerates into a confusing "command not found" error.
    Write-Error (T 'Mgr.Msg.MissingLibrary' @($script:LibraryPath))
    exit 1
}
. $script:LibraryPath

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# -----------------------------------------------------------------------------
# Font and text helpers
# -----------------------------------------------------------------------------

<#
.SYNOPSIS
    Picks the first installed font from a list of candidates, falling back to
    the default font when none of them is available.
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
        # Fall through to the default font
    }

    return (New-Object System.Drawing.Font([System.Drawing.SystemFonts]::MessageBoxFont.FontFamily, $Size))
}

$script:UiFont = Get-AvailableFont -Candidates @('Microsoft YaHei UI', 'Microsoft YaHei', 'SimSun', 'Segoe UI') -Size 9
$script:MonoFont = Get-AvailableFont -Candidates @('Consolas', 'Courier New', 'Microsoft YaHei', 'SimSun') -Size 10

<#
.SYNOPSIS
    Formats a PATH string as numbered multi-line text.
#>
function Format-PathListText {
    param(
        [Parameter(Mandatory = $false)]
        [string]$Value
    )

    $entries = @(Split-PathList -Value $Value)
    if ($entries.Count -eq 0) {
        return (T 'Mgr.Text.EmptyPath')
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
    Reads the change log and returns the most recent N lines, newest first.
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
# Form construction
# -----------------------------------------------------------------------------

$script:form = New-Object System.Windows.Forms.Form
$form = $script:form
$form.Size = New-Object System.Drawing.Size(1080, 720)
$form.MinimumSize = New-Object System.Drawing.Size(880, 560)
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
$form.Font = $script:UiFont

# --- Top panel ---
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
        [Parameter(Mandatory = $false)]
        [string]$Text = '',

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

# --- Language selector (label + combo box), docked to the left of the buttons ---
$languagePanel = New-Object System.Windows.Forms.Panel
$languagePanel.Dock = [System.Windows.Forms.DockStyle]::Right
$languagePanel.Width = 208
$languagePanel.Padding = New-Object System.Windows.Forms.Padding(0)

$languageFlow = New-Object System.Windows.Forms.FlowLayoutPanel
$languageFlow.Dock = [System.Windows.Forms.DockStyle]::Fill
$languageFlow.FlowDirection = [System.Windows.Forms.FlowDirection]::LeftToRight
$languageFlow.WrapContents = $false

$lblLanguage = New-Object System.Windows.Forms.Label
$lblLanguage.AutoSize = $true
$lblLanguage.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$lblLanguage.Margin = New-Object System.Windows.Forms.Padding(0, 7, 6, 0)
$lblLanguage.Font = $script:UiFont

$script:cboLanguage = New-Object System.Windows.Forms.ComboBox
$cboLanguage = $script:cboLanguage
$cboLanguage.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$cboLanguage.Width = 132
$cboLanguage.Margin = New-Object System.Windows.Forms.Padding(0, 3, 0, 0)
$cboLanguage.Font = $script:UiFont
$cboLanguage.DisplayMember = 'DisplayName'
$cboLanguage.ValueMember = 'Code'

# Keeps the tooltip component alive for the lifetime of the form
$script:ManagerToolTip = New-Object System.Windows.Forms.ToolTip

[void]$languageFlow.Controls.Add($lblLanguage)
[void]$languageFlow.Controls.Add($cboLanguage)
[void]$languagePanel.Controls.Add($languageFlow)

$btnRefresh = New-ManagerButton -Width 88
$btnOpenBackupDir = New-ManagerButton -Width 142
$btnOpenLog = New-ManagerButton -Width 142
$btnClose = New-ManagerButton -Width 88

[void]$buttonStrip.Controls.Add($btnRefresh, 0, 0)
[void]$buttonStrip.Controls.Add($btnOpenBackupDir, 1, 0)
[void]$buttonStrip.Controls.Add($btnOpenLog, 2, 0)
[void]$buttonStrip.Controls.Add($btnClose, 3, 0)

$lblHint = New-Object System.Windows.Forms.Label
$lblHint.Dock = [System.Windows.Forms.DockStyle]::Fill
$lblHint.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$lblHint.AutoEllipsis = $true
$lblHint.Font = $script:UiFont

# Dock order note: WinForms lays out docked children from the last one added to
# the first, so the language panel must be added before the button strip to end
# up on its left, and the hint label (Fill) must be added last of the three.
[void]$topPanel.Controls.Add($lblHint)
[void]$topPanel.Controls.Add($languagePanel)
[void]$topPanel.Controls.Add($buttonStrip)

# --- Bottom status bar ---
$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Dock = [System.Windows.Forms.DockStyle]::Bottom
$statusLabel.Height = 26
$statusLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$statusLabel.Padding = New-Object System.Windows.Forms.Padding(8, 0, 0, 0)
$statusLabel.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$statusLabel.Font = $script:UiFont

# --- Main splitter ---
# Key point: the default Size of a SplitContainer is only 150x100.
# Panel1MinSize + Panel2MinSize must be <= the available size of the container,
# otherwise WinForms throws "SplitterDistance must be between Panel1MinSize and
# Width - Panel2MinSize" when Panel2MinSize is assigned and the script dies.
# Therefore an explicit, large enough Size must be set *before* the MinSizes.
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
        [Parameter(Mandatory = $false)]
        [string]$Title = ''
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

$userGroup = New-PathListGroup
$systemGroup = New-PathListGroup

[void]$splitPaths.Panel1.Controls.Add($userGroup.Group)
[void]$splitPaths.Panel2.Controls.Add($systemGroup.Group)
[void]$splitMain.Panel1.Controls.Add($splitPaths)

# --- Tabs at the bottom ---
$tabs = New-Object System.Windows.Forms.TabControl
$tabs.Dock = [System.Windows.Forms.DockStyle]::Fill
$tabs.Font = $script:UiFont

# Backup history tab
$tabBackups = New-Object System.Windows.Forms.TabPage
$tabBackups.Padding = New-Object System.Windows.Forms.Padding(6)
$tabBackups.Font = $script:UiFont

# Column definitions: the header text comes from the language pack (re-applied
# whenever the language changes), the widths are layout constants.
$script:BackupColumns = @(
    @{ Key = 'Mgr.Column.File';  Width = 260 },
    @{ Key = 'Mgr.Column.Scope'; Width = 70 },
    @{ Key = 'Mgr.Column.Time';  Width = 170 },
    @{ Key = 'Mgr.Column.Size';  Width = 110 },
    @{ Key = 'Mgr.Column.Path';  Width = 520 }
)

$lvBackups = New-Object System.Windows.Forms.ListView
$lvBackups.Dock = [System.Windows.Forms.DockStyle]::Fill
$lvBackups.View = [System.Windows.Forms.View]::Details
$lvBackups.FullRowSelect = $true
$lvBackups.GridLines = $true
$lvBackups.HideSelection = $false
$lvBackups.MultiSelect = $false
$lvBackups.Font = $script:MonoFont
foreach ($column in $script:BackupColumns) {
    [void]$lvBackups.Columns.Add('', $column.Width)
}

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
        [Parameter(Mandatory = $false)]
        [string]$Text = '',

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

$btnPreview = New-BackupButton -Width 120
$btnRestore = New-BackupButton -Width 150
$btnRefreshBackups = New-BackupButton -Width 130

[void]$backupFlow.Controls.Add($btnPreview)
[void]$backupFlow.Controls.Add($btnRestore)
[void]$backupFlow.Controls.Add($btnRefreshBackups)
[void]$backupButtonPanel.Controls.Add($backupFlow)

[void]$tabBackups.Controls.Add($lvBackups)
[void]$tabBackups.Controls.Add($backupButtonPanel)

# Change log tab
$tabLog = New-Object System.Windows.Forms.TabPage
$tabLog.Padding = New-Object System.Windows.Forms.Padding(6)
$tabLog.Font = $script:UiFont

$logHeader = New-Object System.Windows.Forms.Label
$logHeader.Dock = [System.Windows.Forms.DockStyle]::Top
$logHeader.Height = 28
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
# Localization
# -----------------------------------------------------------------------------

<#
.SYNOPSIS
    Refills the language combo box with the supported languages and selects the
    active one.
.DESCRIPTION
    A guard flag suppresses the SelectedIndexChanged handler while the items are
    rebuilt, otherwise the re-selection would re-enter the switch logic.
#>
function Update-PathAdderManagerLanguageSelector {
    $script:UpdatingLanguageSelector = $true
    try {
        $current = Get-PathAdderLanguage
        $selectedIndex = -1

        $cboLanguage.BeginUpdate()
        $cboLanguage.Items.Clear()
        foreach ($choice in @(Get-PathAdderLanguageChoices)) {
            $index = $cboLanguage.Items.Add($choice)
            if ([string]$choice.Code -eq $current) {
                $selectedIndex = $index
            }
        }
        $cboLanguage.EndUpdate()

        if ($selectedIndex -ge 0) {
            $cboLanguage.SelectedIndex = $selectedIndex
        }
    } finally {
        $script:UpdatingLanguageSelector = $false
    }
}

<#
.SYNOPSIS
    Applies every localized text to the manager form.
.DESCRIPTION
    Called once at startup and again whenever the user picks another language in
    the language selector, so the whole UI is re-labeled in place (titles,
    buttons, labels, tabs and column headers).
#>
function Apply-PathAdderManagerLocalization {
    $form.Text = (T 'App.Name') + ' - ' + (T 'Mgr.Title')

    $btnRefresh.Text = (T 'App.Button.Refresh')
    $btnOpenBackupDir.Text = (T 'Mgr.Button.OpenBackupDir')
    $btnOpenLog.Text = (T 'Mgr.Button.OpenLog')
    $btnClose.Text = (T 'App.Button.Close')

    $btnPreview.Text = (T 'Mgr.Button.Preview')
    $btnRestore.Text = (T 'Mgr.Button.RestoreToBackup')
    $btnRefreshBackups.Text = (T 'Mgr.Button.RefreshBackups')

    $lblLanguage.Text = (T 'App.Language')
    $lblHint.Text = (T 'Mgr.Hint')

    $userGroup.Group.Text = (T 'Mgr.Group.UserPath')
    $systemGroup.Group.Text = (T 'Mgr.Group.SystemPath')

    $tabBackups.Text = (T 'Mgr.Tab.Backups')
    $tabLog.Text = (T 'Mgr.Tab.Log')

    for ($i = 0; $i -lt $script:BackupColumns.Count; $i++) {
        if ($i -lt $lvBackups.Columns.Count) {
            $lvBackups.Columns[$i].Text = (T $script:BackupColumns[$i].Key)
        }
    }

    $logHeader.Text = (T 'Mgr.Log.Header' @(200))
    $statusLabel.Text = (T 'Mgr.Status.Ready')

    $script:ManagerToolTip.SetToolTip($cboLanguage, (T 'Mgr.ToolTip.LanguageSelector'))
    $script:ManagerToolTip.SetToolTip($lblLanguage, (T 'Mgr.ToolTip.LanguageSelector'))

    Update-PathAdderManagerLanguageSelector
}

Apply-PathAdderManagerLocalization

# -----------------------------------------------------------------------------
# Data loading
# -----------------------------------------------------------------------------

<#
.SYNOPSIS
    Refreshes the PATH lists, the backup list and the log.
#>
function Refresh-ManagerData {
    $isAdmin = Test-PathAdderAdministrator

    $userInfo = Get-EnvironmentPathInfo -Scope 'User'
    $systemInfo = Get-EnvironmentPathInfo -Scope 'System'

    $userCount = @(Split-PathList -Value $userInfo.Value).Count
    $systemCount = @(Split-PathList -Value $systemInfo.Value).Count

    $userGroup.Group.Text = (T 'Mgr.Group.UserPath') + (T 'Mgr.Text.EntryCount' @($userCount))
    $systemGroup.Group.Text = (T 'Mgr.Group.SystemPath') + (T 'Mgr.Text.EntryCount' @($systemCount))

    $userGroup.TextBox.Text = Format-PathListText -Value $userInfo.Value

    if (-not [string]::IsNullOrEmpty($systemInfo.Error)) {
        $systemGroup.TextBox.Text = (T 'Mgr.Text.ReadFailed' @($systemInfo.Error))
    } else {
        $systemGroup.TextBox.Text = Format-PathListText -Value $systemInfo.Value
    }

    # Backup list
    $lvBackups.BeginUpdate()
    $lvBackups.Items.Clear()
    $backups = @(Get-PathAdderBackups)
    foreach ($item in $backups) {
        $lvItem = New-Object System.Windows.Forms.ListViewItem($item.FileName)
        # ScopeLabel is produced by lib\Common.ps1 so that both modules show the
        # same wording for a backup scope.
        [void]$lvItem.SubItems.Add($item.ScopeLabel)
        [void]$lvItem.SubItems.Add($item.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))
        [void]$lvItem.SubItems.Add($item.Length.ToString())
        [void]$lvItem.SubItems.Add($item.FullPath)
        $lvItem.Tag = $item
        [void]$lvBackups.Items.Add($lvItem)
    }
    $lvBackups.EndUpdate()

    # Log
    $logLines = @(Get-ReversedLogLines -MaxCount 200)
    if ($logLines.Count -eq 0) {
        $txtLog.Text = (T 'Mgr.Log.Empty')
    } else {
        $txtLog.Text = [string]::Join([System.Environment]::NewLine, $logLines)
    }

    $adminText = (T 'App.Button.No')
    if ($isAdmin) {
        $adminText = (T 'App.Button.Yes')
    }

    $statusLabel.Text = (T 'Mgr.Status.Summary' @(
        $userCount,
        $systemCount,
        $backups.Count,
        $adminText,
        (Get-PathAdderBackupDirectory)
    ))
}

<#
.SYNOPSIS
    Shows a read-only text preview window.
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
# Event handlers
# -----------------------------------------------------------------------------

$cboLanguage.Add_SelectedIndexChanged({
    if ($script:UpdatingLanguageSelector) {
        return
    }

    $choice = $cboLanguage.SelectedItem
    if ($null -eq $choice) {
        return
    }

    $code = [string]$choice.Code
    if ([string]::IsNullOrWhiteSpace($code) -or $code -eq (Get-PathAdderLanguage)) {
        return
    }

    try {
        [void](Set-PathAdderLanguage -Language $code)
        Apply-PathAdderManagerLocalization
        try {
            Refresh-ManagerData
        } catch {
            Write-PathAdderManagerLog -Message ('Refresh after language switch failed: ' + $_.Exception.Message)
        }
    } catch {
        Write-PathAdderManagerLog -Message ('Language switch failed: ' + $_.Exception.Message)
        [void][System.Windows.Forms.MessageBox]::Show($script:form,
            (T 'Mgr.Msg.LanguageSwitchFailed' @($_.Exception.Message)),
            (T 'App.Name'),
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error)
    }
})

$btnRefresh.Add_Click({
    try {
        Refresh-ManagerData
    } catch {
        [void][System.Windows.Forms.MessageBox]::Show($script:form,
            (T 'Mgr.Msg.RefreshFailed' @($_.Exception.Message)),
            (T 'App.Name'),
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error)
    }
})

$btnRefreshBackups.Add_Click({
    try {
        Refresh-ManagerData
    } catch {
        [void][System.Windows.Forms.MessageBox]::Show($script:form,
            (T 'Mgr.Msg.RefreshFailed' @($_.Exception.Message)),
            (T 'App.Name'),
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
            ((T 'Mgr.Msg.OpenDirFailed' @($dir)) + "`r`n" + $_.Exception.Message),
            (T 'App.Name'),
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error)
    }
})

$btnOpenLog.Add_Click({
    $logFile = Get-PathAdderLogFilePath
    if (-not (Test-Path -LiteralPath $logFile -PathType Leaf)) {
        [void][System.Windows.Forms.MessageBox]::Show($script:form,
            (T 'Mgr.Msg.NoLogFile'),
            (T 'App.Name'),
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information)
        return
    }

    try {
        Start-Process -FilePath 'notepad.exe' -ArgumentList ('"' + $logFile + '"')
    } catch {
        [void][System.Windows.Forms.MessageBox]::Show($script:form,
            (T 'Mgr.Msg.OpenLogFailed' @($logFile)),
            (T 'App.Name'),
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
            (T 'Mgr.Msg.SelectBackupFirst'),
            (T 'App.Name'),
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
            $content = (T 'Mgr.Backup.EmptyContent')
        }
    } catch {
        [void][System.Windows.Forms.MessageBox]::Show($script:form,
            (T 'Mgr.Msg.ReadBackupFailed' @($_.Exception.Message)),
            (T 'App.Name'),
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error)
        return
    }

    Show-TextPreviewForm -Title (T 'Mgr.Title.BackupPreview' @($item.FileName)) -Content $content
})

$btnRestore.Add_Click({
    if ($lvBackups.SelectedItems.Count -eq 0) {
        [void][System.Windows.Forms.MessageBox]::Show($script:form,
            (T 'Mgr.Msg.SelectBackupFirst'),
            (T 'App.Name'),
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information)
        return
    }

    $item = $lvBackups.SelectedItems[0].Tag
    $scopeLabel = (T 'Mgr.Scope.UserPath')
    if ($item.Scope -eq 'System') {
        $scopeLabel = (T 'Mgr.Scope.SystemPath')
    }

    $answer = [System.Windows.Forms.MessageBox]::Show($script:form,
        (T 'Mgr.Msg.ConfirmRestore' @(
            $scopeLabel,
            $item.FileName,
            $item.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'),
            $item.Length)),
        (T 'App.Name'),
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
                (T 'Mgr.Msg.RestoreElevationRequested' @($scopeLabel, $item.FileName)),
                (T 'App.Name'),
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information)
        } else {
            [void][System.Windows.Forms.MessageBox]::Show($script:form,
                (T 'Mgr.Msg.RestoreElevationFailed' @($scopeLabel, $item.FileName)),
                (T 'App.Name'),
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning)
        }
        return
    }

    try {
        $restoreResult = Restore-PathBackup -BackupFileName $item.FileName
        Refresh-ManagerData
        [void][System.Windows.Forms.MessageBox]::Show($script:form,
            (T 'Mgr.Msg.RestoreSucceeded' @(
                $scopeLabel,
                $restoreResult.RestoredFrom,
                $restoreResult.BackupFile)),
            (T 'App.Name'),
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information)
    } catch {
        [void][System.Windows.Forms.MessageBox]::Show($script:form,
            (T 'Mgr.Msg.RestoreFailed' @($_.Exception.Message)),
            (T 'App.Name'),
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
        # SplitterDistance out of range: keep the default
    }
    try {
        $splitPaths.SplitterDistance = [int]($splitPaths.Width / 2)
    } catch {
        # Same as above
    }

    try {
        Refresh-ManagerData
    } catch {
        $statusLabel.Text = (T 'Mgr.Msg.InitFailed' @($_.Exception.Message))
    }
})

# -----------------------------------------------------------------------------
# Startup
# -----------------------------------------------------------------------------

# A WinForms window started by explorer through a hidden powershell window is
# often pushed behind other windows or fails to get the foreground focus
# (Windows foreground locking blocks SetForegroundWindow); from the user's point
# of view it again looks like "I clicked and nothing showed up".
#
# Fix: show it as TopMost (a TopMost window ignores foreground locking and is
#       guaranteed to float to the top), then grab the focus with Activate() in
#       the Shown event and set TopMost back to false *immediately* - otherwise
#       the window would stay on top of everything else and get in the way.
$form.TopMost = $true
$form.Add_Shown({
    try {
        $form.Activate()
    } catch {
        # Failing to grab the focus does not prevent the form from being shown
    }
    $form.TopMost = $false
})

Write-PathAdderManagerLog -Message 'About to show the main form (ShowDialog)'
[void]$form.ShowDialog()
Write-PathAdderManagerLog -Message 'Main form closed, exiting normally'

exit 0
