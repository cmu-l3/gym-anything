Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

Write-Host "=== Installing Multiecuscan Environment ==="

New-Item -ItemType Directory -Path "C:\Temp" -Force | Out-Null

# ── 1. Enable .NET Framework 3.5 (Multiecuscan uses CLR v2.0) ──────────────
Write-Host "[1/5] Enabling .NET Framework 3.5..."
$needsDotnet = $true
$ndpKey = "HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v3.5"
if (Test-Path $ndpKey) {
    Write-Host ".NET Framework 3.5 already installed"
    $needsDotnet = $false
}

if ($needsDotnet) {
    Write-Host "Installing .NET 3.5 via DISM as SYSTEM (downloads from Windows Update)..."
    Remove-Item "C:\Temp\dism_exit.txt" -Force -ErrorAction SilentlyContinue

    # DISM must run as SYSTEM to have permissions; without /LimitAccess
    # so it downloads the removed payload from Windows Update (Windows 11 base
    # images have .NET 3.5 "DisabledWithPayloadRemoved")
    $batContent = "dism /Online /Enable-Feature /FeatureName:NetFx3 /All /NoRestart > C:\Temp\dism_out.txt 2>&1`r`necho %ERRORLEVEL% > C:\Temp\dism_exit.txt"
    Set-Content -Path "C:\Temp\run_dism.bat" -Value $batContent

    schtasks /Delete /TN "InstallDotNet35" /F 2>&1 | Out-Null
    schtasks /Create /TN "InstallDotNet35" /TR "cmd /c C:\Temp\run_dism.bat" /SC ONCE /SD 01/01/2099 /ST 00:00 /RL HIGHEST /RU SYSTEM /F
    schtasks /Run /TN "InstallDotNet35"

    # Poll for completion (typically 3-5 minutes via Windows Update)
    $maxWait = 600
    for ($i = 0; $i -lt $maxWait; $i += 5) {
        Start-Sleep -Seconds 5
        if (Test-Path "C:\Temp\dism_exit.txt") { break }
        if ($i % 30 -eq 0) { Write-Host "  Waiting for .NET 3.5 install... ($i sec)" }
    }

    if (Test-Path "C:\Temp\dism_exit.txt") {
        $exitCode = (Get-Content "C:\Temp\dism_exit.txt" -Raw).Trim()
        if ($exitCode -eq "0") {
            Write-Host ".NET 3.5 installed successfully via DISM"
        } else {
            Write-Host "WARNING: DISM exit code $exitCode"
        }
    } else {
        Write-Host "WARNING: DISM timed out after $maxWait seconds"
    }

    schtasks /Delete /TN "InstallDotNet35" /F 2>&1 | Out-Null
    Remove-Item "C:\Temp\run_dism.bat", "C:\Temp\dism_exit.txt", "C:\Temp\dism_out.txt" -Force -ErrorAction SilentlyContinue
}

# ── 1b. Force .NET native image generation (ngen) ────────────────────────────
# CRITICAL: DISM triggers ngen asynchronously in the background. Multiecuscan is
# a .NET CLR v2 app and will crash immediately if native images aren't compiled.
# We must run ngen executeQueuedItems to force completion BEFORE launching MES.
Write-Host "[1b/5] Running .NET native image generation (ngen)..."
$ngenPaths = @(
    "C:\Windows\Microsoft.NET\Framework\v2.0.50727\ngen.exe",
    "C:\Windows\Microsoft.NET\Framework64\v2.0.50727\ngen.exe",
    "C:\Windows\Microsoft.NET\Framework\v4.0.30319\ngen.exe",
    "C:\Windows\Microsoft.NET\Framework64\v4.0.30319\ngen.exe"
)
foreach ($ngen in $ngenPaths) {
    if (Test-Path $ngen) {
        Write-Host "  Running ngen: $ngen"
        $ngenResult = & $ngen executeQueuedItems 2>&1
        Write-Host "  ngen completed: $ngen"
    }
}

# Verify .NET 3.5 is functional by loading a CLR v2 assembly
Write-Host "  Verifying .NET 3.5 CLR v2 functionality..."
try {
    $testResult = powershell -Version 2 -Command "[System.Environment]::Version.ToString()" 2>&1
    Write-Host "  .NET CLR v2 test: $testResult"
} catch {
    Write-Host "  .NET CLR v2 test skipped (powershell -Version 2 not available)"
}

# ── 2. Download Multiecuscan installer ──────────────────────────────────────
Write-Host "[2/5] Downloading Multiecuscan installer..."
$installer = "C:\Temp\SetupMultiecuscan.msi"
$downloaded = $false

# Method 1: Check pre-mounted installer (fastest, no network needed)
$mountedPaths = @(
    "C:\workspace\data\SetupMultiecuscan.msi",
    "C:\workspace\data\SetupMultiecuscan54.msi",
    "C:\workspace\data\SetupMultiecuscan_54.msi"
)
foreach ($mp in $mountedPaths) {
    if (Test-Path $mp) {
        Copy-Item $mp $installer -Force
        Write-Host "  Using pre-mounted installer from $mp"
        $downloaded = $true
        break
    }
}

