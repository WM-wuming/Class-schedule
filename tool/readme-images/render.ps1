# Renders the README images from the HTML mockups in this folder.
#
#   powershell -ExecutionPolicy Bypass -File tool\readme-images\render.ps1
#
# The mockups are hand-written HTML that mirrors the real widget tree
# (sizes and colours are copied from lib/theme/course_palette.dart,
# lib/widgets/timetable_grid.dart, lib/screens/*.dart and
# android/app/src/main/res/layout/next_class_widget*.xml), so the pictures stay
# in sync with the code as long as those numbers do.
#
# Needs Microsoft Edge or Google Chrome (headless screenshot). Output goes to
# images\ (*.png, 2x device pixel ratio, transparent margins around the phone).
# ASCII only on purpose: Windows PowerShell 5.1 reads .ps1 as GBK without a BOM.

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$srcDir = $PSScriptRoot
$outDir = Join-Path $repoRoot 'images'
$profileDir = Join-Path $env:TEMP 'wb_readme_edge_profile'

if (-not (Test-Path $outDir)) {
    New-Item -ItemType Directory -Path $outDir | Out-Null
}

$candidates = @(
    (Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application\msedge.exe'),
    (Join-Path $env:ProgramFiles 'Microsoft\Edge\Application\msedge.exe'),
    (Join-Path ${env:ProgramFiles(x86)} 'Google\Chrome\Application\chrome.exe'),
    (Join-Path $env:ProgramFiles 'Google\Chrome\Application\chrome.exe')
) | Where-Object { $_ -and (Test-Path $_) }

if (-not $candidates -or @($candidates).Count -eq 0) {
    throw 'Neither Microsoft Edge nor Google Chrome was found.'
}
# @() keeps this working when only one candidate matched.
$browser = @($candidates)[0]

$pages = @(
    @{ html = 'logo.html';         out = 'logo.png';                    w = 256;  h = 256 },
    @{ html = 'timetable.html';    out = 'screenshot-timetable.png';    w = 466;  h = 920 },
    @{ html = 'detail.html';       out = 'screenshot-course-detail.png'; w = 466; h = 920 },
    @{ html = 'classroom.html';    out = 'screenshot-classroom.png';    w = 466;  h = 920 },
    @{ html = 'login.html';        out = 'screenshot-login.png';        w = 466;  h = 920 },
    @{ html = 'widgets.html';      out = 'widget-size-reference.png';   w = 980;  h = 620 },
    @{ html = 'architecture.html'; out = 'architecture-reference.png';  w = 1080; h = 640 }
)

$srcUrl = 'file:///' + ($srcDir -replace '\\', '/')

foreach ($page in $pages) {
    $target = Join-Path $outDir $page.out
    $edgeArgs = @(
        '--headless=new',
        '--disable-gpu',
        '--no-sandbox',
        '--hide-scrollbars',
        '--virtual-time-budget=4000',
        '--force-device-scale-factor=2',
        '--default-background-color=00000000',
        "--user-data-dir=$profileDir",
        "--screenshot=$target",
        "--window-size=$($page.w),$($page.h)",
        "$srcUrl/$($page.html)"
    )
    & $browser @edgeArgs | Out-Null
    if (-not (Test-Path $target)) {
        throw "Screenshot failed: $($page.out)"
    }
    Write-Output "rendered $($page.out)"
}

Write-Output "done -> $outDir"
