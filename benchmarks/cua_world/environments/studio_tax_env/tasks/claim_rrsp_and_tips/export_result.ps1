# export_result.ps1 — post_task hook for claim_rrsp_and_tips

$ErrorActionPreference = "Continue"

Write-Host "=== Exporting results for claim_rrsp_and_tips ==="

Start-Sleep -Seconds 3

Get-Process -Name "StudioTax*" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

$startTimestamp = 0
$tsFile = "C:\Users\Docker\task_start_timestamp_rrsp_tips.txt"
if (Test-Path $tsFile) {
    $startTimestamp = [int](Get-Content $tsFile -ErrorAction SilentlyContinue)
}

$targetFile = "C:\Users\Docker\Documents\StudioTax\terry_lee.24t"
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
        if ($fileContent.Length -gt 5000) {
            $fileContent = $fileContent.Substring(0, 5000)
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
    task_id = "claim_rrsp_and_tips"
    file_exists = $fileExists
    file_size_bytes = $fileSize
    file_mod_time = $fileModTime
    start_timestamp = $startTimestamp
    file_is_new = ($fileModTime -ge $startTimestamp)
    content_sample = $fileContent
    all_return_files = $allReturnFiles
    contains_terry = ($fileContent -match "(?i)terry")
    contains_lee = ($fileContent -match "(?i)lee")
    contains_12000 = ($fileContent -match "12000")
    contains_1000 = ($fileContent -match "1000")
    contains_540 = ($fileContent -match "540")
    contains_rrsp = ($fileContent -match "(?i)rrsp")
    export_timestamp = [int][double]::Parse((Get-Date -UFormat %s))
}

$resultJson = $result | ConvertTo-Json -Depth 5
$resultPath = "C:\Users\Docker\Desktop\rrsp_tips_result.json"
Set-Content -Path $resultPath -Value $resultJson -Encoding UTF8

Write-Host "Results exported to $resultPath"
Write-Host "=== Export complete ==="
