# export_result.ps1 — post_task hook for enter_investment_income

$ErrorActionPreference = "Continue"

Write-Host "=== Exporting results for enter_investment_income ==="

Start-Sleep -Seconds 3

Get-Process -Name "StudioTax*" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

$startTimestamp = 0
$tsFile = "C:\Users\Docker\task_start_timestamp_investment.txt"
if (Test-Path $tsFile) {
    $startTimestamp = [int](Get-Content $tsFile -ErrorAction SilentlyContinue)
}

$targetFile = "C:\Users\Docker\Documents\StudioTax\maria_chen.24t"
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
    task_id = "enter_investment_income"
    file_exists = $fileExists
    file_size_bytes = $fileSize
    file_mod_time = $fileModTime
    start_timestamp = $startTimestamp
    file_is_new = ($fileModTime -ge $startTimestamp)
    content_sample = $fileContent
    all_return_files = $allReturnFiles
    contains_maria = ($fileContent -match "(?i)maria")
    contains_chen = ($fileContent -match "(?i)chen")
    contains_65000 = ($fileContent -match "65000")
    contains_3200 = ($fileContent -match "3200")
    contains_1500 = ($fileContent -match "1500")
    contains_4416 = ($fileContent -match "4416")
    contains_15800 = ($fileContent -match "15800")
    contains_5000 = ($fileContent -match "5000")
    contains_dividend = ($fileContent -match "(?i)dividend")
    export_timestamp = [int][double]::Parse((Get-Date -UFormat %s))
}

$resultJson = $result | ConvertTo-Json -Depth 5
$resultPath = "C:\Users\Docker\Desktop\investment_result.json"
Set-Content -Path $resultPath -Value $resultJson -Encoding UTF8

Write-Host "Results exported to $resultPath"
Write-Host "=== Export complete ==="
