param(
    [ValidateSet('check', 'apk', 'release', 'run')]
    [string]$Task = 'check'
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$original = Get-Location
$mapped = $null
$oldJava = $env:JAVA_HOME
$oldAndroid = $env:ANDROID_HOME
$oldGradle = $env:GRADLE_OPTS
$flutterCommand = Get-Command flutter -ErrorAction SilentlyContinue
$flutter = if ($flutterCommand) { $flutterCommand.Source } else {
    Join-Path $env:USERPROFILE '.codex\cache\flutter\bin\flutter.bat'
}
if (!(Test-Path -LiteralPath $flutter)) { throw 'Install Flutter, or add it to PATH.' }
$dart = Join-Path (Split-Path $flutter) 'dart.bat'
$cachedTools = Join-Path $env:USERPROFILE '.codex\cache\lan-cards-tools'

try {
    # A temporary drive maps this exact workspace without moving any files.
    # It avoids tool-chain Unicode-path issues on Windows; /D only unmaps it.
    foreach ($letter in @('P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z')) {
        if (!(Test-Path -LiteralPath ($letter + ':\'))) {
            & subst.exe ($letter + ':') $root
            if ($LASTEXITCODE -eq 0) { $mapped = $letter; break }
        }
    }
    if ($mapped) { Set-Location ($mapped + ':\') } else { Set-Location $root }
    if (!$env:JAVA_HOME -and (Test-Path -LiteralPath "$cachedTools\jdk\bin\java.exe")) {
        $env:JAVA_HOME = "$cachedTools\jdk"
    }
    if (!$env:ANDROID_HOME -and (Test-Path -LiteralPath "$cachedTools\android-sdk")) {
        $env:ANDROID_HOME = "$cachedTools\android-sdk"
    }
    $env:GRADLE_OPTS = "$oldGradle -Dorg.gradle.daemon=false"
    & $flutter pub get
    if ($LASTEXITCODE -ne 0) { throw 'Dependency resolution failed.' }
    switch ($Task) {
        'check' {
            & $dart analyze --format machine lib test tool
            if ($LASTEXITCODE -ne 0) { throw 'Static analysis failed.' }
            & $flutter test --no-pub --reporter expanded
        }
        'apk' { & $flutter build apk --debug --no-pub --target-platform android-arm64 }
        'release' { & $flutter build apk --release --no-pub --target-platform android-arm64 }
        'run' { & $flutter run --no-pub }
    }
    if ($LASTEXITCODE -ne 0) { throw "$Task failed." }
} finally {
    Set-Location $original
    if ($mapped) { & subst.exe ($mapped + ':') /D }
    $env:JAVA_HOME = $oldJava
    $env:ANDROID_HOME = $oldAndroid
    $env:GRADLE_OPTS = $oldGradle
}
