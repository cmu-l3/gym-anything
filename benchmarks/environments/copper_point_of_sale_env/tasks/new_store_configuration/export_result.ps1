Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

$logPath = "C:\Users\Docker\task_store_config_export.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { }

try {
    Write-Host "=== Exporting new_store_configuration result ==="

    $desktopDir      = "C:\Users\Docker\Desktop"
    $taxVerifyFile   = Join-Path $desktopDir "tax_verification.txt"
    $startTsFile     = "C:\Users\Docker\task_start_ts_store_config.txt"
    $resultPath      = "C:\Users\Docker\new_store_config_result.json"

    # Read start timestamp
    $startTs = 0
    if (Test-Path $startTsFile) {
        try { $startTs = [int](Get-Content $startTsFile -Raw).Trim() } catch { }
    }

    # Check tax verification file
    $taxVerifyExists = $false
    $taxVerifyTs     = 0
    $taxVerifyContent = ""

    if (Test-Path $taxVerifyFile) {
        $taxVerifyExists  = $true
        $fi               = Get-Item $taxVerifyFile
        $taxVerifyTs      = [int][DateTimeOffset]::new($fi.LastWriteTimeUtc).ToUnixTimeSeconds()
        $taxVerifyContent = Get-Content $taxVerifyFile -Raw -ErrorAction SilentlyContinue
        Write-Host "tax_verification.txt found."
    } else {
        Write-Host "tax_verification.txt not found."
    }

    # Also try to find Copper's settings/config file for business name check
    # NCH Copper stores settings in the user's AppData or ProgramData
    $copperDataPaths = @(
        "$env:LOCALAPPDATA\NCH Software\Copper",
        "$env:APPDATA\NCH Software\Copper",
        "$env:ProgramData\NCH Software\Copper",
        "C:\Users\Docker\AppData\Local\NCH Software\Copper",
        "C:\Users\Docker\AppData\Roaming\NCH Software\Copper"
    )

    $copperDbPath = $null
    foreach ($p in $copperDataPaths) {
        if (Test-Path $p) {
            $dbFiles = Get-ChildItem $p -Recurse -Filter "*.db" -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($dbFiles) {
                $copperDbPath = $dbFiles.FullName
                Write-Host "Found Copper DB at: $copperDbPath"
                break
            }
        }
    }

    # Use Python to parse tax_verification.txt and optionally query DB
    $pythonScript = @'
import sys, json, re, os

tax_file   = sys.argv[1]
result_path = sys.argv[2]
db_path    = sys.argv[3] if len(sys.argv) > 3 else ""

content       = ""
has_biz_name  = False
has_tax_rate  = False
has_tax_amount = False
has_total     = False
tax_amount_found = None
total_found   = None
file_size     = 0

expected_biz_name   = "meridian goods"
expected_tax_amount = 4.80
expected_total      = 64.80

if os.path.exists(tax_file):
    file_size = os.path.getsize(tax_file)
    try:
        with open(tax_file, 'r', encoding='utf-8-sig', errors='replace') as f:
            content = f.read()
        content_lower = content.lower()

        # Check for business name
        if expected_biz_name in content_lower or "meridian" in content_lower:
            has_biz_name = True

        # Check for tax rate
        if '8.00%' in content or '8%' in content or '8.0%' in content:
            has_tax_rate = True

        # Extract tax amount - look for $4.80 or 4.80
        tax_matches = re.findall(r'tax\s*[:\s=]+\$?\s*(\d+\.\d{2})', content_lower)
        if tax_matches:
            try:
                tax_amount_found = float(tax_matches[0])
                has_tax_amount = abs(tax_amount_found - expected_tax_amount) <= 0.10
            except:
                pass

        # Also search for 4.80 anywhere
        if not has_tax_amount:
            all_amounts = re.findall(r'\$?\s*4\.8\d', content)
            if all_amounts:
                has_tax_amount = True
                tax_amount_found = 4.80

        # Extract total
        total_matches = re.findall(r'total\s*[:\s=]+\$?\s*(\d+\.\d{2})', content_lower)
        if total_matches:
            try:
                total_found = float(total_matches[-1])
                has_total = abs(total_found - expected_total) <= 0.20
            except:
                pass

        if not has_total:
            all_amounts = re.findall(r'\$?\s*64\.8\d', content)
            if all_amounts:
                has_total = True
                total_found = 64.80

    except Exception as e:
        print(f"File parse error: {e}", file=sys.stderr)

# Try to check Copper DB for configuration (bonus check)
db_has_biz_name = False
db_has_tax_rate = False

if db_path and os.path.exists(db_path):
    try:
        import sqlite3
        conn = sqlite3.connect(db_path)
        cursor = conn.cursor()
        # Try common table names for settings
        for table in ['Settings', 'settings', 'Config', 'config', 'Options', 'options']:
            try:
                rows = cursor.execute(f"SELECT * FROM {table}").fetchall()
                for row in rows:
                    row_str = ' '.join(str(c) for c in row).lower()
                    if 'meridian' in row_str:
                        db_has_biz_name = True
                    if '8.00' in row_str or '8.0' in row_str:
                        db_has_tax_rate = True
            except:
                pass
        conn.close()
    except Exception as e:
        print(f"DB check error: {e}", file=sys.stderr)

result = {
    "file_size":         file_size,
    "has_biz_name":      has_biz_name,
    "has_tax_rate":      has_tax_rate,
    "has_tax_amount":    has_tax_amount,
    "tax_amount_found":  tax_amount_found,
    "has_total":         has_total,
    "total_found":       total_found,
    "db_has_biz_name":   db_has_biz_name,
    "db_has_tax_rate":   db_has_tax_rate,
}

with open(result_path, 'w', encoding='utf-8') as f:
    json.dump(result, f, indent=2)
print(f"biz_name={has_biz_name}, tax_rate={has_tax_rate}, tax_amount={has_tax_amount}({tax_amount_found}), total={has_total}({total_found})")
'@

    $pyScript = "C:\Windows\Temp\parse_store_config.py"
    [System.IO.File]::WriteAllText($pyScript, $pythonScript)

    $parseResult = @{
        file_size        = 0
        has_biz_name     = $false
        has_tax_rate     = $false
        has_tax_amount   = $false
        tax_amount_found = $null
        has_total        = $false
        total_found      = $null
    }

    if ($taxVerifyExists) {
        $dbArg = if ($copperDbPath) { $copperDbPath } else { "" }
        try {
            $pyOut = & python $pyScript $taxVerifyFile $resultPath $dbArg 2>&1
            Write-Host "Python output: $pyOut"
            if (Test-Path $resultPath) {
                $parsed = Get-Content $resultPath -Raw -Encoding UTF8 | ConvertFrom-Json
                $parseResult = $parsed
            }
        } catch {
            Write-Host "Python parsing failed: $($_.Exception.Message)"
        }
    }

    $taxVerifyNew = ($taxVerifyTs -gt $startTs) -and ($taxVerifyTs -gt 0)

    $finalJson = @{
        task                 = "new_store_configuration"
        tax_verify_exists    = $taxVerifyExists
        tax_verify_new       = $taxVerifyNew
        tax_verify_timestamp = $taxVerifyTs
        start_timestamp      = $startTs
        file_size            = $parseResult.file_size
        has_biz_name         = $parseResult.has_biz_name
        has_tax_rate         = $parseResult.has_tax_rate
        has_tax_amount       = $parseResult.has_tax_amount
        tax_amount_found     = $parseResult.tax_amount_found
        has_total            = $parseResult.has_total
        total_found          = $parseResult.total_found
    }

    $finalJson | ConvertTo-Json -Depth 5 | Out-File -FilePath $resultPath -Encoding UTF8 -Force

    Write-Host "tax_verify_exists=$taxVerifyExists, new=$taxVerifyNew"
    Write-Host "=== Export Complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
