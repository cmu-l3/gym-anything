# Post-task export script for mandm_conference_case_review task.
# Checks all output files (3 screenshots, 1 CSV, 1 report) and writes
# a structured result JSON for the verifier.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_post_task_mandm.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { Write-Host "WARNING: Start-Transcript failed" }

try {
    Write-Host "=== Exporting mandm_conference_case_review results ==="

    $outputDir   = "C:\Users\Docker\Desktop\MandM"
    $resultPath  = "C:\tmp\task_result_mandm.json"
    $baselinePath = "C:\tmp\task_baseline_mandm.json"

    # ---- Read baseline timestamp ----
    $taskStartUnix = 0
    if (Test-Path $baselinePath) {
        try {
            $baseline = Get-Content $baselinePath -Raw | ConvertFrom-Json
            $taskStartUnix = [long]$baseline.task_start_unix
        } catch {
            Write-Host "WARNING: Could not parse baseline JSON: $($_.Exception.Message)"
        }
    }
    Write-Host "Task start unix: $taskStartUnix"

    $result = @{
        task_start_unix  = $taskStartUnix
        export_timestamp = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        errors           = @()
    }

    # ---- Helper: collect image file info ----
    function Collect-ImageInfo {
        param([string]$Path, [string]$Label)
        $info = @{
            exists              = $false
            size_bytes          = 0
            created_after_start = $false
        }
        if (Test-Path $Path) {
            try {
                $fi = Get-Item $Path
                $info.exists     = $true
                $info.size_bytes = $fi.Length
                $writeUnix = [DateTimeOffset]::new($fi.LastWriteTimeUtc).ToUnixTimeSeconds()
                if ($taskStartUnix -gt 0 -and $writeUnix -ge $taskStartUnix) {
                    $info.created_after_start = $true
                }
                Write-Host "${Label}: $($fi.Length) bytes"
            } catch {
                $result.errors += "${Label} read error: $($_.Exception.Message)"
            }
        } else {
            Write-Host "WARNING: Not found: $Path"
            $result.errors += "${Label} not found: $Path"
        }
        return $info
    }

    # ---- Collect screenshot info ----
    $result["full_timeline"]    = Collect-ImageInfo -Path "$outputDir\full_timeline.png"    -Label "full_timeline"
    $result["induction_detail"] = Collect-ImageInfo -Path "$outputDir\induction_detail.png" -Label "induction_detail"
    $result["emergence_detail"] = Collect-ImageInfo -Path "$outputDir\emergence_detail.png" -Label "emergence_detail"

    # ---- Collect CSV info ----
    $csvPath = "$outputDir\intraop_data.csv"
    $csvInfo = @{
        exists              = $false
        size_bytes          = 0
        header              = ""
        line_count          = 0
        data_line_count     = 0
        column_names        = @()
        column_count        = 0
        created_after_start = $false
    }
    if (Test-Path $csvPath) {
        try {
            $fi = Get-Item $csvPath
            $csvInfo.exists     = $true
            $csvInfo.size_bytes = $fi.Length
            $writeUnix = [DateTimeOffset]::new($fi.LastWriteTimeUtc).ToUnixTimeSeconds()
            if ($taskStartUnix -gt 0 -and $writeUnix -ge $taskStartUnix) {
                $csvInfo.created_after_start = $true
            }

            # Read header and count lines
            $reader = [System.IO.StreamReader]::new($csvPath)
            $csvInfo.header = $reader.ReadLine()
            if ($csvInfo.header) {
                $csvInfo.column_names = @($csvInfo.header.Split(',') | ForEach-Object { $_.Trim().Trim('"') })
                $csvInfo.column_count = $csvInfo.column_names.Count
            }
            $lc = 1  # already read header
            while ($null -ne $reader.ReadLine()) { $lc++ }
            $csvInfo.line_count      = $lc
            $csvInfo.data_line_count = [Math]::Max(0, $lc - 1)
            $reader.Close()
            $reader.Dispose()

            Write-Host "CSV: $($fi.Length) bytes, $lc lines, $($csvInfo.column_count) columns"
        } catch {
            $result.errors += "CSV read error: $($_.Exception.Message)"
        }
    } else {
        Write-Host "WARNING: CSV not found: $csvPath"
        $result.errors += "CSV not found: $csvPath"
    }
    $result["intraop_csv"] = $csvInfo

    # ---- Collect report info ----
    $reportPath = "$outputDir\case_report.txt"
    $reportInfo = @{
        exists              = $false
        size_bytes          = 0
        content             = ""
        created_after_start = $false
    }
    if (Test-Path $reportPath) {
        try {
            $fi = Get-Item $reportPath
            $reportInfo.exists     = $true
            $reportInfo.size_bytes = $fi.Length
            $writeUnix = [DateTimeOffset]::new($fi.LastWriteTimeUtc).ToUnixTimeSeconds()
            if ($taskStartUnix -gt 0 -and $writeUnix -ge $taskStartUnix) {
                $reportInfo.created_after_start = $true
            }
            $raw = Get-Content $reportPath -Raw -ErrorAction SilentlyContinue
            if ($raw) {
                $reportInfo.content = if ($raw.Length -gt 15000) { $raw.Substring(0, 15000) } else { $raw }
            }
            Write-Host "Report: $($fi.Length) bytes"
        } catch {
            $result.errors += "Report read error: $($_.Exception.Message)"
        }
    } else {
        Write-Host "WARNING: Report not found: $reportPath"
        $result.errors += "Report not found: $reportPath"
    }
    $result["case_report"] = $reportInfo

    # ---- Write result JSON ----
    $result | ConvertTo-Json -Depth 5 | Out-File $resultPath -Encoding UTF8 -Force
    Write-Host "Result JSON written to: $resultPath"

    Write-Host "=== mandm_conference_case_review export complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