# Method 2: ASP.NET postback - the official download mechanism
# NOTE: Must use Invoke-WebRequest WITHOUT -UseBasicParsing to get Forms collection
if (-not $downloaded) {
    Write-Host "  Method 2: ASP.NET postback download..."
    try {
        $pageUrl = "https://www.multiecuscan.net/"
        # First GET to retrieve ASP.NET form state (ViewState, EventValidation)
        $response = Invoke-WebRequest -Uri $pageUrl -TimeoutSec 30 -SessionVariable mesSession
        $html = $response.Content

        $viewState = ""
        $viewStateGen = ""
        $eventValidation = ""

        if ($html -match 'name="__VIEWSTATE"[^>]*value="([^"]*)"') { $viewState = $Matches[1] }
        if ($html -match 'name="__VIEWSTATEGENERATOR"[^>]*value="([^"]*)"') { $viewStateGen = $Matches[1] }
        if ($html -match 'name="__EVENTVALIDATION"[^>]*value="([^"]*)"') { $eventValidation = $Matches[1] }

        if ($viewState) {
            Write-Host "  Extracted ASP.NET form state, submitting postback..."
            $body = @{
                "__EVENTTARGET"        = "ctl00`$CPH1`$lnkbutdown"
                "__EVENTARGUMENT"      = ""
                "__VIEWSTATE"          = $viewState
                "__VIEWSTATEGENERATOR" = $viewStateGen
                "__EVENTVALIDATION"    = $eventValidation
            }
            Invoke-WebRequest -Uri $pageUrl -Method POST -Body $body -WebSession $mesSession -OutFile $installer -UseBasicParsing -TimeoutSec 120

            if ((Test-Path $installer) -and ((Get-Item $installer).Length -gt 1000000)) {
                Write-Host "  Downloaded via ASP.NET postback! Size: $((Get-Item $installer).Length) bytes"
                $downloaded = $true
            } else {
                Write-Host "  Postback response too small or not an MSI"
                Remove-Item $installer -Force -ErrorAction SilentlyContinue
            }
        } else {
            Write-Host "  Could not extract ASP.NET form state"
        }
    } catch {
        Write-Host "  ASP.NET postback failed: $($_.Exception.Message)"
    }
}

if (-not $downloaded) {
    Write-Host "WARNING: Could not download Multiecuscan installer."
    Write-Host "To fix: place SetupMultiecuscan.msi in the data/ directory."
}

# ── 3. Install Multiecuscan (if downloaded) ────────────────────────────────
if ($downloaded) {
    Write-Host "[3/5] Installing Multiecuscan..."
    try {
        $process = Start-Process -FilePath "msiexec.exe" -ArgumentList "/i","`"$installer`"","/quiet","/norestart" -Wait -PassThru -NoNewWindow
        if ($process.ExitCode -eq 0 -or $process.ExitCode -eq 3010) {
            Write-Host "Multiecuscan installed successfully (exit code: $($process.ExitCode))"
        } else {
            Write-Host "WARNING: MSI exit code $($process.ExitCode)"
        }
    } catch {
        Write-Host "ERROR installing: $($_.Exception.Message)"
    }

    # Verify installation
    $mesExe = $null
    $searchPaths = @(
        "C:\Program Files (x86)\Multiecuscan\Multiecuscan.exe",
        "C:\Program Files\Multiecuscan\Multiecuscan.exe"
    )
    foreach ($sp in $searchPaths) {
        if (Test-Path $sp) {
            $mesExe = $sp
            Write-Host "Found Multiecuscan at: $mesExe"
            break
        }
    }
    if (-not $mesExe) {
        Write-Host "WARNING: Multiecuscan.exe not found after install"
    }

    # Save exe path for task scripts and grant write permissions
    if ($mesExe) {
        $mesDir = Split-Path $mesExe
        Set-Content "C:\Users\Docker\Desktop\MultiecuscanTasks\.mes_exe_path" -Value $mesExe
        # Ensure install dir is writable (for ini/config files created at runtime)
        $acl = Get-Acl $mesDir
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule("Docker","FullControl","ContainerInherit,ObjectInherit","None","Allow")
        $acl.SetAccessRule($rule)
        Set-Acl $mesDir $acl
    }

    Remove-Item $installer -Force -ErrorAction SilentlyContinue
} else {
    Write-Host "[3/5] Skipping installation (no installer available)"
}

# ── 4. Set up data directory ───────────────────────────────────────────────
Write-Host "[4/5] Setting up data directory..."
$dataDir = "C:\Users\Docker\Desktop\MultiecuscanData"
New-Item -ItemType Directory -Path $dataDir -Force | Out-Null

# Copy all reference data from mounted workspace
$dataFiles = Get-ChildItem -Path "C:\workspace\data" -File -ErrorAction SilentlyContinue
foreach ($df in $dataFiles) {
    Copy-Item $df.FullName "$dataDir\$($df.Name)" -Force
    Write-Host "  Copied $($df.Name)"
}

# Also download DTC database from GitHub (supplements mounted data)
try {
    $dtcUrl = "https://raw.githubusercontent.com/mytrile/obd-trouble-codes/master/obd-trouble-codes.csv"
    Invoke-WebRequest -Uri $dtcUrl -OutFile "$dataDir\dtc_database_github.csv" -UseBasicParsing -TimeoutSec 15
    Write-Host "  Downloaded DTC database from GitHub"
} catch {
    Write-Host "  Note: GitHub DTC download skipped (mounted data available)"
}

# ── 5. Create directory structure ──────────────────────────────────────────
Write-Host "[5/5] Creating task directory structure..."
New-Item -ItemType Directory -Path "C:\Users\Docker\Desktop\MultiecuscanTasks" -Force | Out-Null

Write-Host "=== Multiecuscan installation complete ==="
Write-Host "Data directory: $dataDir"
