<#
.SYNOPSIS
    PATH Assistant - action panel for the shell context menu.

.DESCRIPTION
    Why not use the native Windows static cascade (SubCommands)?

    SubCommands is a mechanism introduced with Windows Vista/7: the parent entry
    carries a semicolon-separated SubCommands list, each subcommand lives under
    ...\parent\shell\<verb>\command, and Explorer expands the cascade on hover.
    It works fine on Windows 7/10, but it is visibly broken on Windows 11 - the
    parent menu item is shown, yet it never expands on hover, and because the
    parent entry is not allowed to carry a command by convention, clicking it
    does nothing at all.

    Root cause: Windows 11 introduced a new context menu pipeline in which classic
    registry verbs are surfaced through an "ExplorerCommand verb" wrapper. That
    wrapper has incomplete support for the static SubCommands cascade; the more
    third-party IExplorerCommand extensions are installed on a machine, the more
    obvious the breakage becomes.

    Hence this fallback: the parent entry carries a command, and clicking it pops
    up a native WinForms ContextMenuStrip at the cursor position. It looks and
    behaves almost exactly like a native cascading submenu and does not rely on
    Explorer's cascade implementation at all, so it is 100% reliable. The trade-off
    is that it requires a "click" instead of a "hover".

.PARAMETER Target
    Full path of the file that was right-clicked (passed by Explorer as %V).
    This script operates on the directory that contains it.

.PARAMETER Language
    Optional language code (for example en-US or zh-CN). When omitted the language
    is resolved by the framework: PATHADDER_LANG > config.json > registry >
    system UI language > en-US.

.EXAMPLE
    powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden `
        -File ".\MenuPicker.ps1" -Target "D:\tools\app.exe"

.EXAMPLE
    powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden `
        -File ".\MenuPicker.ps1" -Target "D:\tools\app.exe" -Language zh-CN
#>

[CmdletBinding()]
param(
    [string]$Target = '',
    [string]$Language = ''
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# 0. Localization bootstrap
#
#    This script lives in the application root, so its own directory IS the root.
#    i18n.ps1 is loaded defensively: MenuPicker.ps1 is normally spawned directly
#    by Explorer, so nothing else has loaded the framework for us.
# ---------------------------------------------------------------------------
$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Definition
$global:PathAdderRootDirectory = $scriptDirectory

$i18nPath = Join-Path $scriptDirectory 'lib\i18n.ps1'
if (Test-Path -LiteralPath $i18nPath -PathType Leaf) {
    . $i18nPath
}

if (Get-Command -Name 'Initialize-PathAdderI18n' -ErrorAction SilentlyContinue) {
    Initialize-PathAdderI18n -Language $Language | Out-Null
}

# ---------------------------------------------------------------------------
# 1. Dependency check
# ---------------------------------------------------------------------------
try {
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
    Add-Type -AssemblyName System.Drawing -ErrorAction Stop
}
catch {
    Write-Error (T 'Picker.Error.FormsLoadFailed' @($_.Exception.Message))
    exit 1
}

$enginePath = Join-Path $scriptDirectory 'PathAdder.ps1'

if (-not (Test-Path -LiteralPath $enginePath -PathType Leaf)) {
    [void][System.Windows.Forms.MessageBox]::Show(
        (T 'Picker.Error.EngineMissing' @([Environment]::NewLine, $enginePath)),
        (T 'App.Name'),
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error)
    exit 1
}

# Current interpreter path: Explorer launches this script with powershell.exe -File,
# so reading the running process image is the most reliable source.
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
# 2. Menu item definitions
#    Kept one-to-one with the verb definitions in lib\ShellMenu.ps1 (same actions,
#    different presentation layer).
# ---------------------------------------------------------------------------
# Resolve the directory being operated on; shown as a disabled header row.
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
        Label      = (T 'Picker.Item.AddUser')
        Args       = @('-Action', 'Add', '-Scope', 'User')
        WithTarget = $true
    },
    [PSCustomObject] @{
        Label      = (T 'Picker.Item.AddSystem')
        Args       = @('-Action', 'Add', '-Scope', 'System')
        WithTarget = $true
    },
    [PSCustomObject] @{
        Label      = (T 'Picker.Item.Remove')
        Args       = @('-Action', 'Remove', '-Scope', 'All')
        WithTarget = $true
    },
    [PSCustomObject] @{
        Label      = (T 'Picker.Item.OpenManager')
        Args       = @('-Action', 'OpenManager')
        WithTarget = $false
    }
)

# ---------------------------------------------------------------------------
# 3. Build the menu
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
    # Falls back to the default system font when the face is unavailable.
}

# Header row: lets the user confirm which directory is about to be modified.
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
    # Separator after the three PATH actions, before "Open PATH Manager".
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

# Closing the menu (selection, ESC, click outside) also closes the host form so
# that ShowDialog returns.
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
# 4. Show the menu (blocks here until the menu is closed)
# ---------------------------------------------------------------------------
try {
    [void]$ownerForm.ShowDialog()
}
catch {
    Write-Error (T 'Picker.Error.ShowFailed' @($_.Exception.Message))
}

try { $ownerForm.Dispose() } catch { }
try { $contextMenu.Dispose() } catch { }

# ESC or a click outside the menu means "do nothing".
if ($null -eq $selectedSpecification) {
    exit 0
}

# ---------------------------------------------------------------------------
# 5. Hand the action over to PathAdder.ps1
#
#    The child process inherits the language through PATHADDER_LANG, which
#    Initialize-PathAdderI18n exports above, so no explicit -Language is needed
#    (and the registered command line in the registry stays untouched).
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
        (T 'Picker.Error.ExecuteFailed' @($_.Exception.Message)),
        (T 'App.Name'),
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error)
    exit 1
}
