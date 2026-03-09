# Post-task export script for cross_case_event_timeline_database.
# Collects three CSV exports and the event timeline database document.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_post_task_event_timeline.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { Write-Host "WARNING: Start-Transcript failed" }

try {
    Write-Host "=== Exporting cross_case_event_timeline_database results ==="

    $desktop  = "C:\Users\Docker\Desktop"
    $resultPath = "C:\Users\Docker\task_result_event_timeline.json"

    $result = @{
        csv_0001_exists     = $false
        csv_0001_size_bytes = 0
        csv_0001_header     = ""
        csv_0001_line_count = 0
        csv_0002_exists     = $false
        csv_0002_size_bytes = 0
        csv_0002_header     = ""
        csv_0002_line_count = 0
        csv_0003_exists     = $false
        csv_0003_size_bytes = 0
        csv_0003_header     = ""
        csv_0003_line_count = 0
        db_exists           = $false
        db_size_bytes       = 0
        db_content          = ""
        errors              = @()
    }

    # Helper to collect CSV info
    function Collect-CsvInfo([string]$Path, [hashtable]$Out, [string]$Prefix) {
        if (Test-Path $Path) {
            try {
                $info = Get-Item $Path
                $Out["${Prefix}_exists"]     = $true
                $Out["${Prefix}_size_bytes"] = $info.Length
                $lines = Get-Content $Path -TotalCount 2
                if ($lines -and $lines.Count -gt 0) { $Out["${Prefix}_header"] = $lines[0] }
                $lc = 0
                $rdr = [System.IO.StreamReader]::new($Path)
                try { while ($null -ne $rdr.ReadLine()) { $lc++ } } finally { $rdr.Close() }
                $Out["${Prefix}_line_count"] = $lc
                Write-Host "${Prefix}: $($info.Length) bytes, $lc lines"
            } catch {
                $Out["errors"] += "${Prefix} error: $($_.Exception.Message)"
            }
        } else {
            Write-Host "WARNING: Not found: $Path"
            $Out["errors"] += "${Prefix} not found: $Path"
        }
    }

    Collect-CsvInfo "$desktop\case_0001_events.csv" $result "csv_0001"
    Collect-CsvInfo "$desktop\case_0002_events.csv" $result "csv_0002"
    Collect-CsvInfo "$desktop\case_0003_events.csv" $result "csv_0003"

    # Database document
    $dbPath = "$desktop\event_timeline_db.txt"
    if (Test-Path $dbPath) {
        try {
            $info = Get-Item $dbPath
            $result.db_exists     = $true
            $result.db_size_bytes = $info.Length
            $raw = Get-Content $dbPath -Raw -ErrorAction SilentlyContinue
            if ($raw) {
                $result.db_content = if ($raw.Length -gt 15000) { $raw.Substring(0, 15000) } else { $raw }
            }
            Write-Host "Database: $($info.Length) bytes"
        } catch {
            $result.errors += "DB error: $($_.Exception.Message)"
        }
    } else {
        $result.errors += "Database not found: $dbPath"
        Write-Host "WARNING: Database not found"
    }

    $result | ConvertTo-Json -Depth 4 | Out-File $resultPath -Encoding UTF8 -Force
    Write-Host "Result JSON: $resultPath"

    Write-Host "=== cross_case_event_timeline_database export complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
