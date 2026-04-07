# export_result.ps1 — post_task hook for real_estate_agent_expenses

$ErrorActionPreference = "Continue"

Write-Host "=== Exporting results for real_estate_agent_expenses ==="

Start-Sleep -Seconds 3

Get-Process -Name "StudioTax*" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

$startTimestamp = 0
$tsFile = "C:\Users\Docker\task_start_timestamp_realestate.txt"
if (Test-Path $tsFile) {
    $startTimestamp = [int](Get-Content $tsFile -ErrorAction SilentlyContinue)
}

$targetFile = "C:\Users\Docker\Documents\StudioTax\rodrigo_espinoza.24t"
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
    task_id               = "real_estate_agent_expenses"
    file_exists           = $fileExists
    file_size_bytes       = $fileSize
    file_mod_time         = $fileModTime
    start_timestamp       = $startTimestamp
    file_is_new           = ($fileModTime -ge $startTimestamp)
    content_sample        = $fileContent
    all_return_files      = $allReturnFiles
    # Taxpayer identity
    contains_espinoza     = ($fileContent -match "(?i)espinoza")
    contains_rodrigo      = ($fileContent -match "(?i)rodrigo")
    # T4 base salary ($36,000)
    contains_36000        = ($fileContent -match "36000")
    # T4A commission income ($87,500)
    contains_87500        = ($fileContent -match "87500")
    # Business expenses — marketing ($10,630)
    contains_10630        = ($fileContent -match "10630")
    # Vehicle operating expense business portion ($8,342)
    contains_8342         = ($fileContent -match "8342")
    # CCA on vehicle ($6,217 business portion)
    contains_6217         = ($fileContent -match "6217")
    # Total business expenses ($40,478)
    contains_40478        = ($fileContent -match "40478")
    # Net commission income ($47,022)
    contains_47022        = ($fileContent -match "47022")
    # RRSP ($10,000)
    contains_10000        = ($fileContent -match "10000")
    # Charitable donation ($500)
    contains_500          = ($fileContent -match "\b500\b")
    # Province Alberta
    contains_alberta      = ($fileContent -match "(?i)(alberta|AB)")
    # Common-law marker
    contains_common_law   = ($fileContent -match "(?i)(common.law|morales)")
    # Professional fees ($6,770)
    contains_6770         = ($fileContent -match "6770")
    export_timestamp      = [int][double]::Parse((Get-Date -UFormat %s))
}

$resultJson = $result | ConvertTo-Json -Depth 5
$resultPath = "C:\Users\Docker\Desktop\realestate_result.json"
Remove-Item -Path $resultPath -Force -ErrorAction SilentlyContinue
Set-Content -Path $resultPath -Value $resultJson -Encoding UTF8

Write-Host "Results exported to $resultPath"
Write-Host "=== Export complete ==="
