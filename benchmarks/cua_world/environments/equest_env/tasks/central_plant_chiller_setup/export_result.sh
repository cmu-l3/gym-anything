# Note: In the equest_env (Windows), this file should be saved as export_result.ps1

Write-Host "=== Exporting Task Result ==="

$ProjectDir = "C:\Users\Docker\Documents\eQUEST 3-65 Projects\4StoreyBuilding"
$ProjectFile = "$ProjectDir\4StoreyBuilding.inp"
$ResultJson = "C:\Users\Docker\task_result.json"
$ResultInp = "C:\Users\Docker\task_result.inp"
$StartTimeFile = "C:\Users\Docker\task_start_time.txt"

# 1. Take Final Screenshot
Get-Screenshot -OutputPath "C:\Users\Docker\task_final.png"

# 2. Check File Timestamps
$TaskStartTime = 0
if (Test-Path $StartTimeFile) {
    $TaskStartTime = [double](Get-Content $StartTimeFile)
}

$FileExists = Test-Path $ProjectFile
$FileModified = $false
$FileSize = 0
$ModificationTime = 0

if ($FileExists) {
    $Item = Get-Item $ProjectFile
    $FileSize = $Item.Length
    # Get Unix timestamp for modification
    $ModificationTime = (Get-Date $Item.LastWriteTime -UFormat %s)
    
    if ($ModificationTime -gt $TaskStartTime) {
        $FileModified = $true
    }
    
    # Copy the INP file to a result location for the verifier to pick up
    Copy-Item -Path $ProjectFile -Destination $ResultInp -Force
}

# 3. Check if eQUEST is running
$AppRunning = [bool](Get-Process -Name "equest" -ErrorAction SilentlyContinue)

# 4. Create JSON Result
$ResultObject = @{
    task_start = $TaskStartTime
    file_exists = $FileExists
    file_modified_during_task = $FileModified
    file_size_bytes = $FileSize
    modification_time = $ModificationTime
    app_was_running = $AppRunning
    inp_path_container = $ResultInp
}

$ResultObject | ConvertTo-Json | Out-File -FilePath $ResultJson -Encoding ascii -Force

Write-Host "Result exported to $ResultJson"
Type $ResultJson
Write-Host "=== Export Complete ==="