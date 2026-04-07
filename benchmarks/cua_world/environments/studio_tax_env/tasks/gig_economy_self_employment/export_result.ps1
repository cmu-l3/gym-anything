# export_result.ps1 — post_task hook for gig_economy_self_employment

$ErrorActionPreference = "Continue"

Write-Host "=== Exporting results for gig_economy_self_employment ==="

Start-Sleep -Seconds 3

Get-Process -Name "StudioTax*" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

$startTimestamp = 0
$tsFile = "C:\Users\Docker\task_start_timestamp_gig_economy.txt"
if (Test-Path $tsFile) {
    $startTimestamp = [int](Get-Content $tsFile -ErrorAction SilentlyContinue)
}

$targetFile = "C:\Users\Docker\Documents\StudioTax\dimitri_papadopoulos.24t"
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

# Collect all .24t files to detect wrong-target filing
$allReturnFiles = @()
Get-ChildItem -Path "C:\Users\Docker\Documents" -Recurse -Filter "*.24t" -ErrorAction SilentlyContinue | ForEach-Object {
    $allReturnFiles += @{
        path = $_.FullName
        size = $_.Length
        modified = [int][double]::Parse((Get-Date $_.LastWriteTime -UFormat %s))
    }
}

$result = @{
    task_id                 = "gig_economy_self_employment"
    file_exists             = $fileExists
    file_size_bytes         = $fileSize
    file_mod_time           = $fileModTime
    start_timestamp         = $startTimestamp
    file_is_new             = ($fileModTime -ge $startTimestamp)
    content_sample          = $fileContent
    all_return_files        = $allReturnFiles
    # Taxpayer identity checks
    contains_papadopoulos   = ($fileContent -match "(?i)papadopoulos")
    contains_dimitri        = ($fileContent -match "(?i)dimitri")
    # Uber T4A income check ($34,840)
    contains_34840          = ($fileContent -match "34840")
    # DoorDash T4A income check ($12,180)
    contains_12180          = ($fileContent -match "12180")
    # Combined gross business income ($47,020)
    contains_47020          = ($fileContent -match "47020")
    # Business expense markers (vehicle, CCA)
    contains_7679           = ($fileContent -match "7679")
    contains_2697           = ($fileContent -match "2697")
    # Net business income ($35,527)
    contains_35527          = ($fileContent -match "35527")
    # Self-employment markers (T2125 typically stores SE income differently)
    contains_self_employ    = ($fileContent -match "(?i)(self.?employ|t2125|business.?income|commiss)")
    # Province check
    contains_ontario        = ($fileContent -match "(?i)(ontario|ON)")
    export_timestamp        = [int][double]::Parse((Get-Date -UFormat %s))
}

$resultJson = $result | ConvertTo-Json -Depth 5
$resultPath = "C:\Users\Docker\Desktop\gig_economy_result.json"
Remove-Item -Path $resultPath -Force -ErrorAction SilentlyContinue
Set-Content -Path $resultPath -Value $resultJson -Encoding UTF8

Write-Host "Results exported to $resultPath"
Write-Host "=== Export complete ==="
