# export_result.ps1 — post_task hook for coupled_business_lcge_optimization

$ErrorActionPreference = "Continue"

Write-Host "=== Exporting results for coupled_business_lcge_optimization ==="

Start-Sleep -Seconds 3

Get-Process -Name "StudioTax*" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

$startTimestamp = 0
$tsFile = "C:\Users\Docker\task_start_timestamp_kapoor.txt"
if (Test-Path $tsFile) {
    $startTimestamp = [int](Get-Content $tsFile -ErrorAction SilentlyContinue)
}

$targetFile = "C:\Users\Docker\Documents\StudioTax\kapoor_family.24t"
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
        if ($fileContent.Length -gt 15000) {
            $fileContent = $fileContent.Substring(0, 15000)
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
    task_id               = "coupled_business_lcge_optimization"
    file_exists           = $fileExists
    file_size_bytes       = $fileSize
    file_mod_time         = $fileModTime
    start_timestamp       = $startTimestamp
    file_is_new           = ($fileModTime -ge $startTimestamp)
    content_sample        = $fileContent
    all_return_files      = $allReturnFiles

    # ---- Taxpayer Identity ----
    # Primary taxpayer
    contains_arjun        = ($fileContent -match "(?i)arjun")
    contains_kapoor       = ($fileContent -match "(?i)kapoor")
    # Spouse
    contains_meera        = ($fileContent -match "(?i)meera")
    # Dependants
    contains_rohan        = ($fileContent -match "(?i)rohan")
    contains_anika        = ($fileContent -match "(?i)anika")

    # ---- Arjun's Income ----
    # T2125 net business income $155,400
    contains_155400       = ($fileContent -match "155400")
    # T2125 gross revenue $195,000
    contains_195000       = ($fileContent -match "195000")
    # T2125 expenses $39,600
    contains_39600        = ($fileContent -match "39600")
    # QSBC capital gain $328,000
    contains_328000       = ($fileContent -match "328000")
    # QSBC proceeds $390,000
    contains_390000       = ($fileContent -match "390000")
    # QSBC ACB $50,000
    contains_50000        = ($fileContent -match "50000")
    # T2203 BC revenue allocation $126,750
    contains_126750       = ($fileContent -match "126750")
    # T2203 AB revenue allocation $68,250
    contains_68250        = ($fileContent -match "68250")
    # T3 capital gains $4,600
    contains_4600         = ($fileContent -match "4600")
    # T3 eligible dividends $3,200
    contains_3200_div     = ($fileContent -match "3200")
    # T3 foreign income $2,845
    contains_2845         = ($fileContent -match "2845")
    # T3 foreign tax paid $427
    contains_427          = ($fileContent -match "427")
    # RRSP $22,000
    contains_22000        = ($fileContent -match "22000")
    # LCGE / T657 marker
    contains_lcge         = ($fileContent -match "(?i)(lcge|t657|capital.gains.exemption|capital.gains.deduction)")

    # ---- Meera's Income ----
    # T4 employment income $48,600
    contains_48600        = ($fileContent -match "48600")
    # T776 Rental #1 gross $26,400
    contains_26400        = ($fileContent -match "26400")
    # T776 Rental #1 expenses $20,140
    contains_20140        = ($fileContent -match "20140")
    # T776 Rental #2 gross $8,400
    contains_8400         = ($fileContent -match "8400")
    # T776 Rental #2 expenses $17,300
    contains_17300        = ($fileContent -match "17300")

    # ---- Family Credits and Deductions ----
    # Medical total $6,830
    contains_6830         = ($fileContent -match "6830")
    # Childcare $8,000 (capped) or $12,800 (actual)
    contains_8000         = ($fileContent -match "8000")
    contains_12800        = ($fileContent -match "12800")
    # DTC $15,630
    contains_15630        = ($fileContent -match "15630")
    # Combined donations $8,200 or individual amounts
    contains_8200         = ($fileContent -match "8200")
    contains_5400         = ($fileContent -match "5400")
    contains_2800         = ($fileContent -match "2800")

    # ---- Province ----
    contains_bc           = ($fileContent -match "(?i)(british.columbia|BC)")
    contains_ab           = ($fileContent -match "(?i)(alberta|AB)")

    export_timestamp      = [int][double]::Parse((Get-Date -UFormat %s))
}

$resultJson = $result | ConvertTo-Json -Depth 5
$resultPath = "C:\Users\Docker\Desktop\kapoor_result.json"
Remove-Item -Path $resultPath -Force -ErrorAction SilentlyContinue
Set-Content -Path $resultPath -Value $resultJson -Encoding UTF8

Write-Host "Results exported to $resultPath"
Write-Host "=== Export complete ==="
