Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\env_setup_pre_start.log"
try {
    Start-Transcript -Path $logPath -Force | Out-Null
} catch {
    Write-Host "WARNING: Start-Transcript failed: $($_.Exception.Message)"
}

try {
    Write-Host "=== Installing Talon Voice ==="

    # ---- Check if already installed ----
    $talonExe = "C:\Program Files\Talon\talon.exe"
    if (Test-Path $talonExe) {
        Write-Host "Talon already installed at: $talonExe"
        Write-Host "=== Installation skipped (already present) ==="
        return
    }

    # ---- Download Talon EXE installer ----
    # NOTE: The portable .zip from talonvoice.com uses a content-addressable archive
    # format that PowerShell's Expand-Archive cannot handle. Use the .exe installer instead.
    Write-Host "Downloading Talon EXE installer..."
    $talonUrl = "https://talonvoice.com/dl/latest/talon-windows.exe"
    $talonInstaller = "C:\Windows\Temp\talon-windows.exe"

    $prevEAP = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        & curl.exe -L --silent --show-error -o $talonInstaller $talonUrl 2>&1
    } finally {
        $ErrorActionPreference = $prevEAP
    }

    if (-not (Test-Path $talonInstaller)) {
        throw "Talon download failed - installer not found"
    }

    $installerSize = (Get-Item $talonInstaller).Length
    Write-Host "Downloaded installer size: $installerSize bytes"
    if ($installerSize -lt 5000000) {
        throw "Downloaded file too small ($installerSize bytes) - likely download error"
    }

    # ---- Run silent installer ----
    Write-Host "Running Talon installer silently..."
    $proc = Start-Process $talonInstaller -ArgumentList "/S" -PassThru
    $finished = $proc.WaitForExit(180000)
    if ($finished) {
        Write-Host "Installer exit code: $($proc.ExitCode)"
    } else {
        Write-Host "WARNING: Installer still running after 3 minutes"
    }
    Start-Sleep -Seconds 5

    # Verify installation
    if (Test-Path $talonExe) {
        Write-Host "SUCCESS: Talon installed at $talonExe"
    } else {
        Write-Host "WARNING: talon.exe not found at expected path"
        Write-Host "Searching for talon.exe..."
        $found = Get-ChildItem "C:\Program Files" -Recurse -Filter "talon.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) {
            Write-Host "Found at: $($found.FullName)"
        } else {
            Write-Host "talon.exe not found anywhere in Program Files"
        }
    }

    # ---- Download community voice command set ----
    Write-Host "Downloading Talon community command set..."
    $communityUrl = "https://github.com/talonhub/community/archive/refs/heads/main.zip"
    $communityZip = "C:\Windows\Temp\community.zip"

    $prevEAP = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        & curl.exe -L --silent --show-error -o $communityZip $communityUrl 2>&1
    } finally {
        $ErrorActionPreference = $prevEAP
    }

    if (-not (Test-Path $communityZip)) {
        throw "Community command set download failed"
    }

    $commSize = (Get-Item $communityZip).Length
    Write-Host "Community zip size: $commSize bytes"

    # Extract community to Talon user directory
    $talonUserDir = "C:\Users\Docker\AppData\Roaming\Talon\user"
    New-Item -ItemType Directory -Force -Path $talonUserDir | Out-Null

    $commExtract = "C:\Windows\Temp\community_extract"
    if (Test-Path $commExtract) {
        Remove-Item $commExtract -Recurse -Force
    }
    Expand-Archive -Path $communityZip -DestinationPath $commExtract -Force

    # The zip extracts as community-main/
    $commInner = Get-ChildItem $commExtract -Directory | Select-Object -First 1
    if ($commInner) {
        $commSource = $commInner.FullName
    } else {
        $commSource = $commExtract
    }

    $communityDest = Join-Path $talonUserDir "community"
    if (Test-Path $communityDest) {
        Remove-Item $communityDest -Recurse -Force
    }
    Move-Item -Path $commSource -Destination $communityDest -Force

    # Verify community set
    $talonFileCount = (Get-ChildItem $communityDest -Recurse -Filter "*.talon" -ErrorAction SilentlyContinue).Count
    $pyFileCount = (Get-ChildItem $communityDest -Recurse -Filter "*.py" -ErrorAction SilentlyContinue).Count
    Write-Host "Community command set installed: $talonFileCount .talon files, $pyFileCount .py files"

    # ---- Install Notepad++ for editing .talon files ----
    Write-Host "Installing Notepad++ for .talon file editing..."
    $nppUrl = "https://github.com/notepad-plus-plus/notepad-plus-plus/releases/download/v8.7.1/npp.8.7.1.Installer.x64.exe"
    $nppInstaller = "C:\Windows\Temp\npp_installer.exe"

    $prevEAP = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        & curl.exe -L --silent --show-error -o $nppInstaller $nppUrl 2>&1
    } finally {
        $ErrorActionPreference = $prevEAP
    }

    if (Test-Path $nppInstaller) {
        $proc = Start-Process $nppInstaller -ArgumentList "/S" -PassThru -Wait
        Write-Host "Notepad++ installer exit code: $($proc.ExitCode)"
    } else {
        Write-Host "WARNING: Notepad++ download failed, will use built-in Notepad"
    }

    # ---- Cleanup temp files ----
    Remove-Item $talonInstaller -Force -ErrorAction SilentlyContinue
    Remove-Item $communityZip -Force -ErrorAction SilentlyContinue
    Remove-Item "C:\Windows\Temp\community_extract" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item $nppInstaller -Force -ErrorAction SilentlyContinue

    Write-Host "=== Talon Voice installation complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
