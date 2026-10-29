# 打包「史记知识库」Windows 绿色版：单个 exe 启动器 + docs 站点目录
#
# 用法（在仓库根目录或任意位置执行）：
#   powershell -ExecutionPolicy Bypass -File scripts\packaging\build_win_exe.ps1
#   powershell -ExecutionPolicy Bypass -File scripts\packaging\build_win_exe.ps1 -Slim
#   powershell -ExecutionPolicy Bypass -File scripts\packaging\build_win_exe.ps1 -SkipZip
#
# 参数：
#   -Python   指定解释器，默认 python
#   -Slim     精简站点：不打包 docs\wiki\history（约省 258 MB，查看词条历史时不可用）
#   -SkipZip  不生成 zip（目录已经可以直接运行）

param(
    [string]$Python = 'python',
    [switch]$Slim,
    [switch]$SkipZip
)

$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
Set-Location $RepoRoot

$AppName   = 'ShijiKB'
$ExeName   = '史记知识库.exe'
$DistDir   = Join-Path $RepoRoot 'dist'
$BuildDir  = Join-Path $RepoRoot 'build'
$ReleaseDir = Join-Path $RepoRoot 'release'
$OutDir    = Join-Path $ReleaseDir '史记知识库-Windows'
$DocsSrc   = Join-Path $RepoRoot 'docs'
$Launcher  = Join-Path $RepoRoot 'scripts\packaging\shiji_app.py'

if (-not (Test-Path (Join-Path $DocsSrc 'index.html'))) {
    throw "未找到 $DocsSrc\index.html，请确认在仓库根目录执行"
}

Write-Host '[1/5] 检查 PyInstaller'
& $Python -c 'import PyInstaller' 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host '  未安装，开始安装…'
    & $Python -m pip install pyinstaller
    if ($LASTEXITCODE -ne 0) { throw 'PyInstaller 安装失败' }
} else {
    Write-Host '  已安装，跳过'
}

Write-Host '[2/5] 清理旧产物'
foreach ($p in @($BuildDir, $DistDir, $ReleaseDir)) {
    if (Test-Path $p) { Remove-Item $p -Recurse -Force }
}

Write-Host '[3/5] 打包启动器 exe'
& $Python -m PyInstaller `
    --noconfirm --clean --onedir --console `
    --name $AppName `
    --distpath $DistDir --workpath $BuildDir `
    $Launcher
if ($LASTEXITCODE -ne 0) { throw 'PyInstaller 打包失败' }

Write-Host '[4/5] 组装绿色版目录并复制站点'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
Copy-Item -Path (Join-Path $DistDir "$AppName\*") -Destination $OutDir -Recurse -Force
Rename-Item -Path (Join-Path $OutDir "$AppName.exe") -NewName $ExeName

$RoboArgs = @($DocsSrc, (Join-Path $OutDir 'docs'), '/E', '/NFL', '/NDL', '/NJH', '/NJS', '/R:1', '/W:1', '/MT:16')
if ($Slim) {
    $RoboArgs += '/XD'
    $RoboArgs += (Join-Path $DocsSrc 'wiki\history')
    Write-Host '  精简模式：排除 docs\wiki\history'
}
& robocopy @RoboArgs | Out-Null
if ($LASTEXITCODE -ge 8) { throw "复制站点失败，robocopy 退出码 $LASTEXITCODE" }

# robocopy 会把空目录也算成功，这里再校验关键入口
foreach ($f in @('index.html', 'chapters', 'wiki', 'data')) {
    if (-not (Test-Path (Join-Path $OutDir "docs\$f"))) { throw "站点复制不完整，缺少 docs\$f" }
}

if (-not $SkipZip) {
    Write-Host '[5/5] 生成压缩包'
    $ZipPath = Join-Path $ReleaseDir '史记知识库-Windows.zip'
    if (Test-Path $ZipPath) { Remove-Item $ZipPath -Force }
    Compress-Archive -Path $OutDir -DestinationPath $ZipPath -CompressionLevel Optimal
} else {
    Write-Host '[5/5] 跳过压缩包（-SkipZip）'
}

$SizeMB = [math]::Round(((Get-ChildItem $OutDir -Recurse -File | Measure-Object Length -Sum).Sum / 1MB), 1)
$FileCount = (Get-ChildItem $OutDir -Recurse -File).Count

Write-Host ''
Write-Host '打包完成'
Write-Host "  输出目录: $OutDir"
Write-Host "  可执行文件: $(Join-Path $OutDir $ExeName)"
Write-Host "  体积: $SizeMB MB（$FileCount 个文件）"
if (-not $SkipZip) {
    Write-Host "  压缩包: $(Join-Path $ReleaseDir '史记知识库-Windows.zip')"
}
Write-Host ''
Write-Host '分发提示：整个「史记知识库-Windows」目录一起拷贝，双击 exe 即可运行。'
