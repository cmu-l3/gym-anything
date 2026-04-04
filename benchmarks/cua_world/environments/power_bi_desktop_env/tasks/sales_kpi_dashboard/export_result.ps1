# Export script for sales_kpi_dashboard task.
# Runs after the agent finishes. Inspects the saved .pbix file and produces a result JSON.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

$logPath = "C:\Users\Docker\task_post_task_sales_kpi_dashboard.log"
try {
    Start-Transcript -Path $logPath -Force | Out-Null
} catch {
    Write-Host "WARNING: Start-Transcript failed: $($_.Exception.Message)"
}

Write-Host "=== Exporting sales_kpi_dashboard result ==="

# Helper to write final result JSON
function Write-Result {
    param($data)
    $data | ConvertTo-Json -Depth 5 | Set-Content -Path "C:\Users\Docker\Desktop\sales_kpi_result.json" -Encoding UTF8
    Write-Host "Result JSON written."
}

$targetPbix = "C:\Users\Docker\Desktop\Sales_KPI_Dashboard.pbix"
$extractPath = "C:\Users\Docker\Desktop\pbix_extracted_skd"

# Read baseline and start timestamp
$startTimestamp = 0
try {
    $startTimestamp = [int](Get-Content "C:\Users\Docker\task_start_timestamp_sales_kpi.txt" -ErrorAction SilentlyContinue)
} catch { }

# Give Power BI a moment to flush any pending save
Start-Sleep -Seconds 3

# Force-close Power BI to ensure file is fully written
Get-Process PBIDesktop -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Get-Process msmdsrv -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

# Check if target file exists
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
        start_timestamp = $startTimestamp
        export_timestamp = [int][double]::Parse((Get-Date -UFormat %s))
    }
    try { Stop-Transcript | Out-Null } catch { }
    exit 0
}

$fileInfo = Get-Item $targetPbix
$fileSizeBytes = $fileInfo.Length
$fileModTime = [int][double]::Parse((Get-Date $fileInfo.LastWriteTime -UFormat %s))
Write-Host "Found target file: $targetPbix ($fileSizeBytes bytes, modified $fileModTime)"

# Clean up any prior extraction
if (Test-Path $extractPath) {
    Remove-Item $extractPath -Recurse -Force -ErrorAction SilentlyContinue
}
New-Item -ItemType Directory -Force -Path $extractPath | Out-Null

# Unzip .pbix as a ZIP archive
$zipPath = "$extractPath\report.zip"
Copy-Item $targetPbix $zipPath
try {
    Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force -ErrorAction Stop
    Write-Host "Successfully expanded .pbix archive"
} catch {
    Write-Host "WARNING: Failed to expand .pbix: $($_.Exception.Message)"
    Write-Result @{
        file_exists = $true
        file_size_bytes = $fileSizeBytes
        file_mod_time = $fileModTime
        page_count = 0
        page_names = @()
        visual_types = @()
        layout_text = ""
        model_text_sample = ""
        start_timestamp = $startTimestamp
        export_timestamp = [int][double]::Parse((Get-Date -UFormat %s))
        error = "Failed to expand archive: $($_.Exception.Message)"
    }
    try { Stop-Transcript | Out-Null } catch { }
    exit 0
}

# Parse Report/Layout JSON
$layoutFile = "$extractPath\Report\Layout"
$pageCount = 0
$pageNames = @()
$visualTypes = @()
$layoutTextSnippet = ""

if (Test-Path $layoutFile) {
    try {
        # Power BI Layout is typically UTF-16 LE encoded
        $layoutBytes = [System.IO.File]::ReadAllBytes($layoutFile)
        $layoutText = [System.Text.Encoding]::Unicode.GetString($layoutBytes)
        if ($layoutText.Length -lt 100) {
            # Fallback: try UTF-8
            $layoutText = [System.Text.Encoding]::UTF8.GetString($layoutBytes)
        }
        $layoutTextSnippet = if ($layoutText.Length -gt 2000) { $layoutText.Substring(0, 2000) } else { $layoutText }

        $layout = $layoutText | ConvertFrom-Json

        # Extract pages (sections)
        if ($layout.sections) {
            $pageCount = $layout.sections.Count
            $pageNames = @($layout.sections | ForEach-Object { $_.displayName })
            Write-Host "Pages found ($pageCount): $($pageNames -join ', ')"

            # Extract visual types from all pages
            foreach ($section in $layout.sections) {
                if ($section.visualContainers) {
                    foreach ($vc in $section.visualContainers) {
                        try {
                            $vcConfig = $vc.config | ConvertFrom-Json
                            $vtype = $vcConfig.singleVisual.visualType
                            if ($vtype) {
                                $visualTypes += $vtype
                            }
                        } catch { }
                    }
                }
            }
            Write-Host "Visual types found: $($visualTypes -join ', ')"
        }
    } catch {
        Write-Host "WARNING: Failed to parse Report/Layout: $($_.Exception.Message)"
    }
} else {
    Write-Host "WARNING: Report/Layout file not found at $layoutFile"
}

# Search DataModel binary for measure name strings
$modelTextSample = ""
$modelFile = "$extractPath\DataModel"
if (Test-Path $modelFile) {
    try {
        $modelBytes = [System.IO.File]::ReadAllBytes($modelFile)
        # Try UTF-16-LE first (common for Power BI model strings)
        $modelTextUnicode = [System.Text.Encoding]::Unicode.GetString($modelBytes)
        # Also try UTF-8
        $modelTextUtf8 = [System.Text.Encoding]::UTF8.GetString($modelBytes)
        # Combine both to maximize detection
        $modelTextSample = ($modelTextUnicode + " " + $modelTextUtf8)
        if ($modelTextSample.Length -gt 5000) {
            $modelTextSample = $modelTextSample.Substring(0, 5000)
        }
        Write-Host "DataModel binary read: $($modelBytes.Length) bytes"
    } catch {
        Write-Host "WARNING: Failed to read DataModel: $($_.Exception.Message)"
    }
}

# Also search the full layout text for measure names (measures used in visuals appear in layout)
$fullLayoutForSearch = ""
if (Test-Path $layoutFile) {
    try {
        $fullLayoutBytes = [System.IO.File]::ReadAllBytes($layoutFile)
        $fullLayoutForSearch = [System.Text.Encoding]::Unicode.GetString($fullLayoutBytes)
    } catch { }
}

Write-Result @{
    file_exists = $true
    file_size_bytes = $fileSizeBytes
    file_mod_time = $fileModTime
    page_count = $pageCount
    page_names = $pageNames
    visual_types = ($visualTypes | Sort-Object -Unique)
    layout_text = $layoutTextSnippet
    model_text_sample = $modelTextSample
    full_layout_search = $fullLayoutForSearch
    start_timestamp = $startTimestamp
    export_timestamp = [int][double]::Parse((Get-Date -UFormat %s))
}

# Cleanup temp extraction
try {
    Remove-Item $extractPath -Recurse -Force -ErrorAction SilentlyContinue
} catch { }

Write-Host "=== Export Complete ==="
try { Stop-Transcript | Out-Null } catch { }
