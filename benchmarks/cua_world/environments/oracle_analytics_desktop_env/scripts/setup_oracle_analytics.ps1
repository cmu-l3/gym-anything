Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Post-start setup for Oracle Analytics Desktop.
# Runs after VM boots with desktop visible.
# Performs warm-up launch to clear first-run dialogs.

$logPath = "C:\Users\Docker\env_setup_post_start.log"
try {
    Start-Transcript -Path $logPath -Force | Out-Null
} catch {
    Write-Host "WARNING: Start-Transcript failed: $($_.Exception.Message)"
}

try {
    Write-Host "=== Setting up Oracle Analytics Desktop ==="

    # Load shared utilities
    $utils = "C:\workspace\scripts\task_utils.ps1"
    if (Test-Path $utils) {
        . $utils
    } else {
        Write-Host "WARNING: task_utils.ps1 not found at $utils"
    }

    # Copy data files to Desktop for easy access
    $dataDir = "C:\Users\Docker\Desktop\OracleAnalyticsData"
    New-Item -ItemType Directory -Force -Path $dataDir | Out-Null
    if (Test-Path "C:\workspace\data\sample_order_lines2023.xlsx") {
        Copy-Item "C:\workspace\data\sample_order_lines2023.xlsx" -Destination $dataDir -Force
        Write-Host "Copied sample_order_lines2023.xlsx to Desktop"
    }
    if (Test-Path "C:\workspace\data\order_lines.csv") {
        Copy-Item "C:\workspace\data\order_lines.csv" -Destination $dataDir -Force
        Write-Host "Copied order_lines.csv to Desktop"
    }

    # Find OAD executable
    $oadExe = $null
    $searchPaths = @(
        "C:\Program Files\Oracle Analytics Desktop",
        "C:\Program Files (x86)\Oracle Analytics Desktop",
        "C:\Users\Docker\AppData\Local\OracleAnalyticsDesktop"
    )

    foreach ($dir in $searchPaths) {
        if (Test-Path $dir) {
            # Search for the main executable
            $found = Get-ChildItem $dir -Recurse -Filter "*.exe" -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match "OAD|dvdesktop|analyticsdesktop|Oracle.*Analytics" } |
                Select-Object -First 1
            if ($found) {
                $oadExe = $found.FullName
                break
            }
        }
    }

    if (-not $oadExe) {
        # Try to find via Start Menu shortcuts
        $shortcuts = Get-ChildItem "C:\ProgramData\Microsoft\Windows\Start Menu\Programs" -Recurse -Filter "*.lnk" -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match "Oracle.*Analytics" }
        if ($shortcuts) {
            $shell = New-Object -ComObject WScript.Shell
            foreach ($sc in $shortcuts) {
                $target = $shell.CreateShortcut($sc.FullName).TargetPath
                if (Test-Path $target) {
                    $oadExe = $target
                    break
                }
            }
        }
    }

    if ($oadExe) {
        Write-Host "Found Oracle Analytics Desktop at: $oadExe"

        # Save the path for task_utils to use
        $oadExe | Out-File -FilePath "C:\Users\Docker\oad_exe_path.txt" -Encoding utf8 -Force

        # Warm-up launch to clear first-run dialogs
        Write-Host "Performing warm-up launch to clear first-run dialogs..."

        # Create batch file for interactive launch via schtasks
        $launchScript = "C:\Windows\Temp\launch_oad.cmd"
        $batchContent = "@echo off`r`nstart `"`" `"$oadExe`""
        [System.IO.File]::WriteAllText($launchScript, $batchContent)

        # Launch via scheduled task in interactive session
        $taskName = "LaunchOAD_Warmup_GA"
        $schedTime = (Get-Date).AddMinutes(1).ToString("HH:mm")
        $prevEAP = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        schtasks /Create /TN $taskName /TR "cmd /c $launchScript" /SC ONCE /ST $schedTime /RL HIGHEST /IT /F 2>$null
        schtasks /Run /TN $taskName 2>$null
        $ErrorActionPreference = $prevEAP

        # Wait for the app to load (OAD is Java-based, can be slow)
        Write-Host "Waiting for Oracle Analytics Desktop to load (30 seconds)..."
        Start-Sleep -Seconds 30

        # Dismiss any first-run dialogs
        $dismissScript = "C:\workspace\scripts\dismiss_dialogs.ps1"
        if (Test-Path $dismissScript) {
            Write-Host "Dismissing dialogs..."
            $dismissTask = "DismissOAD_GA"
            $ErrorActionPreference = "Continue"
            schtasks /Create /TN $dismissTask /TR "powershell -ExecutionPolicy Bypass -File $dismissScript" /SC ONCE /ST 00:00 /RL HIGHEST /IT /F 2>$null
            schtasks /Run /TN $dismissTask 2>$null
            Start-Sleep -Seconds 15
            schtasks /Delete /TN $dismissTask /F 2>$null
            $ErrorActionPreference = $prevEAP
        }

        # Kill the warm-up instance
        Write-Host "Closing warm-up instance..."
        $ErrorActionPreference = "Continue"
        # Kill dvdesktop process directly (confirmed process name from testing)
        Get-Process dvdesktop -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        # Also kill by window title or path match as fallback
        Get-Process | Where-Object {
            ($_.ProcessName -match "OAD|analyticsdesktop") -or
            ($_.MainWindowTitle -match "Oracle.*Analytics") -or
            ($_.Path -and $_.Path -match "Oracle.*Analytics")
        } | Stop-Process -Force -ErrorAction SilentlyContinue
        $ErrorActionPreference = $prevEAP

        Start-Sleep -Seconds 3

        # Clean up scheduled tasks
        $ErrorActionPreference = "Continue"
        schtasks /Delete /TN $taskName /F 2>$null
        $ErrorActionPreference = $prevEAP

        Write-Host "Warm-up launch complete."
    } else {
        Write-Host "WARNING: Oracle Analytics Desktop executable not found."
        Write-Host "The environment may not be properly installed."
        Write-Host "Searching for any Oracle-related executables..."
        Get-ChildItem "C:\Program Files" -Recurse -Filter "*.exe" -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match "Oracle" } | Select-Object -First 5 | ForEach-Object {
                Write-Host "  Found: $($_.FullName)"
            }
    }

    Write-Host "=== Oracle Analytics Desktop setup complete ==="

} catch {
    Write-Host "ERROR in setup script: $($_.Exception.Message)"
    Write-Host $_.ScriptStackTrace
    # Don't re-throw - post_start errors shouldn't block the environment
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
