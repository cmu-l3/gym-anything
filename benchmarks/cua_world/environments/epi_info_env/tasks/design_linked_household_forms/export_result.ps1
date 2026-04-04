# Note: This is export_result.ps1

Write-Host "=== Exporting task results ==="

# Define paths
$ProjectDir = "C:\Users\Docker\Documents\Epi Info 7\Projects\HouseholdSurvey"
$PrjFile = "$ProjectDir\HouseholdSurvey.prj"
$TimestampFile = "C:\Users\Docker\AppData\Local\Temp\task_start_time.txt"
$ResultJson = "C:\Users\Docker\AppData\Local\Temp\task_result.json"

# 1. Get Task Start Time
If (Test-Path $TimestampFile) {
    $TaskStart = Get-Content -Path $TimestampFile
} Else {
    $TaskStart = 0
}

# 2. Check Project File
$PrjExists = $false
$PrjCreatedDuringTask = $false
$PrjSize = 0

If (Test-Path $PrjFile) {
    $PrjExists = $true
    $Item = Get-Item $PrjFile
    $PrjSize = $Item.Length
    
    # Check creation/modification time
    $ModTime = [int64]($Item.LastWriteTime.ToUniversalTime() - (Get-Date "1/1/1970")).TotalSeconds
    
    If ($ModTime -gt $TaskStart) {
        $PrjCreatedDuringTask = $true
    }
}

# 3. Create JSON Result
$ResultObject = @{
    task_start = $TaskStart
    project_exists = $PrjExists
    project_path = $PrjFile
    file_created_during_task = $PrjCreatedDuringTask
    file_size_bytes = $PrjSize
    timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
}

$ResultObject | ConvertTo-Json -Depth 5 | Set-Content -Path $ResultJson

Write-Host "Result saved to $ResultJson"
Get-Content -Path $ResultJson
Write-Host "=== Export complete ==="