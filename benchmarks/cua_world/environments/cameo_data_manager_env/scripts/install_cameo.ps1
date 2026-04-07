Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\env_setup_pre_start.log"
Start-Transcript -Path $logPath -Force | Out-Null

Write-Host "=== Installing CAMEO Data Manager ==="
Write-Host "Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"

# ============================================================
# Phase 1: Prepare directories
# ============================================================
Write-Host "`n--- Phase 1: Preparing directories ---"
$tempDir = "C:\temp\cameo_install"
New-Item -ItemType Directory -Force -Path $tempDir | Out-Null
New-Item -ItemType Directory -Force -Path "C:\Users\Docker\Documents\CAMEO" | Out-Null

# ============================================================
# Phase 2: Get CAMEO Data Manager installer
# ============================================================
Write-Host "`n--- Phase 2: Getting CAMEO Data Manager installer ---"

$installerPath = "$tempDir\cameodatamanager451installer.exe"

# Prefer mounted installer (faster, no network dependency)
$mountedInstaller = "C:\workspace\data\cameodatamanager451installer.exe"
$downloaded = $false

if (Test-Path $mountedInstaller) {
    Write-Host "Using pre-mounted installer from data directory"
    Copy-Item $mountedInstaller $installerPath -Force
    $downloaded = $true
    Write-Host "Installer size: $((Get-Item $installerPath).Length / 1MB) MB"
}

# Fallback: download from EPA
if (-not $downloaded) {
    $url = "https://www.epa.gov/system/files/other-files/2025-12/cameodatamanager451installer.exe"
    Write-Host "Downloading from: $url"
    try {
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $url -OutFile $installerPath -UseBasicParsing -TimeoutSec 300
        if ((Test-Path $installerPath) -and (Get-Item $installerPath).Length -gt 1MB) {
            Write-Host "Download successful: $((Get-Item $installerPath).Length / 1MB) MB"
            $downloaded = $true
        }
    } catch {
        Write-Host "Download failed: $_"
    }
}

if (-not $downloaded) {
    Write-Host "ERROR: Failed to obtain CAMEO Data Manager installer"
    Stop-Transcript
    exit 1
}

# ============================================================
# Phase 3: Install CAMEO Data Manager (InnoSetup 5.5.7)
# ============================================================
Write-Host "`n--- Phase 3: Installing CAMEO Data Manager (InnoSetup silent) ---"

# CAMEO Data Manager uses InnoSetup 5.5.7 - use /VERYSILENT flag
Write-Host "Running: $installerPath /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP-"
$result = Start-Process -FilePath $installerPath `
    -ArgumentList "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP-" `
    -Wait -PassThru
$exitCode = $result.ExitCode
Write-Host "Installer exit code: $exitCode"

if ($exitCode -ne 0 -and $exitCode -ne 3010) {
    Write-Host "WARNING: InnoSetup silent install returned unexpected exit code: $exitCode"
    Write-Host "Continuing anyway to check if installation succeeded..."
}

# Give Windows time to finalize file operations
Start-Sleep -Seconds 5

# ============================================================
# Phase 4: Locate CAMEO Data Manager executable
# ============================================================
Write-Host "`n--- Phase 4: Locating CAMEO Data Manager executable ---"

$cameoExe = $null
$searchPaths = @(
    "C:\Program Files (x86)\CAMEO Data Manager 4.5.1\CAMEO Data Manager.exe",
    "C:\Program Files\CAMEO Data Manager 4.5.1\CAMEO Data Manager.exe",
    "C:\Program Files (x86)\CAMEO Data Manager\CAMEO Data Manager.exe",
    "C:\Program Files\CAMEO Data Manager\CAMEO Data Manager.exe"
)

foreach ($path in $searchPaths) {
    if (Test-Path $path) {
        $cameoExe = $path
        Write-Host "Found CAMEO executable: $cameoExe"
        break
    }
}

# Broader search if not found at expected paths
if (-not $cameoExe) {
    Write-Host "Searching more broadly..."
    $found = Get-ChildItem "C:\Program Files", "C:\Program Files (x86)" -Recurse -Filter "CAMEO Data Manager.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found) {
        $cameoExe = $found.FullName
        Write-Host "Found CAMEO executable: $cameoExe"
    }
}

if ($cameoExe) {
    Set-Content -Path "C:\Users\Docker\cameo_path.txt" -Value $cameoExe -Encoding UTF8
    Write-Host "CAMEO executable path saved to C:\Users\Docker\cameo_path.txt"
} else {
    Write-Host "WARNING: Could not locate CAMEO Data Manager executable"
    Write-Host "Listing contents of Program Files directories:"
    Get-ChildItem "C:\Program Files" -ErrorAction SilentlyContinue | ForEach-Object { Write-Host "  PF: $($_.Name)" }
    Get-ChildItem "C:\Program Files (x86)" -ErrorAction SilentlyContinue | ForEach-Object { Write-Host "  PF86: $($_.Name)" }
}

# ============================================================
# Phase 5: Copy Tier II data files to Documents
# ============================================================
Write-Host "`n--- Phase 5: Copying data files ---"

$dataSource = "C:\workspace\data"
$dataDest = "C:\Users\Docker\Documents\CAMEO"

if (Test-Path "$dataSource\epcra_tier2_data.xml") {
    Copy-Item "$dataSource\epcra_tier2_data.xml" "$dataDest\epcra_tier2_data.xml" -Force
    Write-Host "Copied Tier II sample data XML to Documents\CAMEO"
}

# ============================================================
# Phase 6: Create desktop shortcut
# ============================================================
Write-Host "`n--- Phase 6: Creating desktop shortcut ---"

if ($cameoExe) {
    $shortcutPath = "C:\Users\Docker\Desktop\CAMEO Data Manager.lnk"
    try {
        $wshell = New-Object -ComObject WScript.Shell
        $shortcut = $wshell.CreateShortcut($shortcutPath)
        $shortcut.TargetPath = $cameoExe
        $shortcut.WorkingDirectory = (Split-Path $cameoExe)
        $shortcut.Description = "CAMEO Data Manager"
        $shortcut.Save()
        Write-Host "Desktop shortcut created"
    } catch {
        Write-Host "Failed to create shortcut: $_"
    }
}

# ============================================================
# Phase 7: Cleanup
# ============================================================
Write-Host "`n--- Phase 7: Cleanup ---"
Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue

Set-Content -Path "C:\Users\Docker\cameo_install_complete.marker" -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -Encoding UTF8

Write-Host "`n=== CAMEO Data Manager installation complete ==="
Stop-Transcript
