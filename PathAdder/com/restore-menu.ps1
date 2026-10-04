<#
.SYNOPSIS
    回滚到「点击弹出菜单」模式（撤销 register-com.ps1 的切换）。

.DESCRIPTION
    做三件事：
      1. 删除 *\shell\PathAdder 的 ExplorerCommandHandler 值
      2. regasm /unregister 注销 COM 类（需管理员）
      3. 重新写回 MenuPicker.ps1 的 command 子键

    执行后右键菜单回到「点击 PATH 助手 → 在光标处弹出菜单」的行为，
    即 register-com.ps1 之前的状态。

.EXAMPLE
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\restore-menu.ps1
#>

[CmdletBinding()]
param(
    # 只切换菜单、不注销 COM（DLL 仍被 explorer 占用时可用）
    [switch]$KeepComRegistration
)

$ErrorActionPreference = 'Stop'

$verbKey = 'Software\Classes\*\shell\PathAdder'
$dllPath = Join-Path $PSScriptRoot 'PathAdderShellExt.dll'

Write-Host '=== 步骤 1/3：清除 ExplorerCommandHandler ===' -ForegroundColor Cyan

$key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($verbKey, $true)
if ($null -ne $key) {
    try {
        if ($key.GetValueNames() -contains 'ExplorerCommandHandler') {
            $key.DeleteValue('ExplorerCommandHandler', $false)
            Write-Host '已删除 ExplorerCommandHandler。' -ForegroundColor Green
        }
        else {
            Write-Host '本来就没有 ExplorerCommandHandler，跳过。' -ForegroundColor Gray
        }
    }
    finally { $key.Close() }
}
else {
    Write-Host '菜单键不存在，跳过。' -ForegroundColor Gray
}

# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '=== 步骤 2/3：注销 COM 类 ===' -ForegroundColor Cyan

if ($KeepComRegistration) {
    Write-Host '已指定 -KeepComRegistration，跳过注销。' -ForegroundColor Gray
}
else {
    $isAdmin = $false
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        $isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch { $isAdmin = $false }

    if (-not $isAdmin) {
        Write-Host '未以管理员运行，跳过 regasm 注销（COM 类仍留在注册表里，无害）。' -ForegroundColor Yellow
        Write-Host '如需彻底清除，请以管理员身份重跑本脚本。' -ForegroundColor Yellow
    }
    else {
        $regasmPath = ''
        $frameworkRoot = Join-Path $env:WINDIR 'Microsoft.NET\Framework64'
        foreach ($dir in @(Get-ChildItem -LiteralPath $frameworkRoot -Directory | Sort-Object Name -Descending)) {
            $candidate = Join-Path $dir.FullName 'RegAsm.exe'
            if (Test-Path -LiteralPath $candidate -PathType Leaf) { $regasmPath = $candidate; break }
        }

        if ((-not [string]::IsNullOrWhiteSpace($regasmPath)) -and (Test-Path -LiteralPath $dllPath -PathType Leaf)) {
            & $regasmPath /unregister /nologo "$dllPath"
            Write-Host 'COM 类已注销。' -ForegroundColor Green
        }
        else {
            Write-Host '未找到 RegAsm.exe 或 DLL，跳过注销。' -ForegroundColor Gray
        }
    }
}

# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '=== 步骤 3/3：写回 MenuPicker 的 command ===' -ForegroundColor Cyan

$parentDir = Split-Path -Parent $PSScriptRoot
$pickerPath = Join-Path $parentDir 'MenuPicker.ps1'

if (-not (Test-Path -LiteralPath $pickerPath -PathType Leaf)) {
    Write-Host ('找不到 MenuPicker.ps1：' + $pickerPath) -ForegroundColor Red
    Write-Host '请改用上级目录的 install.ps1 重新完整安装。' -ForegroundColor Yellow
    exit 1
}

$psPath = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
if (-not (Test-Path -LiteralPath $psPath -PathType Leaf)) {
    $cmd = Get-Command -Name 'powershell.exe' -ErrorAction SilentlyContinue
    if ($null -ne $cmd) { $psPath = $cmd.Source } else { $psPath = 'powershell.exe' }
}

$commandLine = '"' + $psPath + '" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' +
               $pickerPath + '" -Target "%V"'

$cmdKey = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($verbKey + '\command')
try {
    $cmdKey.SetValue('', $commandLine, [Microsoft.Win32.RegistryValueKind]::String)
    Write-Host '已写回 command：' -ForegroundColor Green
    Write-Host ('  ' + $commandLine) -ForegroundColor Gray
}
finally { $cmdKey.Close() }

# 顺带补上父项显示值（防止之前被清空）
$key2 = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($verbKey)
try {
    if ([string]::IsNullOrWhiteSpace([string]$key2.GetValue('MUIVerb', ''))) {
        $key2.SetValue('MUIVerb', 'PATH 助手', [Microsoft.Win32.RegistryValueKind]::String)
    }
}
finally { $key2.Close() }

Write-Host ''
Write-Host '========== 已回到「点击弹出菜单」模式 ==========' -ForegroundColor Green
Write-Host ''
Write-Host '请重启资源管理器使改动生效：' -ForegroundColor Yellow
Write-Host '    Stop-Process -Name explorer -Force; Start-Process explorer.exe' -ForegroundColor Gray
Write-Host ''

exit 0
