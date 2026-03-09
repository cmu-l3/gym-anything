Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Install eQUEST 3.65 (DOE-2.2 building energy simulation tool).
# This script runs as the pre_start hook.

$logPath = "C:\Users\Docker\env_setup_pre_start.log"
try {
    Start-Transcript -Path $logPath -Force | Out-Null
} catch {
    Write-Host "WARNING: Start-Transcript failed: $($_.Exception.Message)"
}

try {
    Write-Host "=== Installing eQUEST 3.65 ==="

    # Check if eQUEST is already installed (directory may include build number)
    $eqDirs = Get-ChildItem "C:\Program Files (x86)" -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "eQUEST 3-65*" }
    if (-not $eqDirs) {
        $eqDirs = Get-ChildItem "C:\Program Files" -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "eQUEST 3-65*" }
    }
    if ($eqDirs) {
        foreach ($d in $eqDirs) {
            if (Test-Path "$($d.FullName)\eQUEST.exe") {
                Write-Host "eQUEST is already installed at: $($d.FullName)"
                return
            }
        }
    }

    # Create temp working directory
    $workDir = "C:\eQUEST_Install"
    New-Item -ItemType Directory -Force -Path $workDir | Out-Null

    # Download eQUEST 3.65 from official DOE-2 site
    # Use curl.exe (bundled with Windows 11) instead of Invoke-WebRequest for reliability
    Write-Host "Downloading eQUEST 3.65 from doe2.com..."
    $zipUrl = "https://doe2.com/Download/equest/eQUEST_3-65_Build7175_2018-10-04.zip"
    $zipPath = "$workDir\equest.zip"

    # Retry download up to 3 times using curl.exe
    $maxRetries = 3
    $downloaded = $false
    for ($i = 1; $i -le $maxRetries; $i++) {
        Write-Host "Download attempt $i of $maxRetries..."
        $curlProc = Start-Process -FilePath "curl.exe" -ArgumentList "-L --connect-timeout 30 --max-time 600 -o `"$zipPath`" `"$zipUrl`"" -Wait -PassThru -NoNewWindow
        if ($curlProc.ExitCode -eq 0 -and (Test-Path $zipPath)) {
            $fileSize = (Get-Item $zipPath).Length
            Write-Host "Downloaded: $([math]::Round($fileSize / 1MB, 1)) MB"
            if ($fileSize -gt 1000000) {
                $downloaded = $true
                break
            }
        }
        Write-Host "Download attempt $i failed (exit code: $($curlProc.ExitCode))"
        if ($i -lt $maxRetries) {
            Start-Sleep -Seconds 10
        }
    }

    if (-not $downloaded) {
        throw "Failed to download eQUEST after $maxRetries attempts."
    }

    # Extract ZIP
    Write-Host "Extracting eQUEST archive..."
    $extractDir = "$workDir\extracted"
    Expand-Archive -Path $zipPath -DestinationPath $extractDir -Force
    Write-Host "Archive extracted to: $extractDir"

    # Find the MSI installer in the extracted files
    $msiFile = Get-ChildItem $extractDir -Recurse -Filter "*.msi" | Select-Object -First 1
    if (-not $msiFile) {
        # If no MSI, look for setup.exe or other installers
        $setupExe = Get-ChildItem $extractDir -Recurse -Filter "setup.exe" | Select-Object -First 1
        if (-not $setupExe) {
            $setupExe = Get-ChildItem $extractDir -Recurse -Filter "*.exe" | Select-Object -First 1
        }
        if ($setupExe) {
            Write-Host "Found installer: $($setupExe.FullName)"
            Write-Host "Running installer..."
            $proc = Start-Process -FilePath $setupExe.FullName -ArgumentList "/S /SILENT /VERYSILENT /NORESTART" -Wait -PassThru -NoNewWindow
            Write-Host "Installer exited with code: $($proc.ExitCode)"
        } else {
            # List contents for debugging
            Write-Host "No MSI or EXE installer found. Contents:"
            Get-ChildItem $extractDir -Recurse | Select-Object FullName | Format-Table -AutoSize
            throw "Could not find installer in extracted archive."
        }
    } else {
        Write-Host "Found MSI: $($msiFile.FullName)"
        Write-Host "Installing eQUEST via MSI (this may take several minutes)..."
        $proc = Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$($msiFile.FullName)`" /quiet /norestart ALLUSERS=1" -Wait -PassThru -NoNewWindow
        Write-Host "MSI installer exited with code: $($proc.ExitCode)"
    }

    # Verify installation (directory may include build number like eQUEST 3-65-7175)
    $installed = $false
    $eqInstDirs = @()
    $eqInstDirs += Get-ChildItem "C:\Program Files (x86)" -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "eQUEST 3-65*" }
    $eqInstDirs += Get-ChildItem "C:\Program Files" -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "eQUEST 3-65*" }
    foreach ($d in $eqInstDirs) {
        if (Test-Path "$($d.FullName)\eQUEST.exe") {
            Write-Host "eQUEST installed successfully at: $($d.FullName)"
            $installed = $true
            break
        }
    }

    if (-not $installed) {
        # Search more broadly
        $found = Get-ChildItem "C:\" -Recurse -Filter "eQUEST.exe" -ErrorAction SilentlyContinue -Depth 4 | Select-Object -First 1
        if ($found) {
            Write-Host "eQUEST found at: $($found.FullName)"
            $installed = $true
        } else {
            Write-Host "WARNING: Could not find eQUEST.exe after installation."
        }
    }

    # Download official training example files
    Write-Host "Downloading eQUEST training examples..."
    $trainingUrl = "https://doe2.com/Download/equest/eQuestTrainingWorkbook_Examples.zip"
    $trainingZip = "$workDir\training_examples.zip"
    try {
        Invoke-WebRequest -Uri $trainingUrl -OutFile $trainingZip -UseBasicParsing -TimeoutSec 120
        if (Test-Path $trainingZip) {
            $trainingDir = "C:\eQUEST_Data\TrainingExamples"
            New-Item -ItemType Directory -Force -Path $trainingDir | Out-Null
            Expand-Archive -Path $trainingZip -DestinationPath $trainingDir -Force
            Write-Host "Training examples extracted to: $trainingDir"
        }
    } catch {
        Write-Host "WARNING: Could not download training examples: $($_.Exception.Message)"
    }

    # Cleanup installer files
    Remove-Item -Path $workDir -Recurse -Force -ErrorAction SilentlyContinue

    Write-Host "=== eQUEST installation complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
