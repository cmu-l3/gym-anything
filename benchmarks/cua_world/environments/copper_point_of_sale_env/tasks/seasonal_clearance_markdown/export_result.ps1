Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

$logPath = "C:\Users\Docker\task_seasonal_clearance_export.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { }

try {
    Write-Host "=== Exporting seasonal_clearance_markdown result ==="

    $desktopDir   = "C:\Users\Docker\Desktop"
    $exportedFile = Join-Path $desktopDir "clearance_inventory.csv"
    $startTsFile  = "C:\Users\Docker\task_start_ts_seasonal_clearance.txt"
    $resultPath   = "C:\Users\Docker\seasonal_clearance_result.json"

    # Read task start timestamp
    $startTs = 0
    if (Test-Path $startTsFile) {
        try { $startTs = [int](Get-Content $startTsFile -Raw).Trim() } catch { }
    }

    # Check if exported file exists and get its timestamp
    $exportExists  = $false
    $exportTs      = 0
    $exportContent = ""

    if (Test-Path $exportedFile) {
        $exportExists  = $true
        $fileInfo      = Get-Item $exportedFile
        $exportTs      = [int][DateTimeOffset]::new($fileInfo.LastWriteTimeUtc).ToUnixTimeSeconds()
        $exportContent = Get-Content $exportedFile -Raw -ErrorAction SilentlyContinue
    }

    # Use Python to parse the exported CSV robustly and extract item prices
    $pythonScript = @'
import sys, csv, json, io, os

export_file = sys.argv[1]
result_path = sys.argv[2]

# Ground truth: original data from clothing_inventory.csv
originals = {
    "floral white top":     {"qty": 39, "original_price": 75.00, "expected_clearance": 60.00},
    "striped silk blouse":  {"qty": 32, "original_price": 50.00, "expected_clearance": 40.00},
    "dark denim top":       {"qty": 37, "original_price": 60.00, "expected_clearance": 48.00},
    "navy sports jacket":   {"qty": 40, "original_price": 60.00, "expected_clearance": 48.00},
    "soft winter jacket":   {"qty": 46, "original_price": 50.00, "expected_clearance": 40.00},
    "black leather bag":    {"qty": 31, "original_price": 30.00, "expected_clearance": 24.00},
    "zipped jacket":        {"qty": 42, "original_price": 65.00, "expected_clearance": 52.00},
    "led high tops":        {"qty": 39, "original_price": 80.00, "expected_clearance": 64.00},
}
low_stock_originals = {
    "ocean blue shirt":       {"qty": 6,  "original_price": 50.00, "expected_premium": 57.50},
    "silk summer top":        {"qty": 5,  "original_price": 70.00, "expected_premium": 80.50},
    "striped skirt and top":  {"qty": 7,  "original_price": 50.00, "expected_premium": 57.50},
}

items_found = {}
row_count   = 0

if os.path.exists(export_file):
    try:
        with open(export_file, 'r', encoding='utf-8-sig', errors='replace') as f:
            content = f.read()
        reader = csv.DictReader(io.StringIO(content))
        price_col = None
        name_col  = None
        for row in reader:
            row_count += 1
            # Detect column names flexibly
            if name_col is None:
                for k in row.keys():
                    kl = k.lower().strip()
                    if 'name' in kl or 'item' in kl or 'product' in kl:
                        name_col = k
                        break
            if price_col is None:
                for k in row.keys():
                    kl = k.lower().strip()
                    if 'price' in kl or 'sell' in kl or 'unit' in kl:
                        price_col = k
                        break
            if name_col and price_col:
                name = str(row.get(name_col, '')).strip().lower()
                price_str = str(row.get(price_col, '0')).replace('$','').replace(',','').strip()
                try:
                    price = float(price_str)
                except:
                    price = 0.0
                items_found[name] = price
    except Exception as e:
        print(f"Parse error: {e}", file=sys.stderr)

# Evaluate clearance pricing (should be ~80% of original)
clearance_results = {}
for item_key, info in originals.items():
    found_price = None
    for name, price in items_found.items():
        if item_key in name or name in item_key:
            found_price = price
            break
    expected = info["expected_clearance"]
    is_correct = found_price is not None and abs(found_price - expected) / expected <= 0.08
    clearance_results[item_key] = {
        "found_price": found_price,
        "expected_price": expected,
        "correct": is_correct
    }

# Evaluate premium pricing (should be ~115% of original)
premium_results = {}
for item_key, info in low_stock_originals.items():
    found_price = None
    for name, price in items_found.items():
        if item_key in name or name in item_key:
            found_price = price
            break
    expected = info["expected_premium"]
    is_correct = found_price is not None and abs(found_price - expected) / expected <= 0.08
    premium_results[item_key] = {
        "found_price": found_price,
        "expected_price": expected,
        "correct": is_correct
    }

clearance_correct_count = sum(1 for v in clearance_results.values() if v["correct"])
premium_correct_count   = sum(1 for v in premium_results.values() if v["correct"])

output = {
    "row_count":              row_count,
    "items_parsed":           len(items_found),
    "clearance_results":      clearance_results,
    "premium_results":        premium_results,
    "clearance_correct_count": clearance_correct_count,
    "premium_correct_count":   premium_correct_count,
}

with open(result_path, 'w', encoding='utf-8') as f:
    json.dump(output, f, indent=2)
print(f"Parsed {row_count} rows, found {len(items_found)} named items")
print(f"Clearance correct: {clearance_correct_count}/8, Premium correct: {premium_correct_count}/3")
'@

    # Write python script to temp file and run it
    $pyScript = "C:\Windows\Temp\parse_clearance.py"
    [System.IO.File]::WriteAllText($pyScript, $pythonScript)

    $parseResult = @{
        row_count              = 0
        items_parsed           = 0
        clearance_correct_count = 0
        premium_correct_count  = 0
        clearance_results      = @{}
        premium_results        = @{}
    }

    if ($exportExists) {
        try {
            $pyOut = & python $pyScript $exportedFile $resultPath 2>&1
            Write-Host "Python parser output: $pyOut"
            # Read the parsed result if python succeeded
            if (Test-Path $resultPath) {
                $parsed = Get-Content $resultPath -Raw -Encoding UTF8 | ConvertFrom-Json
                $parseResult = $parsed
            }
        } catch {
            Write-Host "Python parsing failed: $($_.Exception.Message)"
        }
    }

    # Build the final JSON result
    $exportExistsStr   = if ($exportExists) { "true" } else { "false" }
    $fileIsNew = ($exportTs -gt $startTs) -and ($exportTs -gt 0)
    $fileIsNewStr      = if ($fileIsNew) { "true" } else { "false" }
    $clearanceCount    = if ($parseResult.clearance_correct_count -ne $null) { $parseResult.clearance_correct_count } else { 0 }
    $premiumCount      = if ($parseResult.premium_correct_count -ne $null) { $parseResult.premium_correct_count } else { 0 }
    $rowCount          = if ($parseResult.row_count -ne $null) { $parseResult.row_count } else { 0 }

    $finalJson = @{
        task              = "seasonal_clearance_markdown"
        export_file_exists = $exportExists
        export_file_new   = $fileIsNew
        export_timestamp  = $exportTs
        start_timestamp   = $startTs
        row_count         = $rowCount
        clearance_correct_count = $clearanceCount
        premium_correct_count   = $premiumCount
        export_result_path = $resultPath
    }

    $finalJson | ConvertTo-Json -Depth 5 | Out-File -FilePath $resultPath -Encoding UTF8 -Force

    Write-Host "export_file_exists=$exportExists, file_is_new=$fileIsNew"
    Write-Host "clearance_correct=$clearanceCount/8, premium_correct=$premiumCount/3"
    Write-Host "=== Export Complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
