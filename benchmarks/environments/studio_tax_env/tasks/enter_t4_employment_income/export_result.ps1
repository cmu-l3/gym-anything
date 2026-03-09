# export_result.ps1 — post_task hook for enter_t4_employment_income
# Exports task results for verification

$ErrorActionPreference = "Continue"

Write-Host "=== Exporting results for enter_t4_employment_income ==="

Start-Sleep -Seconds 3

# Close StudioTax to flush saves
Get-Process -Name "StudioTax*" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

# Read start timestamp
$startTimestamp = 0
$tsFile = "C:\Users\Docker\task_start_timestamp_t4_employment.txt"
if (Test-Path $tsFile) {
    $startTimestamp = [int](Get-Content $tsFile -ErrorAction SilentlyContinue)
}

# Check for output file
$targetFile = "C:\Users\Docker\Documents\StudioTax\jonah_smith.24t"
$fileExists = Test-Path $targetFile
$fileSize = 0
$fileModTime = 0
$fileContent = ""

if ($fileExists) {
    $fileInfo = Get-Item $targetFile
    $fileSize = $fileInfo.Length
    $fileModTime = [int][double]::Parse((Get-Date $fileInfo.LastWriteTime -UFormat %s))

    # Try to read file content (may be binary or text)
    try {
        $rawBytes = [System.IO.File]::ReadAllBytes($targetFile)
        # Try UTF-8 first
        $fileContent = [System.Text.Encoding]::UTF8.GetString($rawBytes)
        if ($fileContent.Length -gt 5000) {
            $fileContent = $fileContent.Substring(0, 5000)
        }
    } catch {
        $fileContent = "binary_unreadable"
    }
}

# Search for any .24t files in Documents
$allReturnFiles = @()
Get-ChildItem -Path "C:\Users\Docker\Documents" -Recurse -Filter "*.24t" -ErrorAction SilentlyContinue | ForEach-Object {
    $allReturnFiles += @{
        path = $_.FullName
        size = $_.Length
        modified = [int][double]::Parse((Get-Date $_.LastWriteTime -UFormat %s))
    }
}

# Build result JSON
$result = @{
    task_id = "enter_t4_employment_income"
    file_exists = $fileExists
    file_size_bytes = $fileSize
    file_mod_time = $fileModTime
    start_timestamp = $startTimestamp
    file_is_new = ($fileModTime -ge $startTimestamp)
    content_sample = $fileContent
    all_return_files = $allReturnFiles
    contains_jonah = ($fileContent -match "(?i)jonah")
    contains_smith = ($fileContent -match "(?i)smith")
    contains_18000 = ($fileContent -match "18000")
    export_timestamp = [int][double]::Parse((Get-Date -UFormat %s))
}

$resultJson = $result | ConvertTo-Json -Depth 5
$resultPath = "C:\Users\Docker\Desktop\t4_employment_result.json"
Set-Content -Path $resultPath -Value $resultJson -Encoding UTF8

Write-Host "Results exported to $resultPath"
Write-Host "=== Export complete ==="
