# export_result.ps1 — nutrition_label_generator
# Saves workbook, captures file metadata, writes result JSON for verifier.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

$logPath = "C:\Users\Docker\task_post_nutrition_label.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { }

try {
    Write-Host "=== Exporting nutrition_label_generator result ==="

    $utils = "C:\workspace\scripts\task_utils.ps1"
    if (Test-Path $utils) { . $utils }

    # Send Ctrl+S to save the workbook
    try {
        Invoke-PyAutoGUICommand -Command @{action = "press"; keys = "ctrl+s"} | Out-Null
        Start-Sleep -Seconds 3
        Invoke-PyAutoGUICommand -Command @{action = "press"; keys = "return"} | Out-Null
        Start-Sleep -Seconds 2
        Write-Host "Ctrl+S sent via PyAutoGUI"
    } catch {
        Write-Host "WARNING: PyAutoGUI Ctrl+S failed: $($_.Exception.Message)"
    }

    # Define Paths
    $DesktopPath = [Environment]::GetFolderPath("Desktop")
    $ExcelFilePath = Join-Path $DesktopPath "ExcelTasks\nutrition_calculator.xlsx"
    $ResultJsonPath = "C:\tmp\task_result.json"
    $StartTimePath = "C:\tmp\task_start_time.txt"
    $InitialHashPath = "C:\tmp\initial_file_hash.txt"

    # Read start time
    $StartTime = 0
    if (Test-Path $StartTimePath) {
        $StartTime = (Get-Content $StartTimePath -Raw).Trim()
    }

    # Check File Status
    $FileExists = Test-Path $ExcelFilePath
    $FileModified = $false
    $OutputSize = 0

    if ($FileExists) {
        $Item = Get-Item $ExcelFilePath
        $OutputSize = $Item.Length

        if (Test-Path $InitialHashPath) {
            $OldHash = (Get-Content $InitialHashPath -Raw).Trim()
            $NewHash = (Get-FileHash $ExcelFilePath -Algorithm MD5).Hash
            if ($OldHash -ne $NewHash) {
                $FileModified = $true
            }
        }
    }

    # Ensure output directory exists
    New-Item -ItemType Directory -Force -Path "C:\tmp" -ErrorAction SilentlyContinue | Out-Null

    # Create JSON Result
    $ResultObject = [ordered]@{
        task_start        = $StartTime
        output_exists     = $FileExists
        file_modified     = $FileModified
        output_size_bytes = $OutputSize
        xlsx_path         = $ExcelFilePath
    }

    $ResultObject | ConvertTo-Json -Depth 5 | Out-File -FilePath $ResultJsonPath -Encoding UTF8 -Force
    Write-Host "Result saved to $ResultJsonPath"

    Write-Host "=== Export complete: nutrition_label_generator ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
