# Export script for yoy_performance_dashboard task.
# Extracts .pbix internals (layout, data model, mashup) into a JSON for verification.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

$logPath = "C:\Users\Docker\task_post_task_yoy_performance_dashboard.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { }

Write-Host "=== Exporting yoy_performance_dashboard result ==="

function Write-Result {
    param($data)
    $data | ConvertTo-Json -Depth 5 | Set-Content -Path "C:\Users\Docker\Desktop\yoy_performance_result.json" -Encoding UTF8
    Write-Host "Result JSON written."
}

$targetPbix = "C:\Users\Docker\Desktop\YoY_Performance.pbix"
$extractPath = "C:\Users\Docker\Desktop\pbix_extracted_yoy"

$startTimestamp = 0
try { $startTimestamp = [int](Get-Content "C:\Users\Docker\task_start_timestamp_yoy_performance.txt" -ErrorAction SilentlyContinue) } catch { }

# Wait briefly then kill Power BI to release file locks
Start-Sleep -Seconds 3
Get-Process PBIDesktop -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Get-Process msmdsrv -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

# Early exit if file not found
if (-not (Test-Path $targetPbix)) {
    Write-Host "Target file not found: $targetPbix"
    Write-Result @{
        file_exists = $false
        file_size_bytes = 0
        page_count = 0
        page_names = @()
        visual_types = @()
        layout_text = ""
        model_text_sample = ""
        full_layout_search = ""
        mashup_m_code = ""
        start_timestamp = $startTimestamp
        export_timestamp = [int][double]::Parse((Get-Date -UFormat %s))
    }
    try { Stop-Transcript | Out-Null } catch { }
    exit 0
}

$fileInfo = Get-Item $targetPbix
$fileSizeBytes = $fileInfo.Length
$fileModTime = [int][double]::Parse((Get-Date $fileInfo.LastWriteTime -UFormat %s))

# Extract the .pbix (it's a ZIP)
if (Test-Path $extractPath) { Remove-Item $extractPath -Recurse -Force -ErrorAction SilentlyContinue }
New-Item -ItemType Directory -Force -Path $extractPath | Out-Null

$zipPath = "$extractPath\report.zip"
Copy-Item $targetPbix $zipPath
try {
    Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force -ErrorAction Stop
} catch {
    Write-Host "WARNING: Could not expand .pbix: $($_.Exception.Message)"
    Write-Result @{
        file_exists = $true
        file_size_bytes = $fileSizeBytes
        file_mod_time = $fileModTime
        page_count = 0
        page_names = @()
        visual_types = @()
        error = $_.Exception.Message
        start_timestamp = $startTimestamp
        export_timestamp = [int][double]::Parse((Get-Date -UFormat %s))
    }
    try { Stop-Transcript | Out-Null } catch { }
    exit 0
}

# Parse Report/Layout (Unicode-encoded JSON inside the .pbix)
$layoutFile = "$extractPath\Report\Layout"
$pageCount = 0; $pageNames = @(); $visualTypes = @()
$layoutTextSnippet = ""; $fullLayoutForSearch = ""

if (Test-Path $layoutFile) {
    try {
        $layoutBytes = [System.IO.File]::ReadAllBytes($layoutFile)
        $layoutText = [System.Text.Encoding]::Unicode.GetString($layoutBytes)
        if ($layoutText.Length -lt 100) {
            $layoutText = [System.Text.Encoding]::UTF8.GetString($layoutBytes)
        }
        $layoutTextSnippet = if ($layoutText.Length -gt 2000) { $layoutText.Substring(0, 2000) } else { $layoutText }
        $fullLayoutForSearch = if ($layoutText.Length -gt 15000) { $layoutText.Substring(0, 15000) } else { $layoutText }

        $layout = $layoutText | ConvertFrom-Json
        if ($layout.sections) {
            $pageCount = $layout.sections.Count
            $pageNames = @($layout.sections | ForEach-Object { $_.displayName })
            foreach ($section in $layout.sections) {
                if ($section.visualContainers) {
                    foreach ($vc in $section.visualContainers) {
                        try {
                            $vcConfig = $vc.config | ConvertFrom-Json
                            $vtype = $vcConfig.singleVisual.visualType
                            if ($vtype) { $visualTypes += $vtype }
                        } catch { }
                    }
                }
            }
        }
        Write-Host "Pages: $($pageCount) ($($pageNames -join ', ')), Visuals: $($visualTypes -join ', ')"
    } catch {
        Write-Host "WARNING: Layout parse failed: $($_.Exception.Message)"
    }
}

# Read DataModel binary (contains DAX measure names, table names as searchable text)
$modelTextSample = ""
$modelFile = "$extractPath\DataModel"
if (Test-Path $modelFile) {
    try {
        $modelBytes = [System.IO.File]::ReadAllBytes($modelFile)
        $modelTextUnicode = [System.Text.Encoding]::Unicode.GetString($modelBytes)
        $modelTextUtf8 = [System.Text.Encoding]::UTF8.GetString($modelBytes)
        $combined = ($modelTextUnicode + " " + $modelTextUtf8)
        $modelTextSample = if ($combined.Length -gt 8000) { $combined.Substring(0, 8000) } else { $combined }
    } catch {
        Write-Host "WARNING: Could not read DataModel."
    }
}

# Read DataMashup (contains M/Power Query code referencing data sources)
$mashupCode = ""
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
            $mashupCode = if ($mCode.Length -gt 8000) { $mCode.Substring(0, 8000) } else { $mCode }
        } catch {
            Write-Host "WARNING: Could not expand DataMashup inner ZIP."
            $rawBytes = [System.IO.File]::ReadAllBytes($mashupFile)
            $rawText = [System.Text.Encoding]::UTF8.GetString($rawBytes)
            $mashupCode = if ($rawText.Length -gt 8000) { $rawText.Substring(0, 8000) } else { $rawText }
        }
    } catch {
        Write-Host "WARNING: DataMashup processing failed."
    }
}

# Write the result JSON
Write-Result @{
    file_exists = $true
    file_size_bytes = $fileSizeBytes
    file_mod_time = $fileModTime
    file_created_during_task = ($fileModTime -gt $startTimestamp)
    file_created_after_start = ($fileModTime -gt $startTimestamp)
    file_fresh = ($fileModTime -gt $startTimestamp)
    page_count = $pageCount
    page_names = $pageNames
    visual_types = ($visualTypes | Sort-Object -Unique)
    layout_text = $layoutTextSnippet
    model_text_sample = $modelTextSample
    full_layout_search = $fullLayoutForSearch
    mashup_m_code = $mashupCode
    start_timestamp = $startTimestamp
    export_timestamp = [int][double]::Parse((Get-Date -UFormat %s))
}

# Cleanup extracted files
try { Remove-Item $extractPath -Recurse -Force -ErrorAction SilentlyContinue } catch { }
Write-Host "=== Export Complete ==="
try { Stop-Transcript | Out-Null } catch { }
