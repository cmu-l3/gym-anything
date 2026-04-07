# Note: This is a PowerShell script saved with .ps1 extension in the environment
# But for the framework's file generation, we provide the content here.
# Content of setup_task.ps1

Write-Host "=== Setting up StatCalc Cohort Sample Size Task ==="

# 1. timestamp for anti-gaming
$startTime = [DateTimeOffset]::Now.ToUnixTimeSeconds()
$startTime | Out-File -FilePath "C:\Users\Docker\Documents\task_start_time.txt" -Encoding ascii -Force

# 2. Clean up previous artifacts
$outputFile = "C:\Users\Docker\Documents\silicosis_sample_size.txt"
if (Test-Path $outputFile) {
    Remove-Item $outputFile -Force
}

# 3. Start Epi Info 7 if not running
$processName = "EpiInfo"
if (-not (Get-Process $processName -ErrorAction SilentlyContinue)) {
    Write-Host "Starting Epi Info 7..."
    # Assuming standard install location from env spec
    $epiPath = "C:\Epi_Info_7\EpiInfo.exe" 
    if (-not (Test-Path $epiPath)) {
        # Try common alternative
        $epiPath = "C:\Program Files (x86)\CDC\Epi Info 7\EpiInfo.exe"
    }
    
    if (Test-Path $epiPath) {
        Start-Process -FilePath $epiPath -WorkingDirectory (Split-Path $epiPath)
        Start-Sleep -Seconds 10
    } else {
        Write-Host "WARNING: EpiInfo.exe not found in expected paths."
    }
}

# 4. Ensure window is maximized (using simplistic approach or expecting agent to handle)
# In Windows containers, programmatic window management is tricky without tools like nircmd.
# We trust the pre-installed environment tools or the agent.
# Attempting to maximize using PowerShell (if WASP module or similar is present, otherwise skip)

Write-Host "=== Task Setup Complete ==="