<#
.SYNOPSIS
    编译 PathAdder COM 外壳扩展（64 位 DLL）。

.DESCRIPTION
    使用 .NET Framework 自带的 csc.exe 编译，不需要 Visual Studio。
    必须编译为 x64 —— explorer.exe 在 64 位 Windows 上是 64 位进程，
    32 位 DLL 无法被它加载（这是 COM 外壳扩展最常见的失败原因）。

    产物：PathAdderShellExt.dll（与源码同目录）

.EXAMPLE
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\build.ps1
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$sourcePath = Join-Path $PSScriptRoot 'PathAdderShellExt.cs'
$outputPath = Join-Path $PSScriptRoot 'PathAdderShellExt.dll'

if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
    Write-Host ('找不到源码：' + $sourcePath) -ForegroundColor Red
    exit 1
}

# 只用 64 位编译器
$frameworkRoot = Join-Path $env:WINDIR 'Microsoft.NET\Framework64'
if (-not (Test-Path -LiteralPath $frameworkRoot)) {
    Write-Host '未找到 .NET Framework 64 位目录，无法编译。' -ForegroundColor Red
    exit 1
}

$cscPath = ''
foreach ($dir in @(Get-ChildItem -LiteralPath $frameworkRoot -Directory | Sort-Object Name -Descending)) {
    $candidate = Join-Path $dir.FullName 'csc.exe'
    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
        $cscPath = $candidate
        break
    }
}

if ([string]::IsNullOrWhiteSpace($cscPath)) {
    Write-Host '未找到 csc.exe（.NET Framework 的 C# 编译器）。' -ForegroundColor Red
    Write-Host '请先安装 .NET Framework 4.x 开发工具，或改用 Visual Studio 编译。' -ForegroundColor Yellow
    exit 1
}

Write-Host ('编译器：' + $cscPath) -ForegroundColor Gray

# 若 DLL 正被 explorer 占用，先提示
if (Test-Path -LiteralPath $outputPath -PathType Leaf) {
    try {
        $stream = [System.IO.File]::Open($outputPath, 'Open', 'ReadWrite', 'None')
        $stream.Close()
        $stream.Dispose()
    }
    catch {
        Write-Host '' -ForegroundColor Yellow
        Write-Host 'PathAdderShellExt.dll 正被占用（多半是 explorer.exe 已加载它）。' -ForegroundColor Yellow
        Write-Host '请先注销 COM 并重启资源管理器：' -ForegroundColor Yellow
        Write-Host '    .\restore-menu.ps1 -KeepComRegistration' -ForegroundColor Gray
        Write-Host '    Stop-Process -Name explorer -Force; Start-Process explorer.exe' -ForegroundColor Gray
        Write-Host '' -ForegroundColor Yellow
        exit 1
    }
}

& $cscPath /nologo /target:library /platform:x64 /optimize+ /out:"$outputPath" "$sourcePath"

if ($LASTEXITCODE -ne 0) {
    Write-Host ('编译失败，csc 退出码 ' + $LASTEXITCODE) -ForegroundColor Red
    exit $LASTEXITCODE
}

if (-not (Test-Path -LiteralPath $outputPath -PathType Leaf)) {
    Write-Host '编译未产出 DLL。' -ForegroundColor Red
    exit 1
}

$size = (Get-Item -LiteralPath $outputPath).Length
Write-Host ('编译成功：' + $outputPath + '  (' + $size + ' 字节)') -ForegroundColor Green
Write-Host ''
Write-Host '下一步：以管理员身份运行 register-com.ps1 完成注册。' -ForegroundColor Cyan
exit 0
