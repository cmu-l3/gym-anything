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

    # 3. Download the pre-built Epi Info 7 install from the gym-anything mirror.
    #    The upstream CDC installer (cdc.gov/.../EI7_Setup.zip) is dead (404). Epi Info is
    #    US CDC public domain, so we host the extracted install (the EpiInfo7 folder) ourselves.
    Write-Host "--- Downloading Epi Info 7 from gym-anything mirror ---"
    $epiTgz = "$tempDir\EpiInfo7.tgz"
    $size = Download-File -Url "https://storage.googleapis.com/gym-anything-data-public/assets/epi_info/EpiInfo7.tgz" -OutFile $epiTgz -TimeoutSec 600
    Write-Host "Downloaded: $([math]::Round($size/1MB,1)) MB"

    # 4. Extract to C:\ (the archive's top-level entry is the EpiInfo7 folder)
    Write-Host "--- Extracting Epi Info 7 to C:\EpiInfo7 ---"
    & tar.exe -xzf $epiTgz -C C:\ 2>&1 | Out-Null
    Write-Host "Extraction complete."

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

    # Warm-up: launch Epi Info 7 once at build time so first-run state is
    # baked into the pre_start checkpoint. Local, no network.
    try {
        . C:\workspace\scripts\task_utils.ps1
        Launch-EpiInfoInteractive -WaitSeconds 20
        Start-Sleep -Seconds 3
        Stop-EpiInfo
        Write-Host "Warm-up complete: Epi Info 7 first-run baked into checkpoint."
    } catch { Write-Host "WARNING: Epi Info 7 warm-up failed: $($_.Exception.Message)" }

    Write-Host "=== Epi Info 7 Installation Complete ==="

} catch {
    Write-Host "FATAL ERROR: $($_.Exception.Message)"
    Write-Host $_.ScriptStackTrace
    exit 1
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
