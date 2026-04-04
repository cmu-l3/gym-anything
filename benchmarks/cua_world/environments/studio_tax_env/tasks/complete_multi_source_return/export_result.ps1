# export_result.ps1 — post_task hook for complete_multi_source_return

$ErrorActionPreference = "Continue"

Write-Host "=== Exporting results for complete_multi_source_return ==="

Start-Sleep -Seconds 3

Get-Process -Name "StudioTax*" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

$startTimestamp = 0
$tsFile = "C:\Users\Docker\task_start_timestamp_multi_source.txt"
if (Test-Path $tsFile) {
    $startTimestamp = [int](Get-Content $tsFile -ErrorAction SilentlyContinue)
}

$targetFile = "C:\Users\Docker\Documents\StudioTax\han_park.24t"
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
        if ($fileContent.Length -gt 10000) {
            $fileContent = $fileContent.Substring(0, 10000)
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
    task_id = "complete_multi_source_return"
    file_exists = $fileExists
    file_size_bytes = $fileSize
    file_mod_time = $fileModTime
    start_timestamp = $startTimestamp
    file_is_new = ($fileModTime -ge $startTimestamp)
    content_sample = $fileContent
    all_return_files = $allReturnFiles
    contains_han = ($fileContent -match "(?i)\bhan\b")
    contains_park = ($fileContent -match "(?i)park")
    contains_32000 = ($fileContent -match "32000")
    contains_28000 = ($fileContent -match "28000")
    contains_60000 = ($fileContent -match "60000")
    contains_3830 = ($fileContent -match "3830")
    contains_1200_donations = ($fileContent -match "1200")
    contains_medical = ($fileContent -match "(?i)medical")
    contains_charit = ($fileContent -match "(?i)charit|donat")
    contains_maple_leaf = ($fileContent -match "(?i)maple")
    contains_northern = ($fileContent -match "(?i)northern")
    export_timestamp = [int][double]::Parse((Get-Date -UFormat %s))
}

$resultJson = $result | ConvertTo-Json -Depth 5
$resultPath = "C:\Users\Docker\Desktop\multi_source_result.json"
Set-Content -Path $resultPath -Value $resultJson -Encoding UTF8

Write-Host "Results exported to $resultPath"
Write-Host "=== Export complete ==="
