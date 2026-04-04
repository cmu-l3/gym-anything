# Note: This is export_result.ps1 content

$ErrorActionPreference = "Continue"

Write-Host "=== Exporting Dashboard Task Result ==="

# Paths
$OutputFile = "C:\Users\Docker\Documents\Epi_Info\Dashboards\SymptomProfile.cvs7"
$JsonResultPath = "C:\Users\Docker\AppData\Local\Temp\task_result.json"
$StartTimeFile = "C:\Users\Docker\AppData\Local\Temp\task_start_time.txt"

# Read Start Time
$TaskStart = 0
if (Test-Path $StartTimeFile) {
    $TaskStart = [int](Get-Content $StartTimeFile)
}

# Initialize Result Object
$Result = @{
    "output_exists" = $false
    "file_created_during_task" = $false
    "file_size" = 0
    "app_running" = $false
    "timestamp" = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
}

# Check Application State
$DashboardProcess = Get-Process -Name "AnalysisDashboard" -ErrorAction SilentlyContinue
if ($DashboardProcess) {
    $Result["app_running"] = $true
}

# Check Output File
if (Test-Path $OutputFile) {
    $FileItem = Get-Item $OutputFile
    $Result["output_exists"] = $true
    $Result["file_size"] = $FileItem.Length
    
    # Check modification time
    $ModTime = [int][double]::Parse((Get-Date -Date $FileItem.LastWriteTime -UFormat %s))
    
    if ($ModTime -gt $TaskStart) {
        $Result["file_created_during_task"] = $true
    }
    
    Write-Host "Output file found ($($FileItem.Length) bytes)"
} else {
    Write-Host "Output file NOT found at $OutputFile"
}

# Export Result to JSON
$Result | ConvertTo-Json -Depth 2 | Set-Content $JsonResultPath

Write-Host "Result saved to $JsonResultPath"
Get-Content $JsonResultPath
Write-Host "=== Export Complete ==="