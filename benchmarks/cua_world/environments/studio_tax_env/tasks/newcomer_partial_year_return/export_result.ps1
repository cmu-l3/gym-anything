# export_result.ps1 — post_task hook for newcomer_partial_year_return

$ErrorActionPreference = "Continue"

Write-Host "=== Exporting results for newcomer_partial_year_return ==="

Start-Sleep -Seconds 3

Get-Process -Name "StudioTax*" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

$startTimestamp = 0
$tsFile = "C:\Users\Docker\task_start_timestamp_newcomer.txt"
if (Test-Path $tsFile) {
    $startTimestamp = [int](Get-Content $tsFile -ErrorAction SilentlyContinue)
}

$targetFile = "C:\Users\Docker\Documents\StudioTax\amara_osei_mensah.24t"
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
    task_id               = "newcomer_partial_year_return"
    file_exists           = $fileExists
    file_size_bytes       = $fileSize
    file_mod_time         = $fileModTime
    start_timestamp       = $startTimestamp
    file_is_new           = ($fileModTime -ge $startTimestamp)
    content_sample        = $fileContent
    all_return_files      = $allReturnFiles
    # Taxpayer identity
    contains_osei         = ($fileContent -match "(?i)osei")
    contains_mensah       = ($fileContent -match "(?i)mensah")
    contains_amara        = ($fileContent -match "(?i)amara")
    # T4 employment income ($52,800)
    contains_52800        = ($fileContent -match "52800")
    # RPP pension contribution ($2,640)
    contains_2640         = ($fileContent -match "2640")
    # Tax deducted ($10,320)
    contains_10320        = ($fileContent -match "10320")
    # FHSA contribution ($4,000)
    contains_4000         = ($fileContent -match "\b4000\b")
    # Tuition credit ($1,800)
    contains_1800         = ($fileContent -match "\b1800\b")
    # Rent for OTB ($26,550)
    contains_26550        = ($fileContent -match "26550")
    # Arrival date (April 1, 2024 — various formats in file)
    contains_arrival_date = ($fileContent -match "(2024.04.01|04.01.2024|April.1.2024|Apr.1..2024)")
    # Province Ontario
    contains_ontario      = ($fileContent -match "(?i)(ontario|ON)")
    # Part-year resident marker
    contains_part_year    = ($fileContent -match "(?i)(part.year|resident|arrival|became)")
    # Spouse with $0 income
    contains_kwame        = ($fileContent -match "(?i)kwame")
    export_timestamp      = [int][double]::Parse((Get-Date -UFormat %s))
}

$resultJson = $result | ConvertTo-Json -Depth 5
$resultPath = "C:\Users\Docker\Desktop\newcomer_result.json"
Remove-Item -Path $resultPath -Force -ErrorAction SilentlyContinue
Set-Content -Path $resultPath -Value $resultJson -Encoding UTF8

Write-Host "Results exported to $resultPath"
Write-Host "=== Export complete ==="
