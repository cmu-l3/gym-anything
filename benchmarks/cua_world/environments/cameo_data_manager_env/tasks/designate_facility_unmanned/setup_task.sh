<#
.SYNOPSIS
    Setup script for designate_facility_unmanned task
    Runs in PowerShell on the Windows guest
#>

Write-Host "=== Setting up task: Designate Facility Unmanned ==="

# 1. Define paths and variables
$dbPath = "C:\Users\Docker\Documents\CAMEOfm\cameo_data.mdb"
$taskStartTimePath = "C:\tmp\task_start_time.txt"
$initialStatePath = "C:\tmp\initial_state.json"
$screenshotPath = "C:\tmp\task_initial.png"

# Ensure temp dir exists
if (!(Test-Path "C:\tmp")) { New-Item -ItemType Directory -Force -Path "C:\tmp" }

# 2. Record Start Time
$startTime = [DateTimeOffset]::Now.ToUnixTimeSeconds()
$startTime | Out-File -FilePath $taskStartTimePath -Encoding ascii -NoNewline

# 3. Kill CAMEO to release DB locks
Write-Host "Closing CAMEO Data Manager..."
Stop-Process -Name "CAMEOfm" -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

# 4. Inject Initial Data (Manned=True, No Plan Location)
Write-Host "Injecting initial facility data..."

$conn = New-Object System.Data.OleDb.OleDbConnection
$conn.ConnectionString = "Provider=Microsoft.ACE.OLEDB.12.0;Data Source=$dbPath;Persist Security Info=False;"

try {
    $conn.Open()
    $cmd = $conn.CreateCommand()

    # Check if facility exists
    $cmd.CommandText = "SELECT COUNT(*) FROM Facilities WHERE FacilityName = 'North Creek Lift Station'"
    $count = $cmd.ExecuteScalar()

    if ($count -eq 0) {
        Write-Host "Creating new facility record..."
        # Insert new facility with Manned=1 (True) and empty LocationOfPlans
        # Note: Schema assumptions based on standard CAMEO structure. 
        # Using parameterized queries is better but string interpolation is simpler for setup script
        $cmd.CommandText = "INSERT INTO Facilities (FacilityName, StreetAddress, City, State, Zip, Manned, LocationOfPlans) VALUES ('North Creek Lift Station', '8800 North Creek Rd', 'Anytown', 'KS', '66002', 1, '')"
        $cmd.ExecuteNonQuery()
    } else {
        Write-Host "Resetting existing facility record..."
        # Reset to bad state
        $cmd.CommandText = "UPDATE Facilities SET Manned = 1, LocationOfPlans = '' WHERE FacilityName = 'North Creek Lift Station'"
        $cmd.ExecuteNonQuery()
    }
    
    Write-Host "Database preparation complete."
}
catch {
    Write-Error "Database setup failed: $_"
    exit 1
}
finally {
    $conn.Close()
    $conn.Dispose()
}

# 5. Start CAMEO Data Manager
Write-Host "Starting CAMEO Data Manager..."
$cameoPath = "C:\Program Files (x86)\CAMEO Data Manager\CAMEOfm.exe"
if (Test-Path $cameoPath) {
    Start-Process -FilePath $cameoPath
} else {
    # Try alternate path just in case
    Start-Process -FilePath "C:\Program Files\CAMEO Data Manager\CAMEOfm.exe"
}

# 6. Wait for UI and Maximize
Write-Host "Waiting for application window..."
$wsh = New-Object -ComObject WScript.Shell
for ($i=0; $i -lt 30; $i++) {
    if ($wsh.AppActivate("CAMEO Data Manager")) {
        Write-Host "Window found."
        break
    }
    Start-Sleep -Seconds 1
}

# Simple maximization via keystrokes or PowerShell UI automation
# (Alt+Space, X is standard Windows maximize shortcut)
Start-Sleep -Seconds 2
if ($wsh.AppActivate("CAMEO Data Manager")) {
    $wsh.SendKeys("% x") 
}

# 7. Take Initial Screenshot (using Python if available, or simple PS method)
Write-Host "Taking initial screenshot..."
$pythonScript = @"
import pyautogui
try:
    pyautogui.screenshot('C:\\tmp\\task_initial.png')
except Exception as e:
    print(e)
"@
Set-Content -Path "C:\tmp\screenshot.py" -Value $pythonScript
python "C:\tmp\screenshot.py"

Write-Host "=== Setup Complete ==="