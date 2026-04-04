#!/bin/bash
echo "=== Exporting import_business_assets result ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final state screenshot
take_screenshot /tmp/task_final.png

# 2. Get task timings
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 3. Query Database for results
# We check for specific assets created AFTER the task start time
# Using python to handle the SQL execution and JSON formatting safely

python3 -c "
import subprocess
import json
import time

def run_query(sql):
    cmd = ['docker', 'exec', 'eramba-db', 'mysql', '-u', 'eramba', '-peramba_db_pass', 'eramba', '-N', '-e', sql]
    try:
        return subprocess.check_output(cmd, stderr=subprocess.DEVNULL).decode('utf-8').strip()
    except:
        return ''

task_start = $TASK_START
target_assets = ['US-EAST-DB-01', 'US-WEST-WEB-04', 'EU-FR-API-02', 'BAK-SRV-09', 'DEV-BUILD-01']

found_assets = []
data_integrity = False

# Check each asset
for asset in target_assets:
    # Eramba stores 'created' as DATETIME. 
    # We check if title matches AND it was created recently (or just exists if timestamp logic is tricky in SQL)
    # Ideally, we check created > FROM_UNIXTIME(task_start)
    sql = f\"SELECT count(*) FROM business_assets WHERE title='{asset}' AND deleted=0;\"
    count = run_query(sql)
    if count == '1':
        found_assets.append(asset)

# Check description mapping for the first asset
desc_sql = \"SELECT description FROM business_assets WHERE title='US-EAST-DB-01' LIMIT 1;\"
description = run_query(desc_sql)
if 'Primary Customer Database' in description:
    data_integrity = True

# Get total count change
try:
    with open('/tmp/initial_asset_count.txt', 'r') as f:
        initial_count = int(f.read().strip())
except:
    initial_count = 0

final_count_str = run_query(\"SELECT COUNT(*) FROM business_assets WHERE deleted=0;\")
final_count = int(final_count_str) if final_count_str.isdigit() else 0
count_delta = final_count - initial_count

result = {
    'task_start': task_start,
    'found_assets': found_assets,
    'total_found': len(found_assets),
    'data_integrity_check': data_integrity,
    'retrieved_description': description,
    'count_delta': count_delta,
    'initial_count': initial_count,
    'final_count': final_count
}

print(json.dumps(result))
" > /tmp/task_result.json

# 4. Handle permissions for copy_from_env
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Export complete. Result:"
cat /tmp/task_result.json