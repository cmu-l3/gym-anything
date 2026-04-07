Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

$logPath = "C:\Users\Docker\task_grand_opening_export.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { }

try {
    Write-Host "=== Exporting grand_opening_day_operations result ==="

    $desktopDir     = "C:\Users\Docker\Desktop"
    $salesReport    = Join-Path $desktopDir "daily_sales_report.csv"
    $summaryFile    = Join-Path $desktopDir "opening_day_summary.txt"
    $startTsFile    = "C:\Users\Docker\task_start_ts_grand_opening.txt"
    $resultPath     = "C:\Users\Docker\grand_opening_result.json"

    # Read start timestamp
    $startTs = 0
    if (Test-Path $startTsFile) {
        try { $startTs = [int](Get-Content $startTsFile -Raw).Trim() } catch { }
    }

    # Helper to check file existence and timestamp
    function Get-FileInfo {
        param($Path)
        if (Test-Path $Path) {
            $fi = Get-Item $Path
            return @{
                exists    = $true
                timestamp = [int][DateTimeOffset]::new($fi.LastWriteTimeUtc).ToUnixTimeSeconds()
                size      = $fi.Length
            }
        }
        return @{ exists = $false; timestamp = 0; size = 0 }
    }

    $reportInfo  = Get-FileInfo $salesReport
    $summaryInfo = Get-FileInfo $summaryFile

    Write-Host "daily_sales_report.csv: exists=$($reportInfo.exists), size=$($reportInfo.size)"
    Write-Host "opening_day_summary.txt: exists=$($summaryInfo.exists), size=$($summaryInfo.size)"

    # Inline Python to parse the summary file and sales report
    $pythonScript = @'
import sys, json, re, os, csv

summary_file = sys.argv[1]
sales_file   = sys.argv[2]
result_path  = sys.argv[3]

summary_content = ""
has_store_name   = False
has_tax_rate     = False
has_item_count   = False
has_completed    = False
has_voided       = False
has_revenue      = False
revenue_found    = None
item_count_found = None

if os.path.exists(summary_file):
    try:
        with open(summary_file, 'r', encoding='utf-8-sig', errors='replace') as f:
            summary_content = f.read()
        cl = summary_content.lower()

        # Store name
        if 'riverside' in cl and 'electronics' in cl:
            has_store_name = True

        # Tax rate
        if '8.25' in summary_content:
            has_tax_rate = True

        # Item count
        item_matches = re.findall(r'(?:items?\s*(?:imported|in\s+inventory|count))\s*[:\s=]+(\d+)', cl)
        if item_matches:
            try:
                item_count_found = int(item_matches[0])
                has_item_count = (10 <= item_count_found <= 20)
            except:
                pass
        if not has_item_count and '15' in summary_content:
            # Looser check: just the number 15 near item-related context
            if re.search(r'(?:item|import|catalog|product).*15|15.*(?:item|import|catalog|product)', cl):
                has_item_count = True
                item_count_found = 15

        # Completed sales count
        completed_matches = re.findall(r'(?:completed|successful)\s*(?:sales?|transactions?)\s*[:\s=]+(\d+)', cl)
        if completed_matches:
            try:
                if int(completed_matches[0]) == 3:
                    has_completed = True
            except:
                pass
        if not has_completed:
            # Check for "3" near "completed" or "sales"
            if re.search(r'completed.*3|3.*completed', cl):
                has_completed = True

        # Voided sales count
        voided_matches = re.findall(r'(?:void|cancelled|canceled)\s*(?:sales?|transactions?)\s*[:\s=]+(\d+)', cl)
        if voided_matches:
            try:
                if int(voided_matches[0]) == 1:
                    has_voided = True
            except:
                pass
        if not has_voided:
            if re.search(r'void.*1|1.*void', cl):
                has_voided = True

        # Revenue
        revenue_matches = re.findall(r'\$?\s*(\d+\.\d{2})', summary_content)
        for rm in revenue_matches:
            try:
                v = float(rm)
                if abs(v - 452.95) < 5.0:
                    revenue_found = v
                    has_revenue = True
                    break
            except:
                pass
        if not has_revenue:
            if '452' in summary_content or '452.95' in summary_content:
                has_revenue = True
                revenue_found = 452.95

    except Exception as e:
        print(f"Summary parse error: {e}", file=sys.stderr)

# Parse sales report CSV
sales_row_count = 0
if os.path.exists(sales_file):
    try:
        with open(sales_file, 'r', encoding='utf-8-sig', errors='replace') as f:
            reader = csv.reader(f)
            sales_row_count = sum(1 for _ in reader)
    except Exception as e:
        print(f"Sales report parse error: {e}", file=sys.stderr)

result = {
    "summary_content":  summary_content[:2000],
    "has_store_name":   has_store_name,
    "has_tax_rate":     has_tax_rate,
    "has_item_count":   has_item_count,
    "item_count_found": item_count_found,
    "has_completed":    has_completed,
    "has_voided":       has_voided,
    "has_revenue":      has_revenue,
    "revenue_found":    revenue_found,
    "sales_row_count":  sales_row_count,
}

with open(result_path, 'w', encoding='utf-8') as f:
    json.dump(result, f, indent=2)
print(f"store_name={has_store_name}, tax={has_tax_rate}, items={item_count_found}")
print(f"completed={has_completed}, voided={has_voided}, revenue={revenue_found}")
print(f"sales_rows={sales_row_count}")
'@

    $pyScript = "C:\Windows\Temp\parse_grand_opening.py"
    [System.IO.File]::WriteAllText($pyScript, $pythonScript)

    $parseResult = @{
        summary_content  = ""
        has_store_name   = $false
        has_tax_rate     = $false
        has_item_count   = $false
        item_count_found = $null
        has_completed    = $false
        has_voided       = $false
        has_revenue      = $false
        revenue_found    = $null
        sales_row_count  = 0
    }

    # Run Python parser if any output file exists
    if ($summaryInfo.exists -or $reportInfo.exists) {
        $summaryArg = if ($summaryInfo.exists) { $summaryFile } else { "nonexistent" }
        $salesArg   = if ($reportInfo.exists)  { $salesReport } else { "nonexistent" }
        try {
            $pyOut = & python $pyScript $summaryArg $salesArg $resultPath 2>&1
            Write-Host "Python output: $pyOut"
            if (Test-Path $resultPath) {
                $parsed = Get-Content $resultPath -Raw -Encoding UTF8 | ConvertFrom-Json
                $parseResult = $parsed
            }
        } catch {
            Write-Host "Python parsing failed: $($_.Exception.Message)"
        }
    }

    $reportNew  = ($reportInfo.timestamp -gt $startTs) -and ($reportInfo.timestamp -gt 0)
    $summaryNew = ($summaryInfo.timestamp -gt $startTs) -and ($summaryInfo.timestamp -gt 0)

    # Check if Copper is still running
    $appRunning = (Get-Process copper -ErrorAction SilentlyContinue) -ne $null

    # Check if Copper data was modified during task
    $dataModified = $false
    $dataDirs = @(
        "C:\ProgramData\NCH Software\Copper\Shared",
        "C:\Users\Docker\AppData\Roaming\NCH Software\Copper",
        "C:\Users\Docker\Documents\CopperData"
    )
    try {
        foreach ($dir in $dataDirs) {
            if (Test-Path $dir) {
                $recentFiles = @(Get-ChildItem $dir -Recurse -File -ErrorAction SilentlyContinue | Where-Object {
                    [int][DateTimeOffset]::new($_.LastWriteTimeUtc).ToUnixTimeSeconds() -ge $startTs
                })
                if ($recentFiles.Count -gt 0) {
                    $dataModified = $true
                    break
                }
            }
        }
    } catch {
        Write-Host "Data modification check failed: $($_.Exception.Message)"
    }

    # Check registry for tax configuration
    $taxConfigured = $false
    try {
        $regPaths = @(
            "HKCU:\Software\NCH Software\Copper",
            "HKCU:\Software\NCH Software\Copper\Settings"
        )
        foreach ($regPath in $regPaths) {
            if (Test-Path $regPath) {
                $regProps = Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue
                if ($null -ne $regProps) {
                    $allValues = @($regProps.PSObject.Properties | ForEach-Object { $_.Value })
                    $taxFound = @($allValues | Where-Object { $_ -is [string] -and $_ -match "8\.25" })
                    if ($taxFound.Count -gt 0) { $taxConfigured = $true; break }
                }
            }
        }
    } catch {
        Write-Host "Registry check failed: $($_.Exception.Message)"
    }

    $finalJson = @{
        task                    = "grand_opening_day_operations"
        start_timestamp         = $startTs
        sales_report_exists     = $reportInfo.exists
        sales_report_new        = $reportNew
        sales_report_size       = $reportInfo.size
        summary_exists          = $summaryInfo.exists
        summary_new             = $summaryNew
        summary_size            = $summaryInfo.size
        app_running             = $appRunning
        data_modified           = $dataModified
        tax_configured          = $taxConfigured
        has_store_name          = $parseResult.has_store_name
        has_tax_rate            = $parseResult.has_tax_rate
        has_item_count          = $parseResult.has_item_count
        item_count_found        = $parseResult.item_count_found
        has_completed           = $parseResult.has_completed
        has_voided              = $parseResult.has_voided
        has_revenue             = $parseResult.has_revenue
        revenue_found           = $parseResult.revenue_found
        sales_row_count         = $parseResult.sales_row_count
    }

    $finalJson | ConvertTo-Json -Depth 5 | Out-File -FilePath $resultPath -Encoding UTF8 -Force

    Write-Host "report=$($reportInfo.exists)(new=$reportNew), summary=$($summaryInfo.exists)(new=$summaryNew)"
    Write-Host "app_running=$appRunning, data_modified=$dataModified, tax=$taxConfigured"
    Write-Host "=== Export Complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
