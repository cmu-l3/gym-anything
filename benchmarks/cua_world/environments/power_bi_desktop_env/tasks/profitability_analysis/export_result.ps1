# Export script for profitability_analysis task.
# Inspects Profitability_Report.pbix and profit_by_category.csv, outputs result JSON.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

$logPath = "C:\Users\Docker\task_post_task_profitability_analysis.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { }

Write-Host "=== Exporting profitability_analysis result ==="

function Write-Result {
    param($data)
    $data | ConvertTo-Json -Depth 5 | Set-Content -Path "C:\Users\Docker\Desktop\profitability_result.json" -Encoding UTF8
    Write-Host "Result JSON written."
}

$targetPbix  = "C:\Users\Docker\Desktop\Profitability_Report.pbix"
$targetCsv   = "C:\Users\Docker\Desktop\profit_by_category.csv"
$extractPath = "C:\Users\Docker\Desktop\pbix_extracted_pa"

$startTimestamp = 0
try { $startTimestamp = [int](Get-Content "C:\Users\Docker\task_start_timestamp_profitability.txt" -ErrorAction SilentlyContinue) } catch { }

Start-Sleep -Seconds 3
Get-Process PBIDesktop -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Get-Process msmdsrv -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

# Default result
$resultData = @{
    file_exists = $false
    file_size_bytes = 0
    page_count = 0
    visual_types = @()
    model_text_sample = ""
    full_layout_search = ""
    csv_exists = $false
    csv_row_count = 0
    csv_preview = ""
    start_timestamp = $startTimestamp
    export_timestamp = [int][double]::Parse((Get-Date -UFormat %s))
}

# Check CSV file
if (Test-Path $targetCsv) {
    $resultData.csv_exists = $true
    $csvContent = Get-Content $targetCsv -ErrorAction SilentlyContinue
    $resultData.csv_row_count = if ($csvContent) { $csvContent.Count } else { 0 }
    $preview = ($csvContent | Select-Object -First 10) -join "`n"
    $resultData.csv_preview = $preview
    Write-Host "CSV found: $targetCsv ($($resultData.csv_row_count) rows)"
} else {
    Write-Host "CSV not found: $targetCsv"
}

if (-not (Test-Path $targetPbix)) {
    Write-Host "Target .pbix not found."
    Write-Result $resultData
    try { Stop-Transcript | Out-Null } catch { }
    exit 0
}

$fileInfo = Get-Item $targetPbix
$resultData.file_exists = $true
$resultData.file_size_bytes = $fileInfo.Length
$resultData.file_mod_time = [int][double]::Parse((Get-Date $fileInfo.LastWriteTime -UFormat %s))
Write-Host "Found: $targetPbix ($($fileInfo.Length) bytes)"

# Unzip
if (Test-Path $extractPath) { Remove-Item $extractPath -Recurse -Force -ErrorAction SilentlyContinue }
New-Item -ItemType Directory -Force -Path $extractPath | Out-Null
$zipPath = "$extractPath\report.zip"
Copy-Item $targetPbix $zipPath
try {
    Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force -ErrorAction Stop
} catch {
    Write-Host "WARNING: Could not expand .pbix: $($_.Exception.Message)"
    Write-Result $resultData
    try { Stop-Transcript | Out-Null } catch { }
    exit 0
}

# Parse Report/Layout
$layoutFile = "$extractPath\Report\Layout"
if (Test-Path $layoutFile) {
    try {
        $layoutBytes = [System.IO.File]::ReadAllBytes($layoutFile)
        $layoutText = [System.Text.Encoding]::Unicode.GetString($layoutBytes)
        if ($layoutText.Length -lt 100) { $layoutText = [System.Text.Encoding]::UTF8.GetString($layoutBytes) }

        $resultData.full_layout_search = if ($layoutText.Length -gt 8000) { $layoutText.Substring(0, 8000) } else { $layoutText }

        $layout = $layoutText | ConvertFrom-Json
        if ($layout.sections) {
            $resultData.page_count = $layout.sections.Count
            $resultData.page_names = @($layout.sections | ForEach-Object { $_.displayName })
            $vt = @()
            foreach ($section in $layout.sections) {
                if ($section.visualContainers) {
                    foreach ($vc in $section.visualContainers) {
                        try {
                            $cfg = $vc.config | ConvertFrom-Json
                            $t = $cfg.singleVisual.visualType
                            if ($t) { $vt += $t }
                        } catch { }
                    }
                }
            }
            $resultData.visual_types = ($vt | Sort-Object -Unique)
            Write-Host "Pages: $($resultData.page_count), Visuals: $($vt -join ', ')"
        }
    } catch { Write-Host "WARNING: Layout parse failed: $($_.Exception.Message)" }
}

# Read DataModel binary for measure names
$modelFile = "$extractPath\DataModel"
if (Test-Path $modelFile) {
    try {
        $modelBytes = [System.IO.File]::ReadAllBytes($modelFile)
        $u16 = [System.Text.Encoding]::Unicode.GetString($modelBytes)
        $u8  = [System.Text.Encoding]::UTF8.GetString($modelBytes)
        $combined = ($u16 + " " + $u8)
        $resultData.model_text_sample = if ($combined.Length -gt 6000) { $combined.Substring(0, 6000) } else { $combined }
    } catch { Write-Host "WARNING: Could not read DataModel: $($_.Exception.Message)" }
}

Write-Result $resultData

try { Remove-Item $extractPath -Recurse -Force -ErrorAction SilentlyContinue } catch { }
Write-Host "=== Export Complete ==="
try { Stop-Transcript | Out-Null } catch { }
