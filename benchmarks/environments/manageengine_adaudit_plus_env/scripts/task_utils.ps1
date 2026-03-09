# task_utils.ps1 - Shared utilities for ADAudit Plus task setup scripts

# -------------------------------------------------------
# Global constants
# -------------------------------------------------------
$ADAUDIT_PORT = 8081
$ADAUDIT_URL = "http://localhost:$ADAUDIT_PORT"
$ADAUDIT_ADMIN_USER = "admin"
$ADAUDIT_ADMIN_PASS = "Admin@2024"

# -------------------------------------------------------
# Find ADAudit Plus install directory
# -------------------------------------------------------
function Get-ADAuditInstallDir {
    $markerFile = "C:\Windows\Temp\adaudit_install_dir.txt"
    if (Test-Path $markerFile) {
        $dir = (Get-Content $markerFile -Raw).Trim()
        if (Test-Path $dir) { return $dir }
    }
    foreach ($p in @(
        "C:\Program Files\ManageEngine\ADAudit Plus",
        "C:\ManageEngine\ADAudit Plus",
        "C:\Program Files (x86)\ManageEngine\ADAudit Plus"
    )) {
        if (Test-Path $p) { return $p }
    }
    return $null
}

# -------------------------------------------------------
# Wait for ADAudit Plus web server readiness
# -------------------------------------------------------
function Wait-ForADAudit {
    param([int]$TimeoutSec = 600)
    Write-Host "Waiting for ADAudit Plus (http://localhost:$ADAUDIT_PORT)..."
    $elapsed = 0
    while ($elapsed -lt $TimeoutSec) {
        try {
            $r = Invoke-WebRequest -Uri "$ADAUDIT_URL/" -UseBasicParsing -TimeoutSec 5 -ErrorAction SilentlyContinue
            if ($r.StatusCode -ge 200 -and $r.StatusCode -lt 400) {
                Write-Host "ADAudit Plus ready after ${elapsed}s"
                return $true
            }
        } catch {}
        Start-Sleep -Seconds 5
        $elapsed += 5
        if ($elapsed % 60 -eq 0) { Write-Host "  Still waiting... ${elapsed}s" }
    }
    Write-Host "WARNING: ADAudit Plus not ready after ${TimeoutSec}s"
    return $false
}

# -------------------------------------------------------
# Login to ADAudit Plus and get session cookie
# -------------------------------------------------------
function Get-ADAuditSession {
    $session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
    try {
        $loginBody = @{
            j_username    = $ADAUDIT_ADMIN_USER
            j_password    = $ADAUDIT_ADMIN_PASS
            AUTHRULE_NAME = "ADAPAuthenticator"
        }
        $r = Invoke-WebRequest -Uri "$ADAUDIT_URL/j_security_check" -Method POST -Body $loginBody -WebSession $session -UseBasicParsing -MaximumRedirection 5 -ErrorAction SilentlyContinue
        Write-Host "Login response: HTTP $($r.StatusCode)"
    } catch {
        Write-Host "Login attempt: $_"
    }
    return $session
}

# -------------------------------------------------------
# Make API call to ADAudit Plus
# -------------------------------------------------------
function Invoke-ADAuditAPI {
    param(
        [string]$Path,
        [string]$Method = "GET",
        [hashtable]$Body = @{},
        [Microsoft.PowerShell.Commands.WebRequestSession]$Session = $null
    )
    if (-not $Session) { $Session = Get-ADAuditSession }
    $url = "$ADAUDIT_URL$Path"
    try {
        if ($Method -eq "GET") {
            $r = Invoke-WebRequest -Uri $url -Method GET -WebSession $Session -UseBasicParsing -ErrorAction Stop
        } else {
            $r = Invoke-WebRequest -Uri $url -Method $Method -Body ($Body | ConvertTo-Json) -ContentType "application/json" -WebSession $Session -UseBasicParsing -ErrorAction Stop
        }
        return $r
    } catch {
        Write-Host "API call failed: $Method $url - $_"
        return $null
    }
}

# -------------------------------------------------------
# Launch Edge browser to ADAudit Plus page (Session 1)
# -------------------------------------------------------
function Launch-BrowserToADAudit {
    param(
        [string]$Path = "/",
        [int]$WaitSeconds = 15
    )
    $url = "$ADAUDIT_URL$Path"
    Write-Host "Launching Edge to: $url"

    # Kill existing Edge
    Get-Process -Name "msedge" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    # Use a fresh temporary Edge profile to avoid session restore / "Restore pages" dialog
    # and disable password saving to prevent "Save your password?" popups.
    $tempProfile = "C:\Windows\Temp\edge_task_profile"
    Remove-Item $tempProfile -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -Path "$tempProfile\Default" -ItemType Directory -Force | Out-Null
    '{"credentials_enable_service":false,"profile":{"password_manager_enabled":false}}' | Out-File -FilePath "$tempProfile\Default\Preferences" -Encoding UTF8
    New-Item -Path "$tempProfile\First Run" -ItemType File -Force | Out-Null

    $batch = "C:\Windows\Temp\launch_edge.cmd"
    "@echo off`r`nstart `"`" `"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe`" --start-maximized --no-first-run --disable-sync --no-default-browser-check --disable-features=msEdgeOnRampFRE --user-data-dir=$tempProfile `"$url`"" | Out-File -FilePath $batch -Encoding ASCII

    $taskName = "LaunchEdgeADAudit"
    $prevEAP = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        schtasks /Delete /TN $taskName /F 2>$null
        schtasks /Create /TN $taskName /TR "cmd /c $batch" /SC ONCE /ST 00:00 /RL HIGHEST /IT /F 2>$null
        schtasks /Run /TN $taskName 2>$null
        Start-Sleep -Seconds $WaitSeconds
    } finally {
        schtasks /Delete /TN $taskName /F 2>$null
        Remove-Item $batch -Force -ErrorAction SilentlyContinue
        $ErrorActionPreference = $prevEAP
    }
    Write-Host "Edge launched to $url"
}

# -------------------------------------------------------
# Query ADAudit Plus bundled PostgreSQL
# -------------------------------------------------------
function Invoke-ADAuditDBQuery {
    param([string]$Query)
    $installDir = Get-ADAuditInstallDir
    if (-not $installDir) {
        Write-Host "Cannot find ADAudit Plus install dir for DB query"
        return $null
    }
    $pgBin = "$installDir\pgsql\bin\psql.exe"
    if (-not (Test-Path $pgBin)) {
        Write-Host "psql.exe not found at: $pgBin"
        return $null
    }
    $result = & $pgBin -h localhost -p 33307 -U postgres -d adap -t -A -c $Query 2>&1
    return $result
}
