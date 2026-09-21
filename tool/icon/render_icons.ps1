# 由 app_icon.svg 里的字形生成各平台图标。
#
# 为什么要这么一个脚本：本机没有 ImageMagick / Inkscape / rsvg-convert，
# 但系统自带 Edge，可以用无头截图把 SVG 栅格化成 PNG（含透明背景）。
#
# 做法：先用 Edge 渲出几张 1024x1024 的「主图」，再用 .NET(System.Drawing) 高质量缩放到各尺寸。
# 不能直接让 Edge 按目标尺寸截图 —— Windows 上小窗口会被钳制，小于约 512px 的截图基本是空白。
#
# 用法（在仓库根目录）：
#   powershell -ExecutionPolicy Bypass -File tool\icon\render_icons.ps1
#
# 产出：
#   android/.../mipmap-*/ic_launcher.png、ic_launcher_round.png（API 24/25 用的位图）
#   web/icons/*.png、web/favicon.png
#   ios/Runner/Assets.xcassets/AppIcon.appiconset/*.png
#   macos/Runner/Assets.xcassets/AppIcon.appiconset/*.png
#   tool/icon/app_icon_1024.png（预览用）
# API 26+ 的自适应图标走 res/drawable 下的矢量，不在这里生成。
#
# 注意：本文件必须存成 **UTF-8 with BOM**。Windows PowerShell 5.1 读无 BOM 的 .ps1
# 会按 GBK 解码，中文注释会变成乱码并直接语法报错。

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Add-Type -AssemblyName System.Drawing

$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if (-not (Test-Path (Join-Path $root 'pubspec.yaml'))) {
    throw "找不到仓库根目录（当前推断为 $root）"
}

$edge = @(
    'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe',
    'C:\Program Files\Microsoft\Edge\Application\msedge.exe',
    'C:\Program Files\Google\Chrome\Application\chrome.exe',
    'C:\Program Files (x86)\Google\Chrome\Application\chrome.exe'
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $edge) { throw '找不到 Edge / Chrome，无法把 SVG 栅格化成 PNG' }

# 字形来自 app_icon.svg（24x24 视口，人物捧书）
$glyph = 'M9 6c0-1.65685 1.3431-3 3-3s3 1.34315 3 3-1.3431 3-3 3-3-1.34315-3-3Zm2 3.62992c-.1263-.04413-.25-.08799-.3721-.13131-1.33928-.47482-2.49256-.88372-4.77995-.8482C4.84875 8.66593 4 9.46413 4 10.5v7.2884c0 1.0878.91948 1.8747 1.92888 1.8616 1.283-.0168 2.04625.1322 2.79671.3587.29285.0883.57733.1863.90372.2987l.00249.0008c.11983.0413.24534.0845.379.1299.2989.1015.6242.2088.9892.3185V9.62992Zm2-.00374V20.7551c.5531-.1678 1.0379-.3374 1.4545-.4832.2956-.1034.5575-.1951.7846-.2653.7257-.2245 1.4655-.3734 2.7479-.3566.5019.0065.9806-.1791 1.3407-.4788.3618-.3011.6723-.781.6723-1.3828V10.5c0-.58114-.2923-1.05022-.6377-1.3503-.3441-.29904-.8047-.49168-1.2944-.49929-2.2667-.0352-3.386.36906-4.6847.83812-.1256.04539-.253.09138-.3832.13765Z'

$masterSize = 1024   # 必须够大：Edge 的小窗口截图在 Windows 上会被钳制成空白
$tmp = Join-Path $env:TEMP 'cs_icon_render'
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
$profile = Join-Path $tmp 'profile'
New-Item -ItemType Directory -Force -Path $profile | Out-Null

