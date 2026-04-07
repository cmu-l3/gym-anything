Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

$logPath = "C:\Users\Docker\task_quarterly_reconciliation_export.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { }

try {
    Write-Host "=== Exporting quarterly_inventory_reconciliation result ==="

    $desktopDir    = "C:\Users\Docker\Desktop"
    $inventoryFile = Join-Path $desktopDir "final_inventory.csv"
    $reportFile    = Join-Path $desktopDir "quarterly_close.txt"
    $startTsFile   = "C:\Users\Docker\task_start_ts_quarterly_reconciliation.txt"
    $resultPath    = "C:\Users\Docker\quarterly_reconciliation_result.json"

    # Read task start timestamp
    $startTs = 0
    if (Test-Path $startTsFile) {
        try { $startTs = [int](Get-Content $startTsFile -Raw).Trim() } catch { }
    }

    # Check exported inventory CSV
    $inventoryExists = $false
    $inventoryTs     = 0
    $inventoryContent = ""
    if (Test-Path $inventoryFile) {
        $inventoryExists = $true
        $fi = Get-Item $inventoryFile
        $inventoryTs = [int][DateTimeOffset]::new($fi.LastWriteTimeUtc).ToUnixTimeSeconds()
        $inventoryContent = Get-Content $inventoryFile -Raw -ErrorAction SilentlyContinue
        Write-Host "Inventory file found, size=$($fi.Length) bytes."
    } else {
        Write-Host "final_inventory.csv not found on Desktop."
    }

    # Check quarterly close report
    $reportExists = $false
    $reportTs     = 0
    $reportContent = ""
    if (Test-Path $reportFile) {
        $reportExists = $true
        $fi = Get-Item $reportFile
        $reportTs = [int][DateTimeOffset]::new($fi.LastWriteTimeUtc).ToUnixTimeSeconds()
        $reportContent = Get-Content $reportFile -Raw -ErrorAction SilentlyContinue
        Write-Host "Report file found, size=$($fi.Length) bytes."
    } else {
        Write-Host "quarterly_close.txt not found on Desktop."
    }

    # Use Python to parse the inventory CSV and report file
    $pythonScript = @'
import sys, csv, json, io, os, re

inventory_file = sys.argv[1]
report_file    = sys.argv[2]
result_path    = sys.argv[3]

result = {
    "inventory_row_count": 0,
    "inventory_items": {},
    "report_content": "",
    "report_has_shrinkage_table": False,
    "report_total_adjusted": None,
    "report_shrinkage_units": None,
    "report_refund_amount": None,
    "report_clearance_total": None,
}

# Parse inventory CSV
if os.path.exists(inventory_file):
    try:
        with open(inventory_file, 'r', encoding='utf-8-sig', errors='replace') as f:
            raw = f.read()
        reader = csv.DictReader(io.StringIO(raw))
        for row in reader:
            result["inventory_row_count"] += 1
            # Find SKU and quantity columns
            sku = None
            qty = None
            name = None
            for k, v in row.items():
                kl = k.lower().strip()
                if 'sku' in kl or 'code' in kl or 'item code' in kl:
                    sku = str(v).strip()
                if 'qty' in kl or 'quantity' in kl or 'stock' in kl or 'count' in kl:
                    try:
                        qty = int(float(str(v).strip()))
                    except:
                        pass
                if 'name' in kl or 'item' in kl or 'description' in kl or 'product' in kl:
                    if name is None:
                        name = str(v).strip()
            if sku:
                result["inventory_items"][sku] = {"qty": qty, "name": name}
            elif name:
                result["inventory_items"][name] = {"qty": qty, "name": name}
    except Exception as e:
        print(f"Inventory parse error: {e}", file=sys.stderr)

# Parse report file
if os.path.exists(report_file):
    try:
        with open(report_file, 'r', encoding='utf-8-sig', errors='replace') as f:
            report_raw = f.read()
        result["report_content"] = report_raw[:5000]

        # Check for shrinkage table (pipe-delimited lines)
        if '|' in report_raw:
            result["report_has_shrinkage_table"] = True

        # Extract "Total items adjusted: N"
        m = re.search(r'[Tt]otal\s+items?\s+adjusted[:\s]*(\d+)', report_raw)
        if m:
            result["report_total_adjusted"] = int(m.group(1))

        # Extract "Total units of shrinkage: N" or similar
        m = re.search(r'[Tt]otal\s+(?:units?\s+(?:of\s+)?)?shrinkage[:\s]*(\d+)', report_raw)
        if m:
            result["report_shrinkage_units"] = int(m.group(1))

        # Extract refund amount (dollar value near "refund")
        m = re.search(r'[Rr]efund[^$\d]*\$?\s*(\d+\.?\d*)', report_raw)
        if m:
            result["report_refund_amount"] = float(m.group(1))

        # Extract clearance total (dollar value near "clearance")
        m = re.search(r'[Cc]learance[^$\d]*\$?\s*(\d+\.?\d*)', report_raw)
        if m:
            result["report_clearance_total"] = float(m.group(1))

    except Exception as e:
        print(f"Report parse error: {e}", file=sys.stderr)

with open(result_path, 'w', encoding='utf-8') as f:
    json.dump(result, f, indent=2)
print(f"Inventory rows: {result['inventory_row_count']}, report_table={result['report_has_shrinkage_table']}")
'@

    $pyScript = "C:\Windows\Temp\parse_quarterly_reconciliation.py"
    [System.IO.File]::WriteAllText($pyScript, $pythonScript)

    $parseResult = @{
        inventory_row_count       = 0
        inventory_items           = @{}
        report_content            = ""
        report_has_shrinkage_table = $false
        report_total_adjusted     = $null
        report_shrinkage_units    = $null
        report_refund_amount      = $null
        report_clearance_total    = $null
    }

    if ($inventoryExists -or $reportExists) {
        try {
            $pyOut = & python $pyScript $inventoryFile $reportFile $resultPath 2>&1
            Write-Host "Python output: $pyOut"
            if (Test-Path $resultPath) {
                $parsed = Get-Content $resultPath -Raw -Encoding UTF8 | ConvertFrom-Json
                $parseResult = $parsed
            }
        } catch {
            Write-Host "Python parsing failed: $($_.Exception.Message)"
        }
    }

    $inventoryIsNew = ($inventoryTs -gt $startTs) -and ($inventoryTs -gt 0)
    $reportIsNew    = ($reportTs -gt $startTs) -and ($reportTs -gt 0)

    $finalJson = @{
        task                       = "quarterly_inventory_reconciliation"
        inventory_file_exists      = $inventoryExists
        inventory_file_new         = $inventoryIsNew
        inventory_timestamp        = $inventoryTs
        report_file_exists         = $reportExists
        report_file_new            = $reportIsNew
        report_timestamp           = $reportTs
        start_timestamp            = $startTs
        inventory_row_count        = $parseResult.inventory_row_count
        inventory_items            = $parseResult.inventory_items
        report_content             = $parseResult.report_content
        report_has_shrinkage_table = $parseResult.report_has_shrinkage_table
        report_total_adjusted      = $parseResult.report_total_adjusted
        report_shrinkage_units     = $parseResult.report_shrinkage_units
        report_refund_amount       = $parseResult.report_refund_amount
        report_clearance_total     = $parseResult.report_clearance_total
    }

    $finalJson | ConvertTo-Json -Depth 5 | Out-File -FilePath $resultPath -Encoding UTF8 -Force

    Write-Host "inventory_exists=$inventoryExists (new=$inventoryIsNew), report_exists=$reportExists (new=$reportIsNew)"
    Write-Host "=== Export Complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
