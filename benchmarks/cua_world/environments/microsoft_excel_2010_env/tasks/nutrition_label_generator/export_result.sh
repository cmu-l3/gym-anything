# export_result.ps1 (PowerShell content)

$ErrorActionPreference = "Continue"
Write-Host "=== Exporting Results ==="

# 1. Define Paths
$DesktopPath = [Environment]::GetFolderPath("Desktop")
$ExcelFilePath = Join-Path $DesktopPath "ExcelTasks\nutrition_calculator.xlsx"
$ResultJsonPath = "C:\tmp\task_result.json"
$StartTimePath = "C:\tmp\task_start_time.txt"
$InitialHashPath = "C:\tmp\initial_file_hash.txt"

# 2. Capture Timestamps
$EndTime = Get-Date -UFormat %s
if (Test-Path $StartTimePath) {
    $StartTime = Get-Content $StartTimePath
} else {
    $StartTime = 0
}

# 3. Check File Status
$FileExists = Test-Path $ExcelFilePath
$FileCreated = $false
$FileModified = $false
$OutputSize = 0

if ($FileExists) {
    $Item = Get-Item $ExcelFilePath
    $OutputSize = $Item.Length
    
    # Check modification time
    $MTime = $Item.LastWriteTime.ToString("U") # Universal Sortable
    # We can also compare file hash if strict
    
    if (Test-Path $InitialHashPath) {
        $OldHash = Get-Content $InitialHashPath
        $NewHash = (Get-FileHash $ExcelFilePath -Algorithm MD5).Hash
        if ($OldHash -ne $NewHash) {
            $FileModified = $true
        }
    }
}

# 4. Check App Status
$ExcelRunning = (Get-Process "EXCEL" -ErrorAction SilentlyContinue)
$AppRunning = $false
if ($ExcelRunning) {
    $AppRunning = $true
}

# 5. Take Screenshot (using python or nircmd if available, fallback to simple print if not)
# The environment description mentions "recording" but usually we want an explicit final screenshot.
# We'll rely on the framework's automatic capture or use a python script if needed.
# Here we just output the status for the verifier.

# 6. Create JSON Result
$ResultObject = @{
    task_start = $StartTime
    task_end = $EndTime
    output_exists = $FileExists
    file_modified = $FileModified
    output_size_bytes = $OutputSize
    app_was_running = $AppRunning
    xlsx_path = $ExcelFilePath
}

$ResultJson = $ResultObject | ConvertTo-Json
$ResultJson | Out-File -FilePath $ResultJsonPath -Encoding ASCII

Write-Host "Result saved to $ResultJsonPath"
Write-Host "=== Export Complete ==="