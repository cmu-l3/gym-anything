Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

$logPath = "C:\Users\Docker\task_shift_end_export.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { }

try {
    Write-Host "=== Exporting shift_end_reconciliation result ==="

    $desktopDir   = "C:\Users\Docker\Desktop"
    $reportFile   = Join-Path $desktopDir "shift_report.csv"
    $startTsFile  = "C:\Users\Docker\task_start_ts_shift_end.txt"
    $resultPath   = "C:\Users\Docker\shift_end_result.json"

    # Read task start timestamp
    $startTs = 0
    if (Test-Path $startTsFile) {
        try { $startTs = [int](Get-Content $startTsFile -Raw).Trim() } catch { }
    }

    # Check exported report file
    $reportExists = $false
    $reportTs     = 0
    $reportContent = ""

    if (Test-Path $reportFile) {
        $reportExists  = $true
        $fi            = Get-Item $reportFile
        $reportTs      = [int][DateTimeOffset]::new($fi.LastWriteTimeUtc).ToUnixTimeSeconds()
        $reportContent = Get-Content $reportFile -Raw -ErrorAction SilentlyContinue
        Write-Host "Report file found, size=$($fi.Length) bytes."
    } else {
        Write-Host "shift_report.csv not found on Desktop."
    }

    # Use Python to parse the report CSV and extract transaction data
    $pythonScript = @'
import sys, csv, json, io, os, re

report_file = sys.argv[1]
result_path = sys.argv[2]

rows            = []
total_found     = None
transaction_count = 0
has_discount_line = False
has_void_line     = False
numeric_amounts   = []

if os.path.exists(report_file):
    try:
        with open(report_file, 'r', encoding='utf-8-sig', errors='replace') as f:
            raw = f.read()

        # Try CSV parse first
        try:
            reader = csv.DictReader(io.StringIO(raw))
            for row in reader:
                rows.append(dict(row))
                transaction_count += 1
                # Look for total/amount column
                for k, v in row.items():
                    kl = k.lower()
                    if any(x in kl for x in ['total', 'amount', 'sale', 'subtotal']):
                        vs = str(v).replace('$','').replace(',','').strip()
                        try:
                            amt = float(vs)
                            if amt > 0:
                                numeric_amounts.append(amt)
                        except:
                            pass
                # Look for discount indicators
                for k, v in row.items():
                    combined = (str(k) + ' ' + str(v)).lower()
                    if 'discount' in combined or 'discnt' in combined:
                        has_discount_line = True
                    if 'void' in combined or 'cancel' in combined or 'refund' in combined:
                        has_void_line = True
        except Exception as e:
            print(f"CSV parse warning: {e}", file=sys.stderr)

        # Also do a raw text scan for totals and keywords
        raw_lower = raw.lower()
        if 'void' in raw_lower or 'cancel' in raw_lower or 'refund' in raw_lower:
            has_void_line = True
        if 'discount' in raw_lower or '15%' in raw_lower or '0.15' in raw_lower:
            has_discount_line = True

        # Extract all currency-like numbers from raw content
        all_amounts = re.findall(r'\$?\s*(\d+\.\d{2})', raw)
        all_float_amounts = []
        for a in all_amounts:
            try:
                v = float(a)
                if 1.0 < v < 10000.0:
                    all_float_amounts.append(v)
            except:
                pass

        # Estimate total from max or sum-like value
        if all_float_amounts:
            total_found = max(all_float_amounts)

    except Exception as e:
        print(f"Parse error: {e}", file=sys.stderr)

result = {
    "row_count":           len(rows),
    "transaction_count":   transaction_count,
    "has_discount_line":   has_discount_line,
    "has_void_line":       has_void_line,
    "total_found":         total_found,
    "numeric_amounts":     numeric_amounts[:20],
}

with open(result_path, 'w', encoding='utf-8') as f:
    json.dump(result, f, indent=2)
print(f"Rows: {transaction_count}, discount={has_discount_line}, void={has_void_line}, max_amount={total_found}")
'@

    $pyScript = "C:\Windows\Temp\parse_shift_report.py"
    [System.IO.File]::WriteAllText($pyScript, $pythonScript)

    $parseResult = @{
        row_count          = 0
        transaction_count  = 0
        has_discount_line  = $false
        has_void_line      = $false
        total_found        = $null
        numeric_amounts    = @()
    }

    if ($reportExists) {
        try {
            $pyOut = & python $pyScript $reportFile $resultPath 2>&1
            Write-Host "Python output: $pyOut"
            if (Test-Path $resultPath) {
                $parsed = Get-Content $resultPath -Raw -Encoding UTF8 | ConvertFrom-Json
                $parseResult = $parsed
            }
        } catch {
            Write-Host "Python parsing failed: $($_.Exception.Message)"
        }
    }

    $fileIsNew = ($reportTs -gt $startTs) -and ($reportTs -gt 0)

    $finalJson = @{
        task               = "shift_end_reconciliation"
        report_file_exists = $reportExists
        report_file_new    = $fileIsNew
        report_timestamp   = $reportTs
        start_timestamp    = $startTs
        row_count          = $parseResult.row_count
        transaction_count  = $parseResult.transaction_count
        has_discount_line  = $parseResult.has_discount_line
        has_void_line      = $parseResult.has_void_line
        total_found        = $parseResult.total_found
        numeric_amounts    = $parseResult.numeric_amounts
    }

    $finalJson | ConvertTo-Json -Depth 5 | Out-File -FilePath $resultPath -Encoding UTF8 -Force

    Write-Host "report_exists=$reportExists, file_new=$fileIsNew"
    Write-Host "=== Export Complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
