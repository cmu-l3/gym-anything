Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Helper: download using curl.exe (Invoke-WebRequest has TLS issues in this VM)
function Download-File {
    param([string]$Url, [string]$OutFile, [int]$TimeoutSec = 600)
    Write-Host "Downloading: $Url"
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    & curl.exe -L -f --max-time $TimeoutSec -o $OutFile $Url 2>&1 | Out-Null
    $exitCode = $LASTEXITCODE
    $ErrorActionPreference = $prevEAP
    Write-Host "curl.exe exit code: $exitCode"
    if ($exitCode -ne 0) {
        throw "Download failed (exit code $exitCode): $Url"
    }
    if (-not (Test-Path $OutFile)) {
        throw "Output file not created: $OutFile"
    }
    $size = (Get-Item $OutFile).Length
    Write-Host "Downloaded $([math]::Round($size/1MB, 1)) MB"
    return $size
}

$logPath = "C:\Users\Docker\env_setup_pre_start.log"
try {
    Start-Transcript -Path $logPath -Force | Out-Null
} catch {
    Write-Host "WARNING: Start-Transcript failed: $($_.Exception.Message)"
}

try {
    Write-Host "=== Installing Epi Info 7 Environment ==="

    # 1. Create working directories
    $tempDir = "C:\temp\epi_info_install"
    New-Item -ItemType Directory -Force -Path $tempDir | Out-Null
    New-Item -ItemType Directory -Force -Path "C:\EpiInfo7" | Out-Null
    New-Item -ItemType Directory -Force -Path "C:\Users\Docker\Desktop" | Out-Null

    # 2. Check .NET Framework 4.8 (required by Epi Info 7; Windows 11 has it built-in)
    Write-Host "--- Checking .NET Framework 4.8 ---"
    $ndpKey = "HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full"
    if (Test-Path $ndpKey) {
        $release = (Get-ItemProperty $ndpKey).Release
        if ($release -ge 528040) {
            Write-Host ".NET 4.8+ already installed (release=$release)"
        } else {
            Write-Host ".NET 4.8 not found (release=$release), installing..."
            $ndpPath = "$tempDir\ndp48-web.exe"
            Download-File -Url "https://go.microsoft.com/fwlink/?linkid=2088631" -OutFile $ndpPath -TimeoutSec 300
            $result = Start-Process $ndpPath -ArgumentList "/quiet /norestart" -Wait -PassThru
            Write-Host ".NET 4.8 installed (exit: $($result.ExitCode))"
        }
    } else {
        Write-Host ".NET 4 registry key not found - Windows 11 should have it built-in."
    }

    # 3. Download Epi Info 7 ZIP from CDC using curl.exe
    #    CDC serves Epi Info 7.2.7 (March 2025, ~81MB ZIP)
    Write-Host "--- Downloading Epi Info 7 from CDC ---"

    $epiZip = "$tempDir\Epi_Info_7.zip"
    $downloaded = $false

    $downloadUrls = @(
        "https://www.cdc.gov/epiinfo/software/Epi_Info_7.zip",
        "https://restoredcdc.org/www.cdc.gov/epiinfo/software/Epi_Info_7.zip"
    )

    foreach ($url in $downloadUrls) {
        try {
            Write-Host "Trying: $url"
            $size = Download-File -Url $url -OutFile $epiZip -TimeoutSec 600
            if ($size -gt 10MB) {
                Write-Host "Downloaded: $([math]::Round($size/1MB,1)) MB"
                $downloaded = $true
                break
            } else {
                Write-Host "File too small, trying next..."
                Remove-Item $epiZip -Force -ErrorAction SilentlyContinue
            }
        } catch {
            Write-Host "Failed from $url : $($_.Exception.Message)"
            Remove-Item $epiZip -Force -ErrorAction SilentlyContinue
        }
    }

    if (-not $downloaded) {
        try {
            Write-Host "Trying EI7_Setup.zip..."
            $setupZip = "$tempDir\EI7_Setup.zip"
            $size = Download-File -Url "https://www.cdc.gov/epiinfo/software/EI7_Setup.zip" -OutFile $setupZip -TimeoutSec 600
            if ($size -gt 5MB) {
                $epiZip = $setupZip
                $downloaded = $true
                Write-Host "Downloaded setup variant: $([math]::Round($size/1MB,1)) MB"
            }
        } catch {
            Write-Host "Setup ZIP also failed: $($_.Exception.Message)"
        }
    }

    if (-not $downloaded) {
        throw "ERROR: Could not download Epi Info 7 from any source."
    }

    # 4. Extract Epi Info 7
    Write-Host "--- Extracting Epi Info 7 ---"
    $extractDir = "$tempDir\epi_info_extracted"
    New-Item -ItemType Directory -Force -Path $extractDir | Out-Null
    Expand-Archive -Path $epiZip -DestinationPath $extractDir -Force
    Write-Host "Extraction complete."

    Write-Host "Extracted contents (top level):"
    Get-ChildItem $extractDir | ForEach-Object { Write-Host "  $($_.Name)" }

    # Detect ZIP structure:
    # Modern: root has "Launch Epi Info 7.exe" + "Epi Info 7\" subdirectory
    # Legacy: EpiInfo7Launcher.exe or EpiInfo7.exe somewhere in hierarchy
    $launcherAtRoot = Get-ChildItem $extractDir -Filter "Launch Epi Info 7.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
    $appSubDir = Get-ChildItem $extractDir -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq "Epi Info 7" } | Select-Object -First 1
    $legacyLauncher = Get-ChildItem $extractDir -Recurse -Filter "EpiInfo7Launcher.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $legacyLauncher) {
        $legacyLauncher = Get-ChildItem $extractDir -Recurse -Filter "EpiInfo7.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
    }

    if ($launcherAtRoot -or $appSubDir) {
        # Modern portable ZIP: "Epi Info 7\" dir + "Launch Epi Info 7.exe" at root
        Write-Host "Found modern Epi Info 7 portable structure"
        $existingCount = (Get-ChildItem "C:\EpiInfo7" -ErrorAction SilentlyContinue | Measure-Object).Count
        if ($existingCount -gt 0) {
            Remove-Item "C:\EpiInfo7\*" -Recurse -Force -ErrorAction SilentlyContinue
        }
        if ($appSubDir) {
            Copy-Item "$($appSubDir.FullName)\*" "C:\EpiInfo7\" -Recurse -Force
            Write-Host "Copied app files from: $($appSubDir.FullName)"
        }
        if ($launcherAtRoot) {
            Copy-Item $launcherAtRoot.FullName "C:\EpiInfo7\" -Force
            Write-Host "Copied launcher: $($launcherAtRoot.Name)"
        }
        $launcherDest = "C:\EpiInfo7\Launch Epi Info 7.exe"
        if (Test-Path $launcherDest) {
            Set-Content -Path "C:\Users\Docker\epi_info_launcher_path.txt" -Value $launcherDest -Encoding UTF8
            Write-Host "Launcher path saved: $launcherDest"
        }
    } elseif ($legacyLauncher) {
        # Legacy portable ZIP: EpiInfo7Launcher.exe inside a directory
        Write-Host "Found legacy launcher: $($legacyLauncher.FullName)"
        $sourceRoot = $legacyLauncher.DirectoryName
        Write-Host "Copying to C:\EpiInfo7..."
        $existingCount = (Get-ChildItem "C:\EpiInfo7" -ErrorAction SilentlyContinue | Measure-Object).Count
        if ($existingCount -gt 0) {
            Remove-Item "C:\EpiInfo7\*" -Recurse -Force -ErrorAction SilentlyContinue
        }
        Copy-Item "$sourceRoot\*" "C:\EpiInfo7\" -Recurse -Force
        Write-Host "Files copied to C:\EpiInfo7"
    } else {
        # Setup variant: look for setup.exe or MSI
        $setupExe = Get-ChildItem $extractDir -Recurse -Filter "setup.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
        $msiFile = Get-ChildItem $extractDir -Recurse -Filter "*.msi" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($msiFile) {
            Write-Host "Running MSI installer: $($msiFile.FullName)"
            $msiResult = Start-Process "msiexec" -ArgumentList "/i `"$($msiFile.FullName)`" /qn /norestart INSTALLDIR=C:\EpiInfo7" -Wait -PassThru
            $msiCode = $msiResult.ExitCode
            Write-Host "MSI exit code: $msiCode"
            if ($msiCode -ne 0 -and $msiCode -ne 3010) {
                Write-Host "WARNING: MSI returned $msiCode"
            }
        } elseif ($setupExe) {
            Write-Host "Running setup.exe: $($setupExe.FullName)"
            $result = Start-Process $setupExe.FullName -ArgumentList "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /DIR=C:\EpiInfo7" -Wait -PassThru
            Write-Host "setup.exe exit code: $($result.ExitCode)"
        } else {
            Write-Host "WARNING: No installer found in extracted content."
        }
    }

    # 5. Verify installation and find key files
    Write-Host "--- Verifying Epi Info 7 installation ---"

    $foundLauncher = $null
    $searchPaths = @(
        "C:\EpiInfo7\Launch Epi Info 7.exe",
        "C:\EpiInfo7\Analysis.exe",
        "C:\EpiInfo7\EpiInfo7Launcher.exe",
        "C:\EpiInfo7\EpiInfo7.exe"
    )
    foreach ($p in $searchPaths) {
        if (Test-Path $p) { $foundLauncher = $p; break }
    }

    if (-not $foundLauncher) {
        $found = Get-ChildItem "C:\EpiInfo7" -Recurse -Filter "Launch Epi Info 7.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) { $foundLauncher = $found.FullName }
    }
    if (-not $foundLauncher) {
        $found = Get-ChildItem "C:\EpiInfo7" -Recurse -Filter "EpiInfo7Launcher.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) { $foundLauncher = $found.FullName }
    }
    if (-not $foundLauncher) {
        $found = Get-ChildItem "C:\EpiInfo7" -Recurse -Filter "Analysis.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) { $foundLauncher = $found.FullName }
    }

    if ($foundLauncher) {
        Write-Host "Launcher found: $foundLauncher"
        Set-Content -Path "C:\Users\Docker\epi_info_launcher_path.txt" -Value $foundLauncher -Encoding UTF8
    } else {
        Write-Host "WARNING: No launcher found."
        Write-Host "C:\EpiInfo7 contents:"
        Get-ChildItem "C:\EpiInfo7" -ErrorAction SilentlyContinue | ForEach-Object { Write-Host "  $($_.Name)" }
    }

    # Find EColi.PRJ (real CDC outbreak sample dataset)
    Write-Host "--- Locating CDC sample datasets ---"
    $ecoliPrj = Get-ChildItem "C:\EpiInfo7" -Recurse -Include "EColi.prj","EColi.PRJ" -ErrorAction SilentlyContinue | Select-Object -First 1

    if ($ecoliPrj) {
        Write-Host "EColi.PRJ found: $($ecoliPrj.FullName)"
        Set-Content -Path "C:\Users\Docker\ecoli_prj_path.txt" -Value $ecoliPrj.FullName -Encoding UTF8
    } else {
        Write-Host "WARNING: EColi.PRJ not found."
        $prjFiles = Get-ChildItem "C:\EpiInfo7" -Recurse -Filter "*.prj" -ErrorAction SilentlyContinue
        Write-Host "All PRJ files found:"
        $prjFiles | ForEach-Object { Write-Host "  $($_.FullName)" }
    }

    # Find Salmonella project
    $salmPrj = Get-ChildItem "C:\EpiInfo7" -Recurse -Include "SalmonellaExample.prj","SalmonellaExample.PRJ" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($salmPrj) {
        Write-Host "Salmonella project: $($salmPrj.FullName)"
        Set-Content -Path "C:\Users\Docker\salmonella_prj_path.txt" -Value $salmPrj.FullName -Encoding UTF8
    }

    # 6. List Epi Info 7 directory structure
    Write-Host "--- Epi Info 7 directory structure ---"
    Get-ChildItem "C:\EpiInfo7" -ErrorAction SilentlyContinue | ForEach-Object { Write-Host "  $($_.Name)" }

    Write-Host "=== Epi Info 7 Installation Complete ==="

} catch {
    Write-Host "FATAL ERROR: $($_.Exception.Message)"
    Write-Host $_.ScriptStackTrace
    exit 1
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
