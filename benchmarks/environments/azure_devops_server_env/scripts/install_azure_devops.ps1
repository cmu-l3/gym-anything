Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Installation script for Azure DevOps Server 2022 Express.
# This script runs during VM initialization (pre_start hook).
# Downloads and installs Azure DevOps Server Express with SQL Server Express.

$logPath = "C:\Users\Docker\env_setup_pre_start.log"
try {
    Start-Transcript -Path $logPath -Force | Out-Null
} catch {
    Write-Host "WARNING: Start-Transcript failed: $($_.Exception.Message)"
}

try {
    Write-Host "=== Installing Azure DevOps Server 2022 Express ==="

    # Check if already fully installed AND configured
    $tfsConfigPath = "C:\Program Files\Azure DevOps Server 2022\Tools\tfsconfig.exe"
    $jobAgentSvc = Get-Service -Name "TFSJobAgent" -ErrorAction SilentlyContinue
    if ((Test-Path $tfsConfigPath) -and ($jobAgentSvc -and $jobAgentSvc.Status -eq "Running")) {
        Write-Host "Azure DevOps Server already installed and configured (TFSJobAgent running)."
        Write-Host "=== Installation skipped (already present) ==="
        exit 0
    }

    # If binaries not yet installed, run Phases 1 and 2
    if (-not (Test-Path $tfsConfigPath)) {
        # ---- Phase 1: Download Azure DevOps Server 2022 Express ----
        Write-Host ""
        Write-Host "--- Phase 1: Downloading Azure DevOps Server 2022 Express ---"
        $installerUrl = "https://go.microsoft.com/fwlink/?LinkId=2269947"
        $installerPath = "C:\Windows\Temp\AzureDevOpsExpress2022.exe"

        if (Test-Path $installerPath) {
            $fileSize = (Get-Item $installerPath).Length / 1MB
            if ($fileSize -gt 500) {
                Write-Host "Installer already downloaded ($([math]::Round($fileSize, 1)) MB). Skipping download."
            } else {
                Remove-Item $installerPath -Force
                Write-Host "Partial download found, re-downloading..."
            }
        }

        if (-not (Test-Path $installerPath)) {
            Write-Host "Downloading from: $installerUrl"
            Write-Host "This may take 5-15 minutes depending on bandwidth..."

            # Use BITS for more reliable large download
            $prevEAP = $ErrorActionPreference
            try {
                $ErrorActionPreference = "Continue"
                Import-Module BitsTransfer -ErrorAction SilentlyContinue
                Start-BitsTransfer -Source $installerUrl -Destination $installerPath -ErrorAction Stop
                $ErrorActionPreference = $prevEAP
            } catch {
                $ErrorActionPreference = $prevEAP
                Write-Host "BITS transfer failed, falling back to WebClient..."
                $webClient = New-Object System.Net.WebClient
                $webClient.DownloadFile($installerUrl, $installerPath)
            }

            if (-not (Test-Path $installerPath)) {
                throw "Failed to download Azure DevOps Server Express installer"
            }
            $fileSize = (Get-Item $installerPath).Length / 1MB
            Write-Host "Download complete: $([math]::Round($fileSize, 1)) MB"
        }

        # ---- Phase 2: Silent Install (extract bits to disk) ----
        Write-Host ""
        Write-Host "--- Phase 2: Running Silent Install ---"
        Write-Host "Installing Azure DevOps Server Express (this takes 5-10 minutes)..."

        $proc = Start-Process -FilePath $installerPath -ArgumentList "/Silent" -PassThru -Wait
        Write-Host "Installer exit code: $($proc.ExitCode)"

        if ($proc.ExitCode -ne 0 -and $proc.ExitCode -ne 3010) {
            throw "Azure DevOps Server installer failed with exit code: $($proc.ExitCode)"
        }
        if ($proc.ExitCode -eq 3010) {
            Write-Host "Exit code 3010 = reboot recommended (not required). Continuing..."
        }

        # Verify installation
        if (-not (Test-Path $tfsConfigPath)) {
            # Search more broadly
            $searchResult = Get-ChildItem "C:\Program Files" -Recurse -Filter "tfsconfig.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($searchResult) {
                $tfsConfigPath = $searchResult.FullName
                Write-Host "tfsconfig.exe found at: $tfsConfigPath"
            } else {
                throw "Azure DevOps Server installation failed - tfsconfig.exe not found"
            }
        }
        Write-Host "Azure DevOps Server binaries installed successfully."
    } else {
        Write-Host "Azure DevOps Server binaries already present. Skipping download and install."
    }

    # ---- Phase 2.5: Install required IIS features ----
    Write-Host ""
    Write-Host "--- Phase 2.5: Installing Required IIS Features ---"
    $iisFeatures = @(
        "IIS-WebServer", "IIS-ASPNET45", "IIS-WindowsAuthentication",
        "IIS-WebSockets", "IIS-ManagementConsole", "IIS-ManagementScriptingTools",
        "IIS-HttpCompressionStatic", "IIS-HttpCompressionDynamic", "IIS-StaticContent"
    )
    foreach ($feat in $iisFeatures) {
        $state = (Get-WindowsOptionalFeature -Online -FeatureName $feat -ErrorAction SilentlyContinue).State
        if ($state -ne "Enabled") {
            Write-Host "Enabling IIS feature: $feat"
            dism /online /enable-feature /featurename:$feat /all /norestart 2>&1 | Where-Object { $_ -match "completed|error|failed" } | Write-Host
        }
    }
    Write-Host "IIS features configured."

    # ---- Phase 3: Unattended Configuration with SQL Express ----
    Write-Host ""
    Write-Host "--- Phase 3: Unattended Server Configuration ---"
    Write-Host "Configuring Azure DevOps Server with SQL Server Express..."
    Write-Host "This takes 10-20 minutes (includes SQL Express installation)..."

    $iniPath = "C:\Windows\Temp\azure_devops_config.ini"

    # Generate default INI file
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    & $tfsConfigPath unattend /create /type:NewServerBasic /unattendfile:$iniPath 2>&1
    $ErrorActionPreference = $prevEAP

    if (-not (Test-Path $iniPath)) {
        throw "Failed to generate configuration INI file"
    }

    # Modify INI to install SQL Express and create default collection
    $iniContent = Get-Content $iniPath -Raw
    $iniContent = $iniContent -replace 'InstallSqlExpress=False', 'InstallSqlExpress=True'
    $iniContent = $iniContent -replace 'CreateInitialCollection=False', 'CreateInitialCollection=True'

    # Ensure key settings
    if ($iniContent -notmatch 'InstallSqlExpress=True') {
        $iniContent = $iniContent + "`r`nInstallSqlExpress=True"
    }
    if ($iniContent -notmatch 'CreateInitialCollection=True') {
        $iniContent = $iniContent + "`r`nCreateInitialCollection=True"
    }

    Set-Content -Path $iniPath -Value $iniContent -Force
    Write-Host "Configuration INI prepared at: $iniPath"

    # Run the unattended configuration via scheduled task as SYSTEM
    # (tfsconfig requires SYSTEM privileges for SQL Express install and perf counter operations)
    Write-Host "Starting unattended configuration via SYSTEM scheduled task..."
    $cfgScript = "C:\Windows\Temp\run_tfsconfig_cfg.ps1"
    @"
