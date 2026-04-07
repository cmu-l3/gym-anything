# export_result.ps1 — post_task hook for locum_physician_self_employment

$ErrorActionPreference = "Continue"

Write-Host "=== Exporting results for locum_physician_self_employment ==="

Start-Sleep -Seconds 3

Get-Process -Name "StudioTax*" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

$startTimestamp = 0
$tsFile = "C:\Users\Docker\task_start_timestamp_physician.txt"
if (Test-Path $tsFile) {
    $startTimestamp = [int](Get-Content $tsFile -ErrorAction SilentlyContinue)
}

$targetFile = "C:\Users\Docker\Documents\StudioTax\aisha_kamara.24t"
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
    task_id                 = "locum_physician_self_employment"
    file_exists             = $fileExists
    file_size_bytes         = $fileSize
    file_mod_time           = $fileModTime
    start_timestamp         = $startTimestamp
    file_is_new             = ($fileModTime -ge $startTimestamp)
    content_sample          = $fileContent
    all_return_files        = $allReturnFiles
    # Taxpayer identity
    contains_kamara         = ($fileContent -match "(?i)kamara")
    contains_aisha          = ($fileContent -match "(?i)aisha")
    # T4 from Sunnybrook ($145,000)
    contains_145000         = ($fileContent -match "145000")
    # T4A locum income ($48,000)
    contains_48000          = ($fileContent -match "48000")
    # Professional expenses
    contains_8615           = ($fileContent -match "8615")
    contains_1675           = ($fileContent -match "1675")
    contains_3200           = ($fileContent -match "3200")
    # Net locum business income ($39,385)
    contains_39385          = ($fileContent -match "39385")
    # RRSP contribution ($28,900)
    contains_28900          = ($fileContent -match "28900")
    # RPP/pension from T4 ($12,650)
    contains_12650          = ($fileContent -match "12650")
    # Union dues ($2,100)
    contains_2100           = ($fileContent -match "2100")
    # Province Ontario
    contains_ontario        = ($fileContent -match "(?i)(ontario|ON)")
    # Married status / spouse income
    contains_38400          = ($fileContent -match "38400")
    # Self-employment markers
    contains_self_employ    = ($fileContent -match "(?i)(self.?employ|t2125|business.?income)")
    export_timestamp        = [int][double]::Parse((Get-Date -UFormat %s))
}

$resultJson = $result | ConvertTo-Json -Depth 5
$resultPath = "C:\Users\Docker\Desktop\physician_result.json"
Remove-Item -Path $resultPath -Force -ErrorAction SilentlyContinue
Set-Content -Path $resultPath -Value $resultJson -Encoding UTF8

Write-Host "Results exported to $resultPath"
Write-Host "=== Export complete ==="
