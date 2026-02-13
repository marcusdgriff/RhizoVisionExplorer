[CmdletBinding()]
param(
    [string]$CondaExe = "conda",
    [string]$EnvPrefix = "$HOME/.conda/envs/rhizovision-repro",
    [string]$InstallPrefix = "",
    [string]$BuildRoot = "",
    [string]$Generator = "Ninja",
    [string]$CvutilSrc = "",
    [string]$RveSrc = "",
    [switch]$SkipEnvCreate,
    [switch]$Clean
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RveSrcDefault = (Resolve-Path (Join-Path $ScriptDir "..")).Path
$CvutilSrcDefault = (Resolve-Path (Join-Path $RveSrcDefault "..\cvutil")).Path
$EnvFile = Join-Path $ScriptDir "repro-conda-env.yml"

if (-not $RveSrc) {
    $RveSrc = $RveSrcDefault
}
if (-not $CvutilSrc) {
    $CvutilSrc = $CvutilSrcDefault
}
if (-not $InstallPrefix) {
    $InstallPrefix = Join-Path (Split-Path -Parent $RveSrc) "_install\repro"
}
if (-not $BuildRoot) {
    $BuildRoot = Join-Path $RveSrc "build\repro"
}

if (-not (Test-Path $CvutilSrc)) {
    throw "cvutil source path not found: $CvutilSrc"
}
if (-not (Test-Path $RveSrc)) {
    throw "RhizoVisionExplorer source path not found: $RveSrc"
}

if ($Clean) {
    if (Test-Path $BuildRoot) { Remove-Item -Recurse -Force $BuildRoot }
    if (Test-Path $InstallPrefix) { Remove-Item -Recurse -Force $InstallPrefix }
}

New-Item -ItemType Directory -Force -Path $BuildRoot | Out-Null
New-Item -ItemType Directory -Force -Path $InstallPrefix | Out-Null

if (-not $SkipEnvCreate) {
    & $CondaExe env update --prune -p $EnvPrefix -f $EnvFile
}

function Invoke-CondaRun {
    param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Args)
    & $CondaExe run -p $EnvPrefix @Args
}

$CvutilBuildDir = Join-Path $BuildRoot "cvutil"
$RveBuildDir = Join-Path $BuildRoot "rhizovisionexplorer"

$CommonFlags = @(
    "-G", $Generator,
    "-DCMAKE_BUILD_TYPE=Release",
    "-DCMAKE_CXX_STANDARD=17",
    "-DCMAKE_CXX_STANDARD_REQUIRED=ON",
    "-DCMAKE_EXPORT_COMPILE_COMMANDS=ON",
    "-DENABLE_AVX512=OFF",
    "-DENABLE_AVX2_FMA=ON"
)

Write-Host "Configuring cvutil ..."
Invoke-CondaRun cmake -S $CvutilSrc -B $CvutilBuildDir `
    @CommonFlags `
    "-DCMAKE_PREFIX_PATH=$EnvPrefix" `
    "-DCMAKE_INSTALL_PREFIX=$InstallPrefix" `
    "-DCVUTIL_EXPECTED_OPENCV_MAJOR_MINOR=4.11" `
    "-DCVUTIL_EXPECTED_QT_MAJOR_MINOR=6.9" `
    "-DCVUTIL_ENFORCE_DEPENDENCY_MAJOR_MINOR=ON" `
    "-DUSE_MIMALLOC=ON"

Write-Host "Building cvutil ..."
Invoke-CondaRun cmake --build $CvutilBuildDir --parallel
Invoke-CondaRun cmake --install $CvutilBuildDir --prefix $InstallPrefix

Write-Host "Configuring RhizoVisionExplorer ..."
Invoke-CondaRun cmake -S $RveSrc -B $RveBuildDir `
    @CommonFlags `
    "-DCMAKE_PREFIX_PATH=$InstallPrefix;$EnvPrefix" `
    "-DCMAKE_INSTALL_PREFIX=$InstallPrefix" `
    "-Dcvutil_DIR=$InstallPrefix/lib/cmake/cvutil" `
    "-DRHIZO_EXPECTED_OPENCV_MAJOR_MINOR=4.11" `
    "-DRHIZO_EXPECTED_QT_MAJOR_MINOR=6.9" `
    "-DRHIZO_ENFORCE_DEPENDENCY_MAJOR_MINOR=ON"

Write-Host "Building RhizoVisionExplorer ..."
Invoke-CondaRun cmake --build $RveBuildDir --parallel
Invoke-CondaRun cmake --install $RveBuildDir --prefix $InstallPrefix

$CondaList = & $CondaExe list -p $EnvPrefix
$OpenCvLine = $CondaList | Where-Object { $_ -match '^opencv\s+' } | Select-Object -First 1
$QtLine = $CondaList | Where-Object { $_ -match '^qt6-main\s+' } | Select-Object -First 1
if (-not $OpenCvLine) { throw "Could not determine OpenCV package version from conda env: $EnvPrefix" }
if (-not $QtLine) { throw "Could not determine Qt package version from conda env: $EnvPrefix" }
$OpenCvVersion = $OpenCvLine.Split(' ', [System.StringSplitOptions]::RemoveEmptyEntries)[1]
$QtVersion = $QtLine.Split(' ', [System.StringSplitOptions]::RemoveEmptyEntries)[1]

if (-not $OpenCvVersion.StartsWith("4.11.")) {
    throw "OpenCV version mismatch: expected 4.11.x, got $OpenCvVersion"
}
if (-not $QtVersion.StartsWith("6.9.")) {
    throw "Qt version mismatch: expected 6.9.x, got $QtVersion"
}

$Manifest = Join-Path $InstallPrefix "repro-manifest.txt"
@(
    "opencv=$OpenCvVersion"
    "qt=$QtVersion"
    "generator=$Generator"
    "build_type=Release"
    "cxx_standard=17"
    "enable_avx512=OFF"
    "enable_avx2_fma=ON"
    "cvutil_expected_opencv=4.11"
    "cvutil_expected_qt=6.9"
    "rhizo_expected_opencv=4.11"
    "rhizo_expected_qt=6.9"
) | Set-Content -Path $Manifest -Encoding ascii

Write-Host "Reproducible build complete."
Write-Host "Install prefix: $InstallPrefix"
Write-Host "Manifest: $Manifest"
