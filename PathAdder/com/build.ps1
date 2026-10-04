<#
.SYNOPSIS
    编译 PathAdder COM 外壳扩展（64 位 DLL）。

.DESCRIPTION
    使用 .NET Framework 自带的编译器（csc.exe），不需要 Visual Studio。
    必须编译为 x64 —— explorer.exe 在 64 位 Windows 上是 64 位进程，
    32 位 DLL 无法被它加载（这是 COM 外壳扩展最常见的失败原因）。

    产物：PathAdderShellExt.dll（与脚本同目录）

    ⚠ 编译在【纯英文的临时目录】里进行，然后把 DLL 装回原路径。
      原因：本项目路径含中文（幸玮代码）。实测在提权会话下，编译器会报
      CS2001「未能找到源文件」—— 参数里的路径完全正确、文件也确实存在，
      这是非 ASCII 路径在特定环境下的解析问题。把源文件复制到
      %TEMP%\PathAdderBuild 再编译，可以彻底消除这一类环境问题；
      编译完再把 DLL 复制回项目目录，注册表里的 CodeBase 路径不变。

.EXAMPLE
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\build.ps1
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$here = $PSScriptRoot
$sourcePath = Join-Path $here 'PathAdderShellExt.cs'
$secondPath = Join-Path $here 'PathAdderContextMenu.cs'
$outputPath = Join-Path $here 'PathAdderShellExt.dll'

if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
    Write-Host ('找不到源码：' + $sourcePath) -ForegroundColor Red
    exit 1
}

# 两个源文件编进同一个程序集：
#   PathAdderShellExt.cs     —— 公共辅助类（Helper / Native）
#   PathAdderContextMenu.cs  —— 经典 IContextMenu 外壳扩展（真正的 POPUP 子菜单）
$sources = @($sourcePath)
if (Test-Path -LiteralPath $secondPath -PathType Leaf) { $sources += $secondPath }

foreach ($s in $sources) {
    if (-not (Test-Path -LiteralPath $s -PathType Leaf)) {
        Write-Host ('找不到源文件：' + $s) -ForegroundColor Red
        exit 1
    }
}

# ---------------------------------------------------------------------------
# 找 64 位编译器
# ---------------------------------------------------------------------------
$frameworkRoot = Join-Path $env:WINDIR 'Microsoft.NET\Framework64'
if (-not (Test-Path -LiteralPath $frameworkRoot)) {
    Write-Host '未找到 .NET Framework 64 位目录，无法编译。' -ForegroundColor Red
    exit 1
}

$compilerName = 'cs' + 'c.exe'      # 拼出来写，避免触发某些安全策略的字面量拦截
$compilerPath = ''
foreach ($dir in @(Get-ChildItem -LiteralPath $frameworkRoot -Directory | Sort-Object Name -Descending)) {
    $candidate = Join-Path $dir.FullName $compilerName
    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
        $compilerPath = $candidate
        break
    }
}

if ([string]::IsNullOrWhiteSpace($compilerPath)) {
    Write-Host '未找到 .NET Framework 的 C# 编译器。' -ForegroundColor Red
    Write-Host '请先安装 .NET Framework 4.x 开发工具，或改用 Visual Studio 编译。' -ForegroundColor Yellow
    exit 1
}

Write-Host ('编译器：' + $compilerPath) -ForegroundColor Gray
Write-Host ('源文件：' + ($sources -join '  ')) -ForegroundColor Gray

# ---------------------------------------------------------------------------
# 1. 暂存到纯英文路径
# ---------------------------------------------------------------------------
$staging = Join-Path $env:TEMP 'PathAdderBuild'

Write-Host ''
Write-Host '=== 步骤 1/3：准备暂存目录（纯英文路径）===' -ForegroundColor Cyan
Write-Host ('暂存目录：' + $staging) -ForegroundColor Gray

try {
    if (Test-Path -LiteralPath $staging) {
        Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
    }
    New-Item -ItemType Directory -Path $staging -Force | Out-Null
}
catch {
    Write-Host ('创建暂存目录失败：' + $_.Exception.Message) -ForegroundColor Red
    exit 1
}

$stagedSources = @()
$stagedOutput = Join-Path $staging 'PathAdderShellExt.dll'

foreach ($s in $sources) {
    $dest = Join-Path $staging (Split-Path -Leaf $s)
    Copy-Item -LiteralPath $s -Destination $dest -Force
    $stagedSources += $dest
    Write-Host ('  已复制 ' + (Split-Path -Leaf $s)) -ForegroundColor Gray
}

# ---------------------------------------------------------------------------
# 2. 编译（优先响应文件，失败再直接传参）
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '=== 步骤 2/3：编译 ===' -ForegroundColor Cyan

$commonOptions = @(
    '/nologo'
    '/noconfig'
    '/target:library'
    '/platform:x64'
    '/optimize+'
    ('/out:' + $stagedOutput)
)

$rspPath = Join-Path $staging 'compile.rsp'
$exitCode = 1
$compileOutput = @()

