Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

$logPath = "C:\Users\Docker\task_multi_report_export.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { }

try {
    Write-Host "=== Exporting multi_report_sales_analytics result ==="

    $desktopDir     = "C:\Users\Docker\Desktop"
    $weeklySales    = Join-Path $desktopDir "weekly_sales.csv"
    $stockLevels    = Join-Path $desktopDir "stock_levels.csv"
    $analyticsSummary = Join-Path $desktopDir "analytics_summary.txt"
    $startTsFile    = "C:\Users\Docker\task_start_ts_multi_report.txt"
    $resultPath     = "C:\Users\Docker\multi_report_result.json"

    # Read start timestamp
    $startTs = 0
    if (Test-Path $startTsFile) {
        try { $startTs = [int](Get-Content $startTsFile -Raw).Trim() } catch { }
    }

    # Check each output file
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

    $wsInfo  = Get-FileInfo $weeklySales
    $slInfo  = Get-FileInfo $stockLevels
    $asInfo  = Get-FileInfo $analyticsSummary

    Write-Host "weekly_sales.csv: exists=$($wsInfo.exists), size=$($wsInfo.size)"
    Write-Host "stock_levels.csv: exists=$($slInfo.exists), size=$($slInfo.size)"
    Write-Host "analytics_summary.txt: exists=$($asInfo.exists), size=$($asInfo.size)"

    # Python to parse analytics_summary.txt and the report files
    $pythonScript = @'
import sys, json, re, os, csv, io

summary_file   = sys.argv[1]
sales_file     = sys.argv[2]
stock_file     = sys.argv[3]
result_path    = sys.argv[4]

# Expected values
EXPECTED_TOTAL_REVENUE  = 321.96
EXPECTED_ITEM_COUNT     = 15
EXPECTED_TRANSACTIONS   = 3

# Parse analytics_summary.txt
summary_content = ""
has_item_count       = False
has_transactions     = False
has_total_revenue    = False
has_electronics_cat  = False
revenue_found        = None
item_count_found     = None

if os.path.exists(summary_file):
    try:
        with open(summary_file, 'r', encoding='utf-8-sig', errors='replace') as f:
            summary_content = f.read()
        cl = summary_content.lower()

        # Check for item count mention (should be 15 or close)
        item_matches = re.findall(r'(?:total\s+items?|items?\s+in\s+inventory)\s*[:\s=]+(\d+)', cl)
        if item_matches:
            try:
                item_count_found = int(item_matches[0])
                has_item_count = (10 <= item_count_found <= 20)  # flexible range
            except:
                pass

        # Check for transaction count
        txn_matches = re.findall(r'(?:transactions?|processed)\s*(?:today|today)?\s*[:\s=]+(\d+)', cl)
        if txn_matches or '3' in cl:
            has_transactions = True

        # Check for revenue values
        revenue_matches = re.findall(r'(?:total|revenue|today)\s*[:\s=]+\$?\s*(\d+\.\d{2})', cl)
        for rm in revenue_matches:
            try:
                v = float(rm)
                if abs(v - EXPECTED_TOTAL_REVENUE) < 5.0:
                    revenue_found = v
                    has_total_revenue = True
                    break
            except:
                pass

        # Also look for the specific dollar amounts
        if not has_total_revenue:
            if '321' in summary_content or '321.96' in summary_content:
                has_total_revenue = True
                revenue_found = 321.96

        # Check for electronics category mention
        if 'electronics' in cl:
            has_electronics_cat = True

    except Exception as e:
        print(f"Summary parse error: {e}", file=sys.stderr)

# Parse weekly_sales.csv to check it has data
sales_row_count = 0
if os.path.exists(sales_file):
    try:
        with open(sales_file, 'r', encoding='utf-8-sig', errors='replace') as f:
            reader = csv.reader(f)
            sales_row_count = sum(1 for _ in reader)
    except Exception as e:
        print(f"Sales parse error: {e}", file=sys.stderr)

# Parse stock_levels.csv to check it has data
stock_row_count = 0
if os.path.exists(stock_file):
    try:
        with open(stock_file, 'r', encoding='utf-8-sig', errors='replace') as f:
            reader = csv.reader(f)
            stock_row_count = sum(1 for _ in reader)
    except Exception as e:
        print(f"Stock parse error: {e}", file=sys.stderr)

result = {
    "summary_file_size":   os.path.getsize(summary_file) if os.path.exists(summary_file) else 0,
    "has_item_count":      has_item_count,
    "item_count_found":    item_count_found,
    "has_transactions":    has_transactions,
    "has_total_revenue":   has_total_revenue,
    "revenue_found":       revenue_found,
    "has_electronics_cat": has_electronics_cat,
    "sales_row_count":     sales_row_count,
    "stock_row_count":     stock_row_count,
}

with open(result_path, 'w', encoding='utf-8') as f:
    json.dump(result, f, indent=2)
print(f"item_count={item_count_found}, revenue={revenue_found}, electronics={has_electronics_cat}")
print(f"sales_rows={sales_row_count}, stock_rows={stock_row_count}")
'@

    $pyScript = "C:\Windows\Temp\parse_analytics.py"
    [System.IO.File]::WriteAllText($pyScript, $pythonScript)

    $parseResult = @{
        summary_file_size  = 0
        has_item_count     = $false
        item_count_found   = $null
        has_transactions   = $false
        has_total_revenue  = $false
        revenue_found      = $null
        has_electronics_cat = $false
        sales_row_count    = 0
        stock_row_count    = 0
    }

    # Only run python if at least one output file exists
    if ($asInfo.exists -or $wsInfo.exists -or $slInfo.exists) {
        $summaryArg = if ($asInfo.exists) { $analyticsSummary } else { "nonexistent" }
        $salesArg   = if ($wsInfo.exists) { $weeklySales } else { "nonexistent" }
        $stockArg   = if ($slInfo.exists) { $stockLevels } else { "nonexistent" }
        try {
            $pyOut = & python $pyScript $summaryArg $salesArg $stockArg $resultPath 2>&1
            Write-Host "Python output: $pyOut"
            if (Test-Path $resultPath) {
                $parsed = Get-Content $resultPath -Raw -Encoding UTF8 | ConvertFrom-Json
                $parseResult = $parsed
            }
        } catch {
            Write-Host "Python parsing failed: $($_.Exception.Message)"
        }
    }

    $wsNew = ($wsInfo.timestamp -gt $startTs) -and ($wsInfo.timestamp -gt 0)
    $slNew = ($slInfo.timestamp -gt $startTs) -and ($slInfo.timestamp -gt 0)
    $asNew = ($asInfo.timestamp -gt $startTs) -and ($asInfo.timestamp -gt 0)

    $finalJson = @{
        task                 = "multi_report_sales_analytics"
        start_timestamp      = $startTs
        weekly_sales_exists  = $wsInfo.exists
        weekly_sales_new     = $wsNew
        stock_levels_exists  = $slInfo.exists
        stock_levels_new     = $slNew
        analytics_summary_exists = $asInfo.exists
        analytics_summary_new    = $asNew
        summary_file_size    = $parseResult.summary_file_size
        has_item_count       = $parseResult.has_item_count
        item_count_found     = $parseResult.item_count_found
        has_transactions     = $parseResult.has_transactions
        has_total_revenue    = $parseResult.has_total_revenue
        revenue_found        = $parseResult.revenue_found
        has_electronics_cat  = $parseResult.has_electronics_cat
        sales_row_count      = $parseResult.sales_row_count
        stock_row_count      = $parseResult.stock_row_count
    }

    $finalJson | ConvertTo-Json -Depth 5 | Out-File -FilePath $resultPath -Encoding UTF8 -Force

    Write-Host "weekly_sales=$($wsInfo.exists)(new=$wsNew), stock=$($slInfo.exists)(new=$slNew), summary=$($asInfo.exists)(new=$asNew)"
    Write-Host "=== Export Complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
