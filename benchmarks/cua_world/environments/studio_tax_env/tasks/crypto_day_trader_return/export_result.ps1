# export_result.ps1 — post_task hook for crypto_day_trader_return

$ErrorActionPreference = "Continue"

Write-Host "=== Exporting results for crypto_day_trader_return ==="

Start-Sleep -Seconds 3

Get-Process -Name "StudioTax*" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

$startTimestamp = 0
$tsFile = "C:\Users\Docker\task_start_timestamp_crypto.txt"
if (Test-Path $tsFile) {
    $startTimestamp = [int](Get-Content $tsFile -ErrorAction SilentlyContinue)
}

$targetFile = "C:\Users\Docker\Documents\StudioTax\priya_nair.24t"
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
    task_id               = "crypto_day_trader_return"
    file_exists           = $fileExists
    file_size_bytes       = $fileSize
    file_mod_time         = $fileModTime
    start_timestamp       = $startTimestamp
    file_is_new           = ($fileModTime -ge $startTimestamp)
    content_sample        = $fileContent
    all_return_files      = $allReturnFiles
    # Taxpayer identity
    contains_nair         = ($fileContent -match "(?i)nair")
    contains_priya        = ($fileContent -match "(?i)priya")
    # T4 employment income ($72,500)
    contains_72500        = ($fileContent -match "72500")
    # T5 staking/interest income ($1,840)
    contains_1840         = ($fileContent -match "1840")
    # Capital gains — ETH ($7,600 gain)
    contains_7600         = ($fileContent -match "7600")
    # Capital gains — BTC ($6,400 gain)
    contains_6400         = ($fileContent -match "6400")
    # Capital gains — ETH proceeds ($16,800)
    contains_16800        = ($fileContent -match "16800")
    # MATIC loss ($2,100)
    contains_2100         = ($fileContent -match "2100")
    # RRSP contribution ($5,500)
    contains_5500         = ($fileContent -match "5500")
    # Home office ($2,288 or $2,202)
    contains_2288         = ($fileContent -match "2288")
    contains_2202         = ($fileContent -match "2202")
    # Province BC
    contains_bc           = ($fileContent -match "(?i)(british.columbia|BC)")
    # Capital gains marker
    contains_capgain      = ($fileContent -match "(?i)(capital.gain|schedule.3|sched.3)")
    export_timestamp      = [int][double]::Parse((Get-Date -UFormat %s))
}

$resultJson = $result | ConvertTo-Json -Depth 5
$resultPath = "C:\Users\Docker\Desktop\crypto_trader_result.json"
Remove-Item -Path $resultPath -Force -ErrorAction SilentlyContinue
Set-Content -Path $resultPath -Value $resultJson -Encoding UTF8

Write-Host "Results exported to $resultPath"
Write-Host "=== Export complete ==="
