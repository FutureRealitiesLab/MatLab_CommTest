<#
.SYNOPSIS
  Richtet einen Windows-Rechner fuer den APK-Export (Vive Focus Vision) ein.

.DESCRIPTION
  Idempotent: Vorhandenes wird uebersprungen. Installiert/erzeugt:
    1. OpenJDK 17 (winget)
    2. Android SDK (Command-line Tools, Platform, Build-Tools, NDK, CMake)
    3. Godot-Export-Templates (passend zur Godot-Version)
    4. Android-Build-Template im Projekt (godot/android/build)
    5. OpenXR-Vendors-Plugin (godot/addons/godotopenxrvendors)
    6. Debug-Keystore
    7. Java- und SDK-Pfad in den Godot-Editoreinstellungen (Godot vorher schliessen!)
  export_presets.cfg liegt im Repo und wird nicht angefasst.

  Beim Ausfuehren werden die Android-SDK-Lizenzen akzeptiert.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools\setup_android.ps1
#>
param(
    [string]$GodotVersion = "4.7.2",
    [string]$VendorsVersion = "5.1.0-stable",
    [string]$CmdlineToolsFile = "commandlinetools-win-15859902_latest.zip",
    [string]$CmdlineToolsSha256 = "90ae805d20434428bffcb699c290860f19bb5f66a67e6b330067e3de801fb04a"
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$repo = Split-Path -Parent $PSScriptRoot
$project = Join-Path $repo "godot"
$sdk = Join-Path $env:LOCALAPPDATA "Android\Sdk"
$tmp = Join-Path $env:TEMP "matlab_commtest_setup"
New-Item -ItemType Directory -Force $tmp | Out-Null

if (Get-Process | Where-Object { $_.ProcessName -like "Godot*" }) {
    Write-Warning "Godot laeuft. Bitte schliessen, sonst ueberschreibt der Editor die Einstellungen beim Beenden."
}

# 1. JDK 17
function Find-Jdk { Get-ChildItem "C:\Program Files\Microsoft" -Directory -ErrorAction SilentlyContinue | Where-Object Name -like "jdk-17*" | Select-Object -First 1 }
if (-not (Find-Jdk)) {
    Write-Host "JDK 17 installieren ..."
    winget install --id Microsoft.OpenJDK.17 -e --accept-source-agreements --accept-package-agreements --silent
}
$jdk = (Find-Jdk).FullName
$env:JAVA_HOME = $jdk
Write-Host "JDK: $jdk"

# 2. Android SDK
$sm = Join-Path $sdk "cmdline-tools\latest\bin\sdkmanager.bat"
if (-not (Test-Path $sm)) {
    Write-Host "Android Command-line Tools laden ..."
    $zip = Join-Path $tmp $CmdlineToolsFile
    Invoke-WebRequest -Uri "https://dl.google.com/android/repository/$CmdlineToolsFile" -OutFile $zip -UseBasicParsing
    if ((Get-FileHash $zip -Algorithm SHA256).Hash -ne $CmdlineToolsSha256.ToUpper()) { throw "Pruefsumme der Command-line Tools stimmt nicht." }
    $ct = Join-Path $sdk "cmdline-tools"
    New-Item -ItemType Directory -Force $ct | Out-Null
    tar -xf $zip -C $ct
    Rename-Item (Join-Path $ct "cmdline-tools") "latest"
}
$yes = Join-Path $tmp "yes.txt"
("y`r`n" * 20) | Set-Content $yes -NoNewline
cmd /c "`"$sm`" --sdk_root=`"$sdk`" --licenses < `"$yes`"" | Out-Null
& $sm --sdk_root=$sdk "platform-tools" "build-tools;36.1.0" "platforms;android-36" "ndk;29.0.14206865" "cmake;3.22.1"

# 3. Export-Templates
$tplDir = Join-Path $env:APPDATA "Godot\export_templates\$GodotVersion.stable"
if (-not (Test-Path (Join-Path $tplDir "android_source.zip"))) {
    Write-Host "Godot-Export-Templates laden (ca. 1,3 GB) ..."
    $tpz = Join-Path $tmp "templates.zip"
    Invoke-WebRequest -Uri "https://github.com/godotengine/godot-builds/releases/download/$GodotVersion-stable/Godot_v$GodotVersion-stable_export_templates.tpz" -OutFile $tpz -UseBasicParsing
    $x = Join-Path $tmp "templates"
    New-Item -ItemType Directory -Force $x | Out-Null
    tar -xf $tpz -C $x
    New-Item -ItemType Directory -Force $tplDir | Out-Null
    Copy-Item (Join-Path $x "templates\*") $tplDir -Recurse -Force
}

# 4. Android-Build-Template im Projekt
$build = Join-Path $project "android\build"
$ver = Join-Path $project "android\.build_version"
if (-not (Test-Path $build) -or -not (Test-Path $ver) -or (Get-Content $ver -Raw).Trim() -ne "$GodotVersion.stable") {
    Write-Host "Android-Build-Template installieren ..."
    Remove-Item $build -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force $build | Out-Null
    tar -xf (Join-Path $tplDir "android_source.zip") -C $build
    New-Item -ItemType File -Force (Join-Path $build ".gdignore") | Out-Null
    "$GodotVersion.stable" | Set-Content $ver -NoNewline -Encoding ascii
}

# 5. OpenXR-Vendors-Plugin
$plugin = Join-Path $project "addons\godotopenxrvendors"
if (-not (Test-Path (Join-Path $plugin "plugin.gdextension"))) {
    Write-Host "OpenXR-Vendors-Plugin $VendorsVersion laden ..."
    $vz = Join-Path $tmp "vendors.zip"
    Invoke-WebRequest -Uri "https://github.com/GodotVR/godot_openxr_vendors/releases/download/$VendorsVersion/godotopenxrvendorsaddon.zip" -OutFile $vz -UseBasicParsing
    $vx = Join-Path $tmp "vendors"
    Remove-Item $vx -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force $vx | Out-Null
    tar -xf $vz -C $vx
    New-Item -ItemType Directory -Force (Join-Path $project "addons") | Out-Null
    # macOS-Framework enthaelt Symlinks, die unter Windows nicht entpackt werden; wird hier nicht gebraucht.
    Copy-Item (Join-Path $vx "asset\addons\godotopenxrvendors") $plugin -Recurse -Force -ErrorAction SilentlyContinue
}

# 6. Debug-Keystore
$ks = Join-Path $env:APPDATA "Godot\keystores\debug.keystore"
if (-not (Test-Path $ks)) {
    New-Item -ItemType Directory -Force (Split-Path $ks) | Out-Null
    & (Join-Path $jdk "bin\keytool.exe") -keyalg RSA -genkeypair -alias androiddebugkey -keypass android -keystore $ks -storepass android -dname "CN=Android Debug,O=Android,C=US" -validity 9999 -deststoretype pkcs12 | Out-Null
}

# 7. Godot-Editoreinstellungen
$settings = Join-Path $env:APPDATA "Godot\editor_settings-$($GodotVersion.Substring(0, $GodotVersion.LastIndexOf('.'))).tres"
if (Test-Path $settings) {
    $text = [System.IO.File]::ReadAllText($settings)
    $jdkSlash = $jdk.Replace("\", "/")
    $sdkSlash = $sdk.Replace("\", "/")
    $ksSlash = $ks.Replace("\", "/")
    foreach ($pair in @(
        @("export/android/java_sdk_path", $jdkSlash),
        @("export/android/android_sdk_path", $sdkSlash),
        @("export/android/debug_keystore", $ksSlash),
        @("export/android/debug_keystore_user", "androiddebugkey"),
        @("export/android/debug_keystore_pass", "android"))) {
        $line = "$($pair[0]) = `"$($pair[1])`""
        if ($text -match "(?m)^$([regex]::Escape($pair[0])) = .*$") {
            $text = $text -replace "(?m)^$([regex]::Escape($pair[0])) = .*$", $line.Replace('$', '$$')
        } else {
            $text = $text.TrimEnd() + "`n$line`n"
        }
    }
    [System.IO.File]::WriteAllText($settings, $text, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host "Editoreinstellungen aktualisiert: $settings"
} else {
    Write-Warning "Keine Editoreinstellungen gefunden ($settings). Godot einmal starten und das Skript erneut ausfuehren, oder die Pfade unter Editor > Editoreinstellungen > Export > Android von Hand setzen."
}

Write-Host "`nFertig. Export per Kommandozeile (aus dem Repo-Ordner):"
Write-Host "  `$env:JAVA_HOME = `"$jdk`""
Write-Host '  Godot --headless --path godot --export-debug "Vive_LBE" build/vive_lbe.apk'
