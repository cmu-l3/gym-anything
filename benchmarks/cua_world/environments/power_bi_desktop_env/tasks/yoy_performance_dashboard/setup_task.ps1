# Setup script for yoy_performance_dashboard task.
# Generates 2-year sales dataset, ensures clean state, opens Power BI Desktop.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_pre_task_yoy_performance_dashboard.log"
try {
    Start-Transcript -Path $logPath -Force | Out-Null
} catch {
    Write-Host "WARNING: Start-Transcript failed: $($_.Exception.Message)"
}

try {
    Write-Host "=== Setting up yoy_performance_dashboard task ==="

    # Load shared helpers
    $utils = "C:\workspace\scripts\task_utils.ps1"
    if (-not (Test-Path $utils)) {
        throw "Missing task utils: $utils"
    }
    . $utils

    # Close any open Power BI windows and sub-processes
    Get-Process PBIDesktop -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Get-Process msmdsrv -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    # Remove pre-existing output files BEFORE recording timestamp
    $targetPbix = "C:\Users\Docker\Desktop\YoY_Performance.pbix"
    $resultJson = "C:\Users\Docker\Desktop\yoy_performance_result.json"
    foreach ($f in @($targetPbix, $resultJson)) {
        if (Test-Path $f) { Remove-Item $f -Force; Write-Host "Removed stale: $f" }
    }

    # Ensure working directory exists
    $destDir = "C:\Users\Docker\Desktop\PowerBITasks"
    New-Item -ItemType Directory -Force -Path $destDir | Out-Null

    # Generate 2-year sales dataset (deterministic, seed=42)
    $dataFile = "$destDir\sales_performance_2yr.csv"
    Write-Host "Generating 2-year sales dataset..."

    $rng = New-Object System.Random(42)
    $sb = New-Object System.Text.StringBuilder(500000)
    [void]$sb.AppendLine("Transaction_ID,Date,Region,Product_Category,Sales_Rep,Revenue,Units_Sold,Unit_Cost,Customer_Segment")

    $reps = @("Alice","Bob","Charlie","David","Eve","Frank","Grace","Henry",
              "Ivy","Jack","Kate","Leo","Mia","Noah","Olivia")
    $regions = @("East","West","North","South")
    $categories = @("Electronics","Clothing","Food","Furniture")
    $segments = @("B2B","B2C","Government")

    $txnId = 1
    $startDate = Get-Date -Date "2023-01-01"
    $endDate = Get-Date -Date "2024-12-31"
    $current = $startDate

    while ($current -le $endDate) {
        $year = $current.Year
        $month = $current.Month

        # Base transactions per day: 5-6 normally, 7-8 in Q4 (seasonal peak)
        if ($month -ge 10) {
            $txnsToday = 7 + $rng.Next(0, 2)
        } else {
            $txnsToday = 5 + $rng.Next(0, 2)
        }

        for ($t = 0; $t -lt $txnsToday; $t++) {
            $region = $regions[$rng.Next($regions.Length)]
            $category = $categories[$rng.Next($categories.Length)]
            $rep = $reps[$rng.Next($reps.Length)]
            $segment = $segments[$rng.Next($segments.Length)]

            # Base revenue: log-normal-ish distribution via transformation
            $u = $rng.NextDouble()
            $baseRevenue = [int](100 + 4900 * $u * $u)  # skewed toward lower values

            # Apply YoY regional growth multipliers for 2024
            if ($year -eq 2024) {
                switch ($region) {
                    "West"  { $baseRevenue = [int]($baseRevenue * 1.15) }
                    "South" { $baseRevenue = [int]($baseRevenue * 1.20) }
                    "North" { $baseRevenue = [int]($baseRevenue * 0.90) }
                    "East"  { $baseRevenue = [int]($baseRevenue * 1.02) }
                }
            }

            # Ensure minimum revenue
            if ($baseRevenue -lt 50) { $baseRevenue = 50 }

            $unitsSold = 1 + $rng.Next(0, 50)
            # Unit cost: 50-70% of unit price (realistic margin)
            $unitPrice = [math]::Round($baseRevenue / $unitsSold, 2)
            $marginFactor = 0.50 + $rng.NextDouble() * 0.20
            $unitCost = [math]::Round($unitPrice * $marginFactor, 2)

            $dateStr = $current.ToString("yyyy-MM-dd")
            [void]$sb.AppendLine("$txnId,$dateStr,$region,$category,$rep,$baseRevenue,$unitsSold,$unitCost,$segment")
            $txnId++
        }

        $current = $current.AddDays(1)
    }

    [System.IO.File]::WriteAllText($dataFile, $sb.ToString(), [System.Text.Encoding]::UTF8)
    $rowCount = $txnId - 1
    Write-Host "Generated $dataFile with $rowCount rows"

    # Record task start timestamp (AFTER deleting stale outputs, AFTER generating data)
    $epoch = [int][double]::Parse((Get-Date -UFormat %s))
    Set-Content -Path "C:\Users\Docker\task_start_timestamp_yoy_performance.txt" -Value "$epoch"
    Write-Host "Start timestamp: $epoch"

    Set-Content -Path "C:\Users\Docker\task_baseline_yoy.txt" -Value "pbix_exists_at_start=false"

    # Find and launch Power BI Desktop
    $pbiExe = Find-PowerBIExe
    Write-Host "Power BI executable: $pbiExe"
    Write-Host "Launching Power BI Desktop via scheduled task (interactive desktop)..."
    Launch-PowerBIInteractive -PowerBIExe $pbiExe -WaitSeconds 15

    # Best-effort: dismiss common first-run dialogs in the interactive session.
    $dismissScript = "C:\workspace\scripts\dismiss_dialogs.ps1"
    if (Test-Path $dismissScript) {
        Write-Host "Dismissing dialogs via scheduled task..."
        $taskName = "DismissDialogs_YoY"
        $prevEAP = $ErrorActionPreference
        try {
            $ErrorActionPreference = "Continue"
            schtasks /Create /TN $taskName /TR "powershell -ExecutionPolicy Bypass -File $dismissScript" /SC ONCE /ST 00:00 /RL HIGHEST /IT /F 2>$null
            schtasks /Run /TN $taskName 2>$null
            Start-Sleep -Seconds 28
        } finally {
            schtasks /Delete /TN $taskName /F 2>$null
            $ErrorActionPreference = $prevEAP
        }
        Write-Host "Dialog dismissal complete."
    }

    # Verify Power BI is running
    $pbiProc = Get-Process PBIDesktop -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($pbiProc) {
        Write-Host "Power BI Desktop is running (PID: $($pbiProc.Id))"
    } else {
        Write-Host "WARNING: Power BI Desktop process not found after launch."
    }

    Write-Host "=== yoy_performance_dashboard task setup complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
