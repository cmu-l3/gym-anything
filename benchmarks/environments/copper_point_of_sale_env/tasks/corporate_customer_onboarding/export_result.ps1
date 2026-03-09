Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

$logPath = "C:\Users\Docker\task_corp_onboarding_export.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { }

try {
    Write-Host "=== Exporting corporate_customer_onboarding result ==="

    $desktopDir   = "C:\Users\Docker\Desktop"
    $exportFile   = Join-Path $desktopDir "customer_accounts.csv"
    $startTsFile  = "C:\Users\Docker\task_start_ts_corp_onboarding.txt"
    $resultPath   = "C:\Users\Docker\corporate_onboarding_result.json"

    # Read start timestamp
    $startTs = 0
    if (Test-Path $startTsFile) {
        try { $startTs = [int](Get-Content $startTsFile -Raw).Trim() } catch { }
    }

    $exportExists = $false
    $exportTs     = 0

    if (Test-Path $exportFile) {
        $exportExists = $true
        $fi           = Get-Item $exportFile
        $exportTs     = [int][DateTimeOffset]::new($fi.LastWriteTimeUtc).ToUnixTimeSeconds()
        Write-Host "customer_accounts.csv found, size=$($fi.Length)"
    } else {
        Write-Host "customer_accounts.csv not found."
    }

    # Use Python to parse the customer CSV and check for expected names/notes
    $pythonScript = @'
import sys, csv, json, io, os

export_file = sys.argv[1]
result_path = sys.argv[2]

# Corporate accounts that should appear
expected_companies = [
    "pacific northwest distributors",
    "midwest retail holdings",
    "southern fashion group",
    "great lakes supply co",
    "atlantic coast trading",
    "mountain west goods",
]

# Existing customers whose notes should be updated
update_targets = {
    "sheryl baxter":  "preferred account: yes",
    "preston lozano": "preferred account: yes",
    "roy berry":      "preferred account: no",
}

companies_found    = []
updates_found      = {}
has_gold_tier      = False
has_silver_tier    = False
has_bronze_tier    = False
has_credit_limit   = False
total_rows         = 0
all_names          = []

if os.path.exists(export_file):
    try:
        with open(export_file, 'r', encoding='utf-8-sig', errors='replace') as f:
            raw = f.read()

        reader = csv.DictReader(io.StringIO(raw))
        name_cols  = []
        notes_cols = []

        for row in reader:
            total_rows += 1
            if not name_cols:
                for k in row.keys():
                    kl = k.lower().strip()
                    if any(x in kl for x in ['name', 'first', 'last', 'company', 'contact']):
                        name_cols.append(k)
                    if any(x in kl for x in ['note', 'comment', 'memo', 'remark']):
                        notes_cols.append(k)

            # Build a combined text for this row
            row_text = ' '.join(str(v) for v in row.values()).lower()
            all_names.append(row_text[:100])

            # Check for corporate company names
            for co in expected_companies:
                if co in row_text and co not in companies_found:
                    companies_found.append(co)

            # Check tier keywords
            if 'gold' in row_text:
                has_gold_tier = True
            if 'silver' in row_text:
                has_silver_tier = True
            if 'bronze' in row_text:
                has_bronze_tier = True
            if 'credit limit' in row_text or '$25,000' in row_text or '$15,000' in row_text or '$30,000' in row_text:
                has_credit_limit = True

            # Check updated existing customers
            for target_name, expected_note in update_targets.items():
                parts = target_name.split()
                if len(parts) == 2 and parts[0] in row_text and parts[1] in row_text:
                    note_text = ''
                    for nc in notes_cols:
                        note_text += str(row.get(nc, '')).lower() + ' '
                    note_text += row_text
                    if expected_note.split(':')[0].lower() in note_text:
                        updates_found[target_name] = True
                    else:
                        if target_name not in updates_found:
                            updates_found[target_name] = False

    except Exception as e:
        print(f"Parse error: {e}", file=sys.stderr)

companies_found_count = len(companies_found)
updates_found_count   = sum(1 for v in updates_found.values() if v)

result = {
    "total_rows":             total_rows,
    "companies_found":        companies_found,
    "companies_found_count":  companies_found_count,
    "updates_found":          updates_found,
    "updates_found_count":    updates_found_count,
    "has_gold_tier":          has_gold_tier,
    "has_silver_tier":        has_silver_tier,
    "has_bronze_tier":        has_bronze_tier,
    "has_credit_limit":       has_credit_limit,
}

with open(result_path, 'w', encoding='utf-8') as f:
    json.dump(result, f, indent=2)
print(f"Rows={total_rows}, companies_found={companies_found_count}/6, updates={updates_found_count}/3")
'@

    $pyScript = "C:\Windows\Temp\parse_customers.py"
    [System.IO.File]::WriteAllText($pyScript, $pythonScript)

    $parseResult = @{
        total_rows            = 0
        companies_found_count = 0
        updates_found_count   = 0
        has_gold_tier         = $false
        has_silver_tier       = $false
        has_bronze_tier       = $false
        has_credit_limit      = $false
    }

    if ($exportExists) {
        try {
            $pyOut = & python $pyScript $exportFile $resultPath 2>&1
            Write-Host "Python output: $pyOut"
            if (Test-Path $resultPath) {
                $parsed = Get-Content $resultPath -Raw -Encoding UTF8 | ConvertFrom-Json
                $parseResult = $parsed
            }
        } catch {
            Write-Host "Python parsing failed: $($_.Exception.Message)"
        }
    }

    $fileIsNew = ($exportTs -gt $startTs) -and ($exportTs -gt 0)

    $finalJson = @{
        task                  = "corporate_customer_onboarding"
        export_file_exists    = $exportExists
        export_file_new       = $fileIsNew
        export_timestamp      = $exportTs
        start_timestamp       = $startTs
        total_rows            = $parseResult.total_rows
        companies_found_count = $parseResult.companies_found_count
        updates_found_count   = $parseResult.updates_found_count
        has_gold_tier         = $parseResult.has_gold_tier
        has_silver_tier       = $parseResult.has_silver_tier
        has_bronze_tier       = $parseResult.has_bronze_tier
        has_credit_limit      = $parseResult.has_credit_limit
    }

    $finalJson | ConvertTo-Json -Depth 5 | Out-File -FilePath $resultPath -Encoding UTF8 -Force

    Write-Host "export_exists=$exportExists, new=$fileIsNew, companies=$($parseResult.companies_found_count)/6, updates=$($parseResult.updates_found_count)/3"
    Write-Host "=== Export Complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
