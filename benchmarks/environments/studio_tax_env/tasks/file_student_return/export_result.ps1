# export_result.ps1 — post_task hook for file_student_return

$ErrorActionPreference = "Continue"

Write-Host "=== Exporting results for file_student_return ==="

Start-Sleep -Seconds 3

Get-Process -Name "StudioTax*" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

$startTimestamp = 0
$tsFile = "C:\Users\Docker\task_start_timestamp_student.txt"
if (Test-Path $tsFile) {
    $startTimestamp = [int](Get-Content $tsFile -ErrorAction SilentlyContinue)
}

$targetFile = "C:\Users\Docker\Documents\StudioTax\farah_awan.24t"
$fileExists = Test-Path $targetFile
$fileSize = 0
$fileModTime = 0
$fileContent = ""

if ($fileExists) {
    $fileInfo = Get-Item $targetFile
    $fileSize = $fileInfo.Length
    $fileModTime = [int][double]::Parse((Get-Date $fileInfo.LastWriteTime -UFormat %s))

    try {
        $rawBytes = [System.IO.File]::ReadAllBytes($targetFile)
        $fileContent = [System.Text.Encoding]::UTF8.GetString($rawBytes)
        if ($fileContent.Length -gt 8000) {
            $fileContent = $fileContent.Substring(0, 8000)
        }
    } catch {
        $fileContent = "binary_unreadable"
    }
}

$allReturnFiles = @()
Get-ChildItem -Path "C:\Users\Docker\Documents" -Recurse -Filter "*.24t" -ErrorAction SilentlyContinue | ForEach-Object {
    $allReturnFiles += @{
        path = $_.FullName
        size = $_.Length
        modified = [int][double]::Parse((Get-Date $_.LastWriteTime -UFormat %s))
    }
}

$result = @{
    task_id = "file_student_return"
    file_exists = $fileExists
    file_size_bytes = $fileSize
    file_mod_time = $fileModTime
    start_timestamp = $startTimestamp
    file_is_new = ($fileModTime -ge $startTimestamp)
    content_sample = $fileContent
    all_return_files = $allReturnFiles
    contains_farah = ($fileContent -match "(?i)farah")
    contains_awan = ($fileContent -match "(?i)awan")
    contains_10000 = ($fileContent -match "10000")
    contains_14000 = ($fileContent -match "14000")
    contains_4500 = ($fileContent -match "4500")
    contains_5700 = ($fileContent -match "5700")
    contains_6000 = ($fileContent -match "6000")
    contains_tuition = ($fileContent -match "(?i)tuition")
    contains_scholarship = ($fileContent -match "(?i)scholar")
    export_timestamp = [int][double]::Parse((Get-Date -UFormat %s))
}

$resultJson = $result | ConvertTo-Json -Depth 5
$resultPath = "C:\Users\Docker\Desktop\student_return_result.json"
Set-Content -Path $resultPath -Value $resultJson -Encoding UTF8

Write-Host "Results exported to $resultPath"
Write-Host "=== Export complete ==="