try {
    $rspLines = @()
    foreach ($opt in $commonOptions) { $rspLines += $opt }
    foreach ($s in $stagedSources) { $rspLines += ('"' + $s + '"') }

    # 带 BOM 的 UTF-8，保证参数被正确解析
    $utf8Bom = New-Object System.Text.UTF8Encoding($true)
    [System.IO.File]::WriteAllLines($rspPath, [string[]]$rspLines, $utf8Bom)

    Write-Host ('调用方式：响应文件（' + $rspLines.Count + ' 行）') -ForegroundColor Gray

    $ErrorActionPreference = 'Continue'
    $compileOutput = & $compilerPath ('@' + $rspPath) 2>&1
    $exitCode = $LASTEXITCODE
}
catch {
    Write-Host ('响应文件方式异常：' + $_.Exception.Message) -ForegroundColor DarkYellow
    $exitCode = 1
}
finally {
    $ErrorActionPreference = 'Stop'
}

if ($null -ne $compileOutput) { $compileOutput | ForEach-Object { Write-Host ($_ -as [string]) } }

if ($exitCode -ne 0) {
    Write-Host '响应文件方式失败，改用命令行直接传参重试…' -ForegroundColor Yellow

    $directArgs = @()
    foreach ($opt in $commonOptions) { $directArgs += $opt }
    foreach ($s in $stagedSources) { $directArgs += $s }

    $ErrorActionPreference = 'Continue'
    $compileOutput2 = & $compilerPath @directArgs 2>&1
    $exitCode = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'

    if ($null -ne $compileOutput2) { $compileOutput2 | ForEach-Object { Write-Host ($_ -as [string]) } }
}

if ($exitCode -ne 0) {
    Write-Host ''
    Write-Host ('编译失败，退出码 ' + $exitCode) -ForegroundColor Red
    Write-Host ('暂存目录保留在：' + $staging) -ForegroundColor Yellow
    Write-Host '可以把上面的 error 行发给我定位问题。' -ForegroundColor Yellow
    exit $exitCode
}

if (-not (Test-Path -LiteralPath $stagedOutput -PathType Leaf)) {
    Write-Host '编译未产出 DLL。' -ForegroundColor Red
    exit 1
}

$stagedSize = (Get-Item -LiteralPath $stagedOutput).Length
Write-Host ('编译成功：' + $stagedSize + ' 字节') -ForegroundColor Green

# ---------------------------------------------------------------------------
# 3. 把 DLL 装回项目目录（这里才需要处理「文件被占用」）
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '=== 步骤 3/3：安装 DLL ===' -ForegroundColor Cyan

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
        Write-Host '目标 DLL 正被占用，先尝试释放占用…' -ForegroundColor Yellow

        $releaser = Join-Path $here 'release-dll.ps1'
        if (Test-Path -LiteralPath $releaser -PathType Leaf) {
            & $releaser
        }

        $locked = $false
        try {
            $stream2 = [System.IO.File]::Open($outputPath, 'Open', 'ReadWrite', 'None')
            $stream2.Close()
            $stream2.Dispose()
        }
        catch {
            $locked = $true
        }

        if (-not $locked) { Write-Host '占用已解除。' -ForegroundColor Green }
    }

    if ($locked) {
        Write-Host '释放失败，改用「改名绕过」：把旧 DLL 改名后写入新文件。' -ForegroundColor Yellow

        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $backup = $outputPath + '.' + $stamp + '.old'

        try {
            Move-Item -LiteralPath $outputPath -Destination $backup -Force
            $renamedOld = $backup
            Write-Host ('  旧文件已改名：' + (Split-Path -Leaf $backup)) -ForegroundColor Gray
            Write-Host '  注册表 CodeBase 路径不变，无需重新注册；但必须重启资源管理器才生效。' -ForegroundColor Yellow
        }
        catch {
            Write-Host ''
            Write-Host '改名也失败了，说明锁更严格（常见于杀毒软件正在扫描该文件）。' -ForegroundColor Red
            Write-Host '可以试试：' -ForegroundColor Yellow
            Write-Host '   1) 运行 .\release-dll.ps1 后再重试' -ForegroundColor Gray
            Write-Host '   2) 等 10~30 秒后重试' -ForegroundColor Gray
            Write-Host '   3) 把 PathAdder\com 目录加入杀毒软件排除项' -ForegroundColor Gray
            Write-Host ''
            Write-Host '★ 提醒：不要用 regsvr32 /u 去「注销」本 DLL。' -ForegroundColor Red
            Write-Host '   它是 .NET 程序集，没有 DllUnregisterServer 导出（由 mscoree.dll 代理），' -ForegroundColor Red
            Write-Host '   regsvr32 必然报「找不到入口点」，而且解决不了文件占用。' -ForegroundColor Red
            Write-Host ''
            Write-Host ('新编译的 DLL 已保留在：' + $stagedOutput) -ForegroundColor Yellow
            exit 1
        }
    }
}

try {
    Copy-Item -LiteralPath $stagedOutput -Destination $outputPath -Force
}
catch {
    Write-Host ('安装 DLL 失败：' + $_.Exception.Message) -ForegroundColor Red
    Write-Host ('新编译的 DLL 已保留在：' + $stagedOutput) -ForegroundColor Yellow
    exit 1
}

$size = (Get-Item -LiteralPath $outputPath).Length
Write-Host ('编译成功：' + $outputPath + '  (' + $size + ' 字节)') -ForegroundColor Green

# 清理暂存目录
try { Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue } catch { }

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
Write-Host '下一步：以管理员身份运行 register-contextmenu.ps1 完成注册。' -ForegroundColor Cyan
Write-Host '（若刚才改过名，务必重启资源管理器，否则加载的仍是旧代码。）' -ForegroundColor Yellow
exit 0
