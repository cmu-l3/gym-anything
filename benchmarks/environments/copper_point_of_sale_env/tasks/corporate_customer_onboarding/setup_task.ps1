Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_corp_onboarding_setup.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { }

try {
    Write-Host "=== Setting up corporate_customer_onboarding task ==="

    . "C:\workspace\scripts\task_utils.ps1"

    # Stop any running Copper instance for a clean slate
    Stop-Copper

    $taskDataDir = "C:\workspace\tasks\corporate_customer_onboarding"
    $desktopDir  = "C:\Users\Docker\Desktop"
    $dataDir     = "C:\Users\Docker\Documents\CopperData"
    New-Item -ItemType Directory -Force -Path $desktopDir | Out-Null

    # Stage corporate accounts reference file on Desktop
    $corpAccountsTxt = Join-Path $taskDataDir "corporate_accounts.txt"
    if (Test-Path $corpAccountsTxt) {
        Copy-Item $corpAccountsTxt -Destination (Join-Path $desktopDir "corporate_accounts.txt") -Force
        Write-Host "Staged corporate_accounts.txt on Desktop."
    } else {
        Write-Host "WARNING: corporate_accounts.txt not found."
    }

    # Stage the existing customers CSV on Desktop (from the shared data directory)
    $existingCSV = Join-Path $dataDir "customers.csv"
    if (Test-Path $existingCSV) {
        Copy-Item $existingCSV -Destination (Join-Path $desktopDir "existing_customers.csv") -Force
        Write-Host "Staged existing_customers.csv on Desktop (30 retail customers)."
    } else {
        # Fallback: try the workspace data directory
        $wsCSV = "C:\workspace\data\customers.csv"
        if (Test-Path $wsCSV) {
            Copy-Item $wsCSV -Destination (Join-Path $desktopDir "existing_customers.csv") -Force
            Write-Host "Staged existing_customers.csv from workspace data."
        } else {
            Write-Host "WARNING: customers.csv not found in either data location."
        }
    }

    # Remove any leftover output files
    Remove-Item "C:\Users\Docker\corporate_onboarding_result.json" -Force -ErrorAction SilentlyContinue
    Remove-Item (Join-Path $desktopDir "customer_accounts.csv") -Force -ErrorAction SilentlyContinue

    # Record task start timestamp
    $ts = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $ts | Out-File -FilePath "C:\Users\Docker\task_start_ts_corp_onboarding.txt" -Encoding ASCII -Force
    Write-Host "Task start timestamp: $ts"

    # Launch Copper POS
    Write-Host "Launching Copper POS..."
    Launch-CopperInteractive -WaitSeconds 20

    & "C:\workspace\scripts\dismiss_dialogs.ps1"

    Wait-ForCopperProcess -TimeoutSeconds 30

    Minimize-Terminals

    Write-Host "=== corporate_customer_onboarding setup complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
