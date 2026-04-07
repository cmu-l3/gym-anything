#!/bin/bash
echo "=== Exporting configure_regional_sales_settings results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot as evidence
take_screenshot /tmp/task_final.png

# Query the database for the relevant Tax Rates created
suitecrm_db_query "SELECT id, name, value, status, date_entered FROM taxrates WHERE deleted=0 AND (name LIKE '%GST - Canada%' OR name LIKE '%PST - British Columbia%' OR name LIKE '%HST - Ontario%')" > /tmp/taxrates.tsv

# Query the database for the relevant Shipping Providers created
suitecrm_db_query "SELECT id, name, status, date_entered FROM shippers WHERE deleted=0 AND (name LIKE '%Canada Post%' OR name LIKE '%Purolator%')" > /tmp/shippers.tsv

# Use Python to parse the TSV output into a clean JSON result for the verifier
python3 << 'PYEOF'
import json
import os

def parse_tsv(path, headers):
    if not os.path.exists(path):
        return []
    with open(path, 'r') as f:
        lines = f.read().strip().split('\n')
    
    if not lines or not lines[0]:
        return []
        
    res = []
    for l in lines:
        parts = l.split('\t')
        res.append({headers[i]: parts[i] if i < len(parts) else "" for i in range(len(headers))})
    return res

taxrates = parse_tsv('/tmp/taxrates.tsv', ['id', 'name', 'value', 'status', 'date_entered'])
shippers = parse_tsv('/tmp/shippers.tsv', ['id', 'name', 'status', 'date_entered'])

start_time = 0
if os.path.exists('/tmp/task_start_time.txt'):
    with open('/tmp/task_start_time.txt', 'r') as f:
        txt = f.read().strip()
        if txt.isdigit(): 
            start_time = int(txt)

result = {
    'taxrates': taxrates,
    'shippers': shippers,
    'task_start_time': start_time
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="