# 用 Edge 渲一张 [masterSize]x[masterSize] 的主图
function New-Master {
    param(
        [Parameter(Mandatory)][string]$Out,
        [Parameter(Mandatory)][ValidateSet('rounded', 'circle', 'square')][string]$Shape,
        [Parameter(Mandatory)][double]$Ratio
    )

    $s = $masterSize
    $radius = [Math]::Round($s * 0.22, 2)
    $glyphSize = [Math]::Round($s * $Ratio, 2)

    $radiusCss = ''
    if ($Shape -eq 'rounded') { $radiusCss = "border-radius:${radius}px;" }
    if ($Shape -eq 'circle') { $radiusCss = 'border-radius:50%;' }

    $html = @"
<!doctype html>
<html><head><meta charset="utf-8"><style>
html,body{margin:0;padding:0;width:${s}px;height:${s}px;background:transparent;overflow:hidden}
.bg{position:fixed;inset:0;background:linear-gradient(160deg,#4A80F0 0%,#2C63D4 48%,#1B47A8 100%);$radiusCss}
svg{position:fixed;left:50%;top:50%;transform:translate(-50%,-50%);width:${glyphSize}px;height:${glyphSize}px;fill:#fff}
</style></head>
<body>
<div class="bg"></div>
<svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><path d="$glyph"/></svg>
</body></html>
"@

    $page = Join-Path $tmp 'page.html'
    [System.IO.File]::WriteAllText($page, $html, (New-Object System.Text.UTF8Encoding($false)))

    $staged = Join-Path $tmp 'shot.png'
    if (Test-Path $staged) { Remove-Item -LiteralPath $staged -Force }

    $cmdArgs = @(
        '--headless=new'
        '--disable-gpu'
        '--no-sandbox'
        '--disable-features=Translate'
        "--user-data-dir=$profile"
        '--hide-scrollbars'
        '--force-device-scale-factor=1'
        '--default-background-color=00000000'
        "--window-size=$s,$s"
        '--virtual-time-budget=3000'
        "--screenshot=$staged"
        ('file:///' + ($page -replace '\\', '/'))
    )

    # Edge 会往 stderr 吐无关告警（QQBrowser 路径之类），
    # 在 $ErrorActionPreference='Stop' 下这些噪音会被当成终止错误，所以这里临时放宽。
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & $edge @cmdArgs 2>&1 | Out-Null
    }
    finally {
        $ErrorActionPreference = $previous
    }

    if (-not (Test-Path $staged)) { throw "主图渲染失败：$Out（${s}px, $Shape）" }
    Move-Item -LiteralPath $staged -Destination $Out -Force
    Write-Host ("主图 {0}（{1}，字形占比 {2:P0}）" -f (Split-Path -Leaf $Out), $Shape, $Ratio)
}

# 把主图缩放到 [Size]x[Size]。iOS 图标不允许带透明通道，用 -NoAlpha 落成 24 位。
function Resize-Png {
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Out,
        [Parameter(Mandatory)][int]$Size,
        [switch]$NoAlpha
    )

    $format = if ($NoAlpha) {
        [System.Drawing.Imaging.PixelFormat]::Format24bppRgb
    }
    else {
        [System.Drawing.Imaging.PixelFormat]::Format32bppArgb
    }

    $src = [System.Drawing.Image]::FromFile($Source)
    try {
        $dst = New-Object System.Drawing.Bitmap($Size, $Size, $format)
        try {
            $graphics = [System.Drawing.Graphics]::FromImage($dst)
            try {
                $graphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
                $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
                $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
                $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
                $rect = New-Object System.Drawing.Rectangle(0, 0, $Size, $Size)
                $graphics.DrawImage($src, $rect)
            }
            finally { $graphics.Dispose() }

            $dir = Split-Path -Parent $Out
            New-Item -ItemType Directory -Force -Path $dir | Out-Null
            $dst.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
        }
        finally { $dst.Dispose() }
    }
    finally { $src.Dispose() }
}

# --- 4 张主图 ---
$mRounded = Join-Path $tmp 'm_rounded.png'    # 安卓旧版 / macOS / favicon
$mCircle = Join-Path $tmp 'm_circle.png'      # 安卓圆形启动器
$mMaskable = Join-Path $tmp 'm_maskable.png'  # Web maskable（多留边距给系统裁切）
$mFull = Join-Path $tmp 'm_full.png'          # iOS（满幅，圆角交给系统）

New-Master -Out $mRounded -Shape 'rounded' -Ratio 0.60
New-Master -Out $mCircle -Shape 'circle' -Ratio 0.60
New-Master -Out $mMaskable -Shape 'square' -Ratio 0.50
New-Master -Out $mFull -Shape 'square' -Ratio 0.64

$targets = [System.Collections.Generic.List[hashtable]]::new()
function Add-Target {
    param([string]$Master, [string]$Rel, [int]$Size, [switch]$NoAlpha)
    $targets.Add(@{
            Master  = $Master
            Out     = (Join-Path $root $Rel)
            Size    = $Size
            NoAlpha = [bool]$NoAlpha
        })
}

# --- Android：API 24/25 的位图（API 26+ 用矢量自适应图标） ---
$densities = @{ 'mdpi' = 48; 'hdpi' = 72; 'xhdpi' = 96; 'xxhdpi' = 144; 'xxxhdpi' = 192 }
foreach ($d in $densities.Keys) {
    $base = "android\app\src\main\res\mipmap-$d"
    Add-Target $mRounded "$base\ic_launcher.png" $densities[$d]
    Add-Target $mCircle "$base\ic_launcher_round.png" $densities[$d]
}

# --- Web ---
Add-Target $mRounded 'web\favicon.png' 32
Add-Target $mRounded 'web\icons\Icon-192.png' 192
Add-Target $mRounded 'web\icons\Icon-512.png' 512
Add-Target $mMaskable 'web\icons\Icon-maskable-192.png' 192
Add-Target $mMaskable 'web\icons\Icon-maskable-512.png' 512

# --- iOS：不允许透明通道，满幅方图 ---
$ios = 'ios\Runner\Assets.xcassets\AppIcon.appiconset'
Add-Target $mFull "$ios\Icon-App-20x20@1x.png" 20 -NoAlpha
Add-Target $mFull "$ios\Icon-App-20x20@2x.png" 40 -NoAlpha
Add-Target $mFull "$ios\Icon-App-20x20@3x.png" 60 -NoAlpha
Add-Target $mFull "$ios\Icon-App-29x29@1x.png" 29 -NoAlpha
Add-Target $mFull "$ios\Icon-App-29x29@2x.png" 58 -NoAlpha
Add-Target $mFull "$ios\Icon-App-29x29@3x.png" 87 -NoAlpha
Add-Target $mFull "$ios\Icon-App-40x40@1x.png" 40 -NoAlpha
Add-Target $mFull "$ios\Icon-App-40x40@2x.png" 80 -NoAlpha
Add-Target $mFull "$ios\Icon-App-40x40@3x.png" 120 -NoAlpha
Add-Target $mFull "$ios\Icon-App-60x60@2x.png" 120 -NoAlpha
Add-Target $mFull "$ios\Icon-App-60x60@3x.png" 180 -NoAlpha
Add-Target $mFull "$ios\Icon-App-76x76@1x.png" 76 -NoAlpha
Add-Target $mFull "$ios\Icon-App-76x76@2x.png" 152 -NoAlpha
Add-Target $mFull "$ios\Icon-App-83.5x83.5@2x.png" 167 -NoAlpha
Add-Target $mFull "$ios\Icon-App-1024x1024@1x.png" 1024 -NoAlpha

# --- macOS ---
$mac = 'macos\Runner\Assets.xcassets\AppIcon.appiconset'
foreach ($size in 16, 32, 64, 128, 256, 512, 1024) {
    Add-Target $mRounded "$mac\app_icon_$size.png" $size
}

$i = 0
foreach ($t in $targets) {
    $i++
    Write-Host ("[{0}/{1}] {2} ({3}px)" -f $i, $targets.Count, $t.Out, $t.Size)
    Resize-Png -Source $t.Master -Out $t.Out -Size $t.Size -NoAlpha:$t.NoAlpha
}

# 顺手留一份 1024 的成品，方便以后做商店截图 / 快速预览
Resize-Png -Source $mRounded -Out (Join-Path $root 'tool\icon\app_icon_1024.png') -Size 1024

Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
Write-Host ("完成：4 张主图 + {0} 个图标" -f ($targets.Count + 1))