& 'C:\Program Files\Azure DevOps Server 2022\Tools\tfsconfig.exe' unattend /configure /unattendfile:'C:\Windows\Temp\azure_devops_config.ini' /continue | Out-File -FilePath 'C:\Windows\Temp\tfsconfig_cfg_stdout.log' -Encoding utf8
"@ | Set-Content $cfgScript -Encoding UTF8

    $taskName = "AzDevOpsCfgTask"
    schtasks /create /tn $taskName /tr "powershell.exe -ExecutionPolicy Bypass -File $cfgScript" /sc ONCE /st 00:00 /ru SYSTEM /f | Out-Null
    schtasks /run /tn $taskName | Out-Null

    # Wait for tfsconfig to complete (up to 30 minutes)
    Write-Host "Waiting for tfsconfig configuration to complete (up to 30 minutes)..."
    $maxCfgWait = 1800
    $cfgElapsed = 0
    while ($cfgElapsed -lt $maxCfgWait) {
        Start-Sleep -Seconds 15
        $cfgElapsed += 15
        $tfsproc = Get-Process -Name "TfsConfig" -ErrorAction SilentlyContinue
        if (-not $tfsproc) {
            Write-Host "tfsconfig process completed after ${cfgElapsed}s."
            break
        }
        if ($cfgElapsed % 60 -eq 0) {
            Write-Host "  Still configuring... (${cfgElapsed}s elapsed)"
        }
    }
    schtasks /delete /tn $taskName /f 2>&1 | Out-Null

    # Check result
    if (Test-Path "C:\Windows\Temp\tfsconfig_cfg_stdout.log") {
        $stdout = Get-Content "C:\Windows\Temp\tfsconfig_cfg_stdout.log" -Raw
        Write-Host "tfsconfig stdout (last 2000 chars):"
        Write-Host $stdout.Substring([Math]::Max(0, $stdout.Length - 2000))
        if ($stdout -match "ServerConfiguration completed successfully") {
            Write-Host "Azure DevOps Server configuration SUCCEEDED."
        } else {
            Write-Host "WARNING: Configuration may not have completed successfully."
        }
    }

    # ---- Phase 4: Verify Services ----
    Write-Host ""
    Write-Host "--- Phase 4: Verifying Services ---"

    # Check Azure DevOps services
    $services = @(
        "TFSJobAgent",
        "VSTFS"
    )
    foreach ($svc in $services) {
        $service = Get-Service -Name $svc -ErrorAction SilentlyContinue
        if ($service) {
            Write-Host "Service '$svc': $($service.Status)"
            if ($service.Status -ne "Running") {
                Write-Host "Starting service '$svc'..."
                Start-Service $svc -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 5
            }
        } else {
            Write-Host "Service '$svc' not found (may have different name)."
        }
    }

    # Check SQL Server Express
    $sqlService = Get-Service -Name "MSSQL`$SQLEXPRESS" -ErrorAction SilentlyContinue
    if (-not $sqlService) {
        $sqlService = Get-Service -Name "MSSQLSERVER" -ErrorAction SilentlyContinue
    }
    if ($sqlService) {
        Write-Host "SQL Server service: $($sqlService.Status)"
    } else {
        Write-Host "WARNING: SQL Server service not found."
    }

    # Wait for web interface to become available
    Write-Host "Waiting for Azure DevOps web interface..."
    $maxWait = 120
    $elapsed = 0
    $baseUrl = "http://localhost/DefaultCollection"

    while ($elapsed -lt $maxWait) {
        try {
            $response = Invoke-WebRequest -Uri "$baseUrl/_apis/projects?api-version=7.1" -UseDefaultCredentials -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
            if ($response.StatusCode -eq 200) {
                Write-Host "Azure DevOps web interface is ready! (HTTP 200)"
                break
            }
        } catch {
            # Try alternate URL pattern (with /tfs prefix)
            try {
                $response = Invoke-WebRequest -Uri "http://localhost:8080/tfs/DefaultCollection/_apis/projects?api-version=7.1" -UseDefaultCredentials -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop
                if ($response.StatusCode -eq 200) {
                    Write-Host "Azure DevOps available at alternate URL: http://localhost:8080/tfs/"
                    break
                }
            } catch {}
        }
        Start-Sleep -Seconds 10
        $elapsed += 10
        Write-Host "  Waiting... ($elapsed/$maxWait seconds)"
    }

    if ($elapsed -ge $maxWait) {
        Write-Host "WARNING: Azure DevOps web interface not responding after ${maxWait}s"
        Write-Host "Services may still be starting. Will retry in post_start hook."
    }

    # Clean up installer
    Remove-Item $installerPath -Force -ErrorAction SilentlyContinue
    Remove-Item $iniPath -Force -ErrorAction SilentlyContinue
    Write-Host "Installer cleaned up."

    Write-Host ""
    Write-Host "=== Azure DevOps Server 2022 Express installation complete ==="

} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
