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

# -----------------------------------------------------------------------------
# 若 DLL 正被占用：采用「改名绕过」，而不是直接失败退出
#
# 原理：加载 DLL 的进程（explorer.exe 等）持有 FILE_SHARE_DELETE，所以
#       Windows 允许把这个文件【改名】，只是不允许【写入】它。
#       把旧文件改名后，新 DLL 就能编译到原路径 —— 注册表里的 CodeBase
#       指向的路径没有变化，因此不需要重新注册。（但必须重启资源管理器，
#       才能让新代码生效。）
# -----------------------------------------------------------------------------
$renamedOld = ''

if (Test-Path -LiteralPath $outputPath -PathType Leaf) {
    $locked = $false
    try {
        $stream = [System.IO.File]::Open($outputPath, 'Open', 'ReadWrite', 'None')
        $stream.Close()
        $stream.Dispose()
    }
    catch {
        $locked = $true
    }

    if ($locked) {
        Write-Host ''
        Write-Host 'DLL 正被占用（explorer 已把它加载进内存），改用「改名绕过」策略。' -ForegroundColor Yellow

        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $backup = $outputPath + '.' + $stamp + '.old'

        try {
            Move-Item -LiteralPath $outputPath -Destination $backup -Force
            $renamedOld = $backup
            Write-Host ('  旧文件已改名：' + (Split-Path -Leaf $backup)) -ForegroundColor Gray
            Write-Host '  新 DLL 将编译到原路径，注册表 CodeBase 不变，无需重新注册。' -ForegroundColor Gray
            Write-Host '  ⚠ 必须重启资源管理器，新代码才会被加载。' -ForegroundColor Yellow
        }
        catch {
            Write-Host ''
            Write-Host '改名也失败了，说明锁更严格（常见于杀毒软件正在扫描该文件）。' -ForegroundColor Red
            Write-Host '可以试试：' -ForegroundColor Yellow
            Write-Host '   1) 运行 .\rebuild.ps1（会先重启资源管理器释放占用）' -ForegroundColor Gray
            Write-Host '   2) 等 10~30 秒后重试' -ForegroundColor Gray
            Write-Host '   3) 把 PathAdder\com 目录加入杀毒软件排除项' -ForegroundColor Gray
            Write-Host ''
            Write-Host '★ 提醒：不要用 regsvr32 /u 去「注销」本 DLL。' -ForegroundColor Red
            Write-Host '   它是 .NET 程序集，没有 DllUnregisterServer 导出（由 mscoree.dll 代理），' -ForegroundColor Red
            Write-Host '   regsvr32 必然报「找不到入口点」，而且解决不了文件占用。' -ForegroundColor Red
            Write-Host '' -ForegroundColor Yellow
            exit 1
        }
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

# 顺手清掉本次改名产生的 .old 文件；若仍被内存占用就留着（无害）
if (-not [string]::IsNullOrEmpty($renamedOld)) {
    try {
        Remove-Item -LiteralPath $renamedOld -Force -ErrorAction Stop
        Write-Host '被占用的旧 DLL 已清理。' -ForegroundColor Gray
    }
    catch {
        Write-Host ('旧 DLL 仍被内存占用，暂留在 ' + (Split-Path -Leaf $renamedOld)) -ForegroundColor Gray
        Write-Host '重启资源管理器后可手动删除，留着也不影响功能。' -ForegroundColor Gray
    }
}

Write-Host ''
Write-Host '下一步：以管理员身份运行 register-com.ps1 完成注册。' -ForegroundColor Cyan
Write-Host '（若刚才改过名，务必重启资源管理器，否则加载的仍是旧代码。）' -ForegroundColor Yellow
exit 0
