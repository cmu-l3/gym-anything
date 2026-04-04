# Export script for cross_source_analysis task.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

$logPath = "C:\Users\Docker\task_post_task_cross_source_analysis.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { }

Write-Host "=== Exporting cross_source_analysis result ==="

function Write-Result {
    param($data)
    $data | ConvertTo-Json -Depth 5 | Set-Content -Path "C:\Users\Docker\Desktop\cross_source_result.json" -Encoding UTF8
    Write-Host "Result JSON written."
}

$targetPbix  = "C:\Users\Docker\Desktop\Integrated_Analysis.pbix"
$extractPath = "C:\Users\Docker\Desktop\pbix_extracted_csa"

$startTimestamp = 0
try { $startTimestamp = [int](Get-Content "C:\Users\Docker\task_start_timestamp_csa.txt" -ErrorAction SilentlyContinue) } catch { }

Start-Sleep -Seconds 3
Get-Process PBIDesktop -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Get-Process msmdsrv -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

$resultData = @{
    file_exists = $false
    file_size_bytes = 0
    page_count = 0
    page_names = @()
    visual_types = @()
    full_layout_search = ""
    mashup_m_code = ""
    model_text_sample = ""
    start_timestamp = $startTimestamp
    export_timestamp = [int][double]::Parse((Get-Date -UFormat %s))
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
        $resultData.full_layout_search = if ($layoutText.Length -gt 10000) { $layoutText.Substring(0, 10000) } else { $layoutText }

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
            Write-Host "Pages: $($resultData.page_count) ($($resultData.page_names -join ', ')), Visuals: $($vt -join ', ')"
        }
    } catch { Write-Host "WARNING: Layout parse failed: $($_.Exception.Message)" }
}

# Read DataMashup — critical to check for TWO data sources
$mashupFile = "$extractPath\DataMashup"
if (Test-Path $mashupFile) {
    try {
        $mashupZipPath = "$extractPath\DataMashup.zip"
        Copy-Item $mashupFile $mashupZipPath
        $mashupExtractPath = "$extractPath\mashup_extracted"
        New-Item -ItemType Directory -Force -Path $mashupExtractPath | Out-Null
        try {
            Expand-Archive -Path $mashupZipPath -DestinationPath $mashupExtractPath -Force -ErrorAction Stop
            $mFiles = Get-ChildItem $mashupExtractPath -Recurse -File -ErrorAction SilentlyContinue
            $mCode = ($mFiles | ForEach-Object {
                try { Get-Content $_.FullName -Raw -Encoding UTF8 -ErrorAction SilentlyContinue } catch { "" }
            }) -join "`n"
            $resultData.mashup_m_code = if ($mCode.Length -gt 8000) { $mCode.Substring(0, 8000) } else { $mCode }
        } catch {
            Write-Host "WARNING: Could not expand DataMashup inner ZIP."
            $rawBytes = [System.IO.File]::ReadAllBytes($mashupFile)
            $rawText = [System.Text.Encoding]::UTF8.GetString($rawBytes)
            $resultData.mashup_m_code = if ($rawText.Length -gt 8000) { $rawText.Substring(0, 8000) } else { $rawText }
        }
    } catch { Write-Host "WARNING: DataMashup processing failed." }
}

# Read DataModel binary for Sales_Per_Head measure
$modelFile = "$extractPath\DataModel"
if (Test-Path $modelFile) {
    try {
        $modelBytes = [System.IO.File]::ReadAllBytes($modelFile)
        $u16 = [System.Text.Encoding]::Unicode.GetString($modelBytes)
        $u8  = [System.Text.Encoding]::UTF8.GetString($modelBytes)
        $combined = ($u16 + " " + $u8)
        $resultData.model_text_sample = if ($combined.Length -gt 6000) { $combined.Substring(0, 6000) } else { $combined }
    } catch { Write-Host "WARNING: Could not read DataModel." }
}

Write-Result $resultData
try { Remove-Item $extractPath -Recurse -Force -ErrorAction SilentlyContinue } catch { }
Write-Host "=== Export Complete ==="
try { Stop-Transcript | Out-Null } catch { }
