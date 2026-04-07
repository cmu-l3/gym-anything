Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Installation script for EPA Tier2 Submit 2025.
# This script runs during VM initialization (pre_start hook).
# The installer is Inno Setup based (.tmp extraction pattern confirms this).

$logPath = "C:\Users\Docker\env_setup_pre_start.log"
try {
    Start-Transcript -Path $logPath -Force | Out-Null
} catch {
    Write-Host "WARNING: Start-Transcript failed: $($_.Exception.Message)"
}

try {
    Write-Host "=== Installing EPA Tier2 Submit 2025 ==="

    # Check if already installed
    $t2sPaths = @(
        "C:\Program Files\Tier2Submit\Tier2Submit.exe",
        "C:\Program Files (x86)\Tier2Submit\Tier2Submit.exe",
        "C:\Program Files\EPA\Tier2Submit\Tier2Submit.exe",
        "C:\Program Files (x86)\EPA\Tier2Submit\Tier2Submit.exe",
        "C:\Program Files\CAMEO\Tier2Submit\Tier2Submit.exe",
        "C:\Program Files (x86)\CAMEO\Tier2Submit\Tier2Submit.exe",
        "C:\Program Files\Tier2 Submit\Tier2 Submit.exe",
        "C:\Program Files (x86)\Tier2 Submit\Tier2 Submit.exe",
        "C:\Program Files\Tier2Submit 2025\Tier2Submit.exe",
        "C:\Program Files (x86)\Tier2Submit 2025\Tier2Submit.exe",
        "C:\Tier2Submit\Tier2Submit.exe"
    )

    $existingPath = $null
    foreach ($p in $t2sPaths) {
        if (Test-Path $p) {
            $existingPath = $p
            break
        }
    }
    if (-not $existingPath) {
        $searchResult = Get-ChildItem "C:\Program Files", "C:\Program Files (x86)" -Recurse -Filter "Tier2Submit*.exe" -ErrorAction SilentlyContinue -Depth 3 | Select-Object -First 1
        if ($searchResult) { $existingPath = $searchResult.FullName }
    }

    if ($existingPath) {
        Write-Host "Tier2 Submit already installed at: $existingPath"
        Write-Host "=== Installation skipped (already present) ==="
    } else {
        $installerPath = "C:\Windows\Temp\tier2submit2025installer.exe"

        # Get installer: prefer pre-downloaded from workspace
        $preDownloaded = "C:\workspace\data\tier2submit_installer.exe"
        if (Test-Path $preDownloaded) {
            Write-Host "Using pre-downloaded installer from workspace data..."
            Copy-Item $preDownloaded -Destination $installerPath -Force
            $fileSize = (Get-Item $installerPath).Length / 1MB
            Write-Host "Installer copied: $([math]::Round($fileSize, 1)) MB"
        } else {
            Write-Host "Pre-downloaded installer not found. Attempting download..."
            $urls = @(
                "https://www.epa.gov/system/files/other-files/2026-02/tier2submit2025installer_rev1.exe",
                "https://www.epa.gov/system/files/other-files/2025-12/tier2submit2025installer_rev1.exe"
            )
            $downloaded = $false
            foreach ($url in $urls) {
                Write-Host "Attempting download from: $url"
                try {
                    Invoke-WebRequest -Uri $url -OutFile $installerPath -UseBasicParsing `
                        -Headers @{"User-Agent"="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"} `
                        -ErrorAction Stop
                    if ((Test-Path $installerPath) -and (Get-Item $installerPath).Length -gt 1MB) {
                        $fileSize = (Get-Item $installerPath).Length / 1MB
                        Write-Host "Download complete: $([math]::Round($fileSize, 1)) MB"
                        $downloaded = $true
                        break
                    }
                } catch {
                    Write-Host "Download failed: $($_.Exception.Message)"
                    Remove-Item $installerPath -Force -ErrorAction SilentlyContinue
                }
            }
            if (-not $downloaded) {
                throw "Failed to obtain Tier2 Submit installer."
            }
        }

        # Install - this is an Inno Setup installer (confirmed by .tmp extraction pattern)
        Write-Host "Installing Tier2 Submit (Inno Setup)..."
        $prevEAP = $ErrorActionPreference
        $ErrorActionPreference = "Continue"

        # Inno Setup silent install flags (try these FIRST since confirmed Inno Setup)
        $installAttempts = @(
            @{Args = "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP-"; Desc = "InnoSetup very silent"},
            @{Args = "/SILENT /SUPPRESSMSGBOXES /NORESTART"; Desc = "InnoSetup silent"},
            @{Args = "/S"; Desc = "NSIS silent"}
        )

        $installSuccess = $false
        foreach ($attempt in $installAttempts) {
            Write-Host "Trying install with $($attempt.Desc) flags: $($attempt.Args)"
            try {
                $proc = Start-Process $installerPath -ArgumentList $attempt.Args -PassThru -ErrorAction SilentlyContinue
                # Wait with timeout (180 seconds) instead of indefinite -Wait
                $finished = $proc.WaitForExit(180000)
                if (-not $finished) {
                    Write-Host "Install timed out after 180s, killing process..."
                    $proc | Stop-Process -Force -ErrorAction SilentlyContinue
                    # Also kill any child processes
                    Get-Process | Where-Object {$_.ProcessName -match "(?i)tier2submit.*install"} | Stop-Process -Force -ErrorAction SilentlyContinue
                    Start-Sleep -Seconds 3
                    continue
                }
                if ($proc.ExitCode -eq 0 -or $proc.ExitCode -eq 3010) {
                    Write-Host "Installer completed with exit code: $($proc.ExitCode)"
                    $installSuccess = $true
                    break
                } else {
                    Write-Host "Exit code: $($proc.ExitCode), trying next method..."
                }
            } catch {
                Write-Host "Install attempt failed: $($_.Exception.Message)"
            }
            # Kill any lingering installer processes between attempts
            Get-Process | Where-Object {$_.ProcessName -match "(?i)tier2submit"} | Stop-Process -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 5
        }

        # If silent install failed, try interactive install via schtasks /IT
        if (-not $installSuccess) {
            Write-Host "Silent install methods exhausted. Attempting interactive install via schtasks..."
            # Kill any lingering installers
            Get-Process | Where-Object {$_.ProcessName -match "(?i)tier2submit"} | Stop-Process -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 3

            $launchScript = "C:\Windows\Temp\install_t2s.cmd"
            # Use Inno Setup silent flags even in interactive session
            $batchContent = "@echo off`r`nstart /wait `"`" `"$installerPath`" /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP-"
            [System.IO.File]::WriteAllText($launchScript, $batchContent)

            schtasks /Create /TN "InstallT2S" /TR "cmd /c $launchScript" /SC ONCE /ST 00:00 /RL HIGHEST /IT /F 2>$null
            schtasks /Run /TN "InstallT2S" 2>$null

            # Wait for installer to complete (up to 5 minutes)
            $timeout = 300
            $elapsed = 0
            while ($elapsed -lt $timeout) {
                Start-Sleep -Seconds 10
                $elapsed += 10
                $installerRunning = Get-Process | Where-Object {
                    $_.ProcessName -match "(?i)tier2submit.*install|setup|msiexec"
                }
                if (-not $installerRunning -and $elapsed -gt 30) {
                    Write-Host "Installer process ended after ${elapsed}s"
                    break
                }
                Write-Host "Waiting for installer... ${elapsed}s elapsed"
            }
            schtasks /Delete /TN "InstallT2S" /F 2>$null
            Remove-Item $launchScript -Force -ErrorAction SilentlyContinue
        }

        $ErrorActionPreference = $prevEAP

        # Verify installation
        $installed = $false
        foreach ($p in $t2sPaths) {
            if (Test-Path $p) {
                Write-Host "Tier2 Submit installed at: $p"
                $installed = $true
                break
            }
        }

        if (-not $installed) {
            $searchDirs = @("C:\Program Files", "C:\Program Files (x86)", "C:\Users\Docker", "C:\")
            foreach ($dir in $searchDirs) {
                if (-not (Test-Path $dir)) { continue }
                $found = Get-ChildItem $dir -Recurse -Filter "*.exe" -ErrorAction SilentlyContinue -Depth 5 |
                    Where-Object { $_.Name -match "(?i)tier2submit" -and $_.Name -notmatch "unins|setup|install" } |
                    Select-Object -First 1
                if ($found) {
                    Write-Host "Tier2 Submit found at: $($found.FullName)"
                    $installed = $true
                    break
                }
            }
        }

        if (-not $installed) {
            Write-Host "WARNING: Could not verify Tier2 Submit installation."
            Write-Host "Listing Program Files directories..."
            Get-ChildItem "C:\Program Files" -Directory -ErrorAction SilentlyContinue | ForEach-Object { Write-Host "  $($_.FullName)" }
            Get-ChildItem "C:\Program Files (x86)" -Directory -ErrorAction SilentlyContinue | ForEach-Object { Write-Host "  $($_.FullName)" }
        }

        # Clean up installer
        Remove-Item $installerPath -Force -ErrorAction SilentlyContinue
        Write-Host "Installer cleaned up."
    }

    Write-Host "=== Tier2 Submit installation complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
