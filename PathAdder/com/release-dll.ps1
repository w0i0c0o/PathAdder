<#
.SYNOPSIS
    解除 PathAdderShellExt.dll 的文件占用（编译 / 重注册前必做一步）。

.DESCRIPTION
    explorer.exe 一旦加载过本 DLL，就会以
    FILE_SHARE_READ | FILE_SHARE_DELETE 的方式持有它：
      · 允许【改名】（所以 build.ps1 有「改名绕过」）
      · 但不允许【写入 / 覆盖】（所以新 DLL 编不到原路径）

    本脚本把这个占用从根上解除，而不是绕过：

      1. 用 tasklist /m 找出真正把该模块加载进地址空间的进程
      2. 逐个终止（跳过 System / 空闲进程 / 本脚本自身）
      3. 终止了 explorer 就立刻重新拉起（否则桌面会消失）
      4. 轮询等待文件可写，最多 12 秒

    ⚠ 为什么不能用 regsvr32 /u 来「卸载」：
      本 DLL 是 .NET 程序集，没有 DllUnregisterServer 导出（由 mscoree.dll 代理），
      regsvr32 必然报「找不到入口点」，而且它也解除不了文件锁。

.EXAMPLE
    # 释放占用（默认会自动重启资源管理器）
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\release-dll.ps1

    # 只释放、不重启资源管理器（留给调用方自己决定何时重启）
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\release-dll.ps1 -NoRestartExplorer
#>

[CmdletBinding()]
param(
    [switch]$NoRestartExplorer
)

$ErrorActionPreference = 'Continue'

$dllPath = Join-Path $PSScriptRoot 'PathAdderShellExt.dll'
$moduleName = 'PathAdderShellExt'

function Test-DllFree {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $true }
    try {
        $stream = [System.IO.File]::Open($Path, 'Open', 'ReadWrite', 'None')
        $stream.Close()
        $stream.Dispose()
        return $true
    }
    catch {
        return $false
    }
}

# ---------------------------------------------------------------------------
Write-Host '=== 检查 DLL 占用 ===' -ForegroundColor Cyan

if (-not (Test-Path -LiteralPath $dllPath -PathType Leaf)) {
    Write-Host ('DLL 尚不存在：' + $dllPath) -ForegroundColor Gray
    Write-Host '没有东西需要释放，可以直接编译。' -ForegroundColor Green
    exit 0
}

if (Test-DllFree $dllPath) {
    Write-Host 'DLL 未被占用，无需处理。' -ForegroundColor Green
    exit 0
}

Write-Host 'DLL 正被占用，开始释放…' -ForegroundColor Yellow

# ---------------------------------------------------------------------------
# 1. 找出加载了该模块的进程
# ---------------------------------------------------------------------------
$holderPids = @()

try {
    $tasklist = Join-Path $env:WINDIR 'System32\tasklist.exe'
    if (Test-Path -LiteralPath $tasklist -PathType Leaf) {
        # /m <模块名> 只列出加载了该模块的进程，比 /m 全量快得多
        $lines = & $tasklist /m $moduleName /fo csv /nh 2>$null

        foreach ($line in $lines) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            if ($line -notmatch $moduleName) { continue }

            # CSV 形如："explorer.exe","2096","PathAdderShellExt.dll, ..."
            $fields = $line.Split(',')
            if ($fields.Count -lt 2) { continue }

            $pidText = $fields[1].Trim().Trim('"')
            $candidate = 0
            if ([int]::TryParse($pidText, [ref]$candidate)) {
                if ($candidate -gt 4 -and $candidate -ne $PID) { $holderPids += $candidate }
            }
        }
    }
}
catch {
    Write-Host ('  枚举模块持有者失败：' + $_.Exception.Message) -ForegroundColor DarkYellow
}

$holderPids = @($holderPids | Sort-Object -Unique)

if ($holderPids.Count -eq 0) {
    Write-Host '  没查出模块持有者（常见于只持有纯文件句柄的情况），退而求其次：' -ForegroundColor Gray
    Write-Host '  假定是资源管理器，直接重启它。' -ForegroundColor Gray
}
else {
    foreach ($p in $holderPids) {
        $procName = '(未知)'
        try { $procName = (Get-Process -Id $p -ErrorAction Stop).ProcessName } catch { }
        Write-Host ('  持有者：' + $procName + '  pid=' + $p) -ForegroundColor Gray
    }
}

# ---------------------------------------------------------------------------
# 2. 终止持有者
# ---------------------------------------------------------------------------
$killedAny = $false
foreach ($p in $holderPids) {
    try {
        Stop-Process -Id $p -Force -ErrorAction Stop
        Write-Host ('  已终止 pid=' + $p) -ForegroundColor Gray
        $killedAny = $true
    }
    catch {
        Write-Host ('  终止 pid=' + $p + ' 失败：' + $_.Exception.Message) -ForegroundColor DarkYellow
    }
}

# 资源管理器是绝大多数情况下的持有者，无论如何都重启它
$explorerWasRunning = $false
try { $explorerWasRunning = ($null -ne (Get-Process -Name explorer -ErrorAction Stop)) } catch { $explorerWasRunning = $false }

if ($explorerWasRunning) {
    try {
        Get-Process -Name explorer -ErrorAction Stop | Stop-Process -Force -ErrorAction Stop
        Write-Host '  已终止 explorer.exe' -ForegroundColor Gray
        $killedAny = $true
    }
    catch {
        Write-Host ('  终止 explorer 失败：' + $_.Exception.Message) -ForegroundColor DarkYellow
    }
}

# ---------------------------------------------------------------------------
# 3. 重新拉起资源管理器（否则桌面会消失）
# ---------------------------------------------------------------------------
if ($killedAny -and $explorerWasRunning -and (-not $NoRestartExplorer)) {
    Start-Sleep -Milliseconds 800
    try {
        Start-Process -FilePath 'explorer.exe' | Out-Null
        Write-Host '  已重新拉起资源管理器。' -ForegroundColor Gray
    }
    catch {
        Write-Host ('  重启资源管理器失败，请手动执行：Start-Process explorer.exe') -ForegroundColor Yellow
    }
}
elseif ($killedAny -and $explorerWasRunning) {
    Write-Host '  （已指定 -NoRestartExplorer，资源管理器未重启，请稍后自行重启。）' -ForegroundColor Yellow
}

# ---------------------------------------------------------------------------
# 4. 轮询等待文件真正可写
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '=== 等待文件释放 ===' -ForegroundColor Cyan

$elapsed = 0.0
while ($elapsed -lt 12.0) {
    if (Test-DllFree $dllPath) { break }
    Start-Sleep -Milliseconds 400
    $elapsed = $elapsed + 0.4
}

if (Test-DllFree $dllPath) {
    Write-Host ('✓ DLL 已释放（等待 ' + [math]::Round($elapsed, 1) + ' 秒）') -ForegroundColor Green
    exit 0
}

Write-Host ''
Write-Host '✗ 仍然被占用。可能原因：' -ForegroundColor Red
Write-Host '   · 杀毒软件正在扫描该文件 → 等 10~30 秒后重试，或把目录加入排除项' -ForegroundColor Gray
Write-Host '   · 其它非 explorer 的宿主持有句柄 → 重跑本脚本看列出的持有者' -ForegroundColor Gray
Write-Host '   · 仍然不行：注销再登录（比重启快）' -ForegroundColor Gray
Write-Host ''
exit 1
