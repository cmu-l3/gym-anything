<#
.SYNOPSIS
    Export script for designate_facility_unmanned task
    Runs in PowerShell on the Windows guest
#>

Write-Host "=== Exporting Task Results ==="

# 1. Define paths
$dbPath = "C:\Users\Docker\Documents\CAMEOfm\cameo_data.mdb"
$resultJsonPath = "C:\tmp\task_result.json"
$taskStartTimePath = "C:\tmp\task_start_time.txt"

# 2. Get Timestamps
$taskEnd = [DateTimeOffset]::Now.ToUnixTimeSeconds()
if (Test-Path $taskStartTimePath) {
    $taskStart = Get-Content -Path $taskStartTimePath
} else {
    $taskStart = 0
}

# 3. Take Final Screenshot
Write-Host "Capturing final state..."
$pythonScript = @"
import pyautogui
try:
    pyautogui.screenshot('C:\\tmp\\task_final.png')
except Exception as e:
    print(e)
"@
Set-Content -Path "C:\tmp\screenshot_final.py" -Value $pythonScript
python "C:\tmp\screenshot_final.py"

# 4. Query Database for Final State
Write-Host "Querying database..."
$mannedStatus = $true # Default fail
$planLocation = ""
$facilityFound = $false

# We do NOT close CAMEO here to avoid disrupting the agent's view if they are watching,
# but we need to be careful about read locks. usually OLEDB read is fine.

$conn = New-Object System.Data.OleDb.OleDbConnection
$conn.ConnectionString = "Provider=Microsoft.ACE.OLEDB.12.0;Data Source=$dbPath;Persist Security Info=False;"

try {
    $conn.Open()
    $cmd = $conn.CreateCommand()
    
    $cmd.CommandText = "SELECT Manned, LocationOfPlans FROM Facilities WHERE FacilityName = 'North Creek Lift Station'"
    $reader = $cmd.ExecuteReader()
    
    if ($reader.Read()) {
        $facilityFound = $true
        # Access stores booleans as bits (-1 or 0 usually in Access SQL, but OLEDB maps to boolean)
        # We handle DBNull as well
        if (!$reader.IsDBNull(0)) {
            $mannedStatus = $reader.GetBoolean(0) 
        }
        if (!$reader.IsDBNull(1)) {
            $planLocation = $reader.GetString(1)
        }
    }
    $reader.Close()
}
catch {
    Write-Error "Database query failed: $_"
}
finally {
    $conn.Close()
    $conn.Dispose()
}

# 5. Check File modification time (Anti-gaming)
$dbFile = Get-Item $dbPath
$dbModTime = [DateTimeOffset]::new($dbFile.LastWriteTime).ToUnixTimeSeconds()
$dbModified = ($dbModTime -gt $taskStart)

# 6. Construct JSON Result
$result = @{
    task_start = [int64]$taskStart
    task_end = [int64]$taskEnd
    db_modified_during_task = $dbModified
    facility_found = $facilityFound
    manned_status = $mannedStatus
    location_of_plans = $planLocation
    screenshot_path = "C:\tmp\task_final.png"
}

# Convert to JSON and save
$json = $result | ConvertTo-Json
$json | Out-File -FilePath $resultJsonPath -Encoding ascii

Write-Host "Result exported to $resultJsonPath"
Write-Host $json
Write-Host "=== Export Complete ==="