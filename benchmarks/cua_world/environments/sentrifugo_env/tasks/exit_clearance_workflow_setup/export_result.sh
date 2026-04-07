#!/bin/bash
echo "=== Exporting task results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Execute a Python script inside the container to safely dump DB state to JSON
# This avoids bash escaping nightmares with TSV/CSV data
cat > /tmp/db_dump.py << 'EOF'
import subprocess
import json
import csv
import io
import os

def run_query(query):
    cmd = f'docker exec sentrifugo-db mysql -u sentrifugo -psentrifugo123 sentrifugo -e "{query}"'
    try:
        out = subprocess.check_output(cmd, shell=True, text=True)
        if not out.strip():
            return []
        # MySQL -e outputs tab-separated with headers by default
        reader = csv.DictReader(io.StringIO(out), delimiter='\t')
        return list(reader)
    except Exception as e:
        return []

result = {
    "task_start": int(open("/tmp/task_start_time.txt").read().strip()) if os.path.exists("/tmp/task_start_time.txt") else 0,
    "task_end": 0,  # Will be filled by bash
    "clearance_tables": {},
    "users": []
}

try:
    # Find all tables related to clearance dynamically (usually main_clearancedepartments, etc.)
    tables_out = subprocess.check_output('docker exec sentrifugo-db mysql -u sentrifugo -psentrifugo123 sentrifugo -N -e "SHOW TABLES LIKE \'%clearance%\';"', shell=True, text=True)
    tables = [t.strip() for t in tables_out.split() if t.strip()]
    
    for t in tables:
        result["clearance_tables"][t] = run_query(f"SELECT * FROM {t}")
        
    # Get user mappings to resolve approver names
    result["users"] = run_query("SELECT id, firstname, lastname, employeeId FROM main_users")
    
except Exception as e:
    result["error"] = str(e)

with open('/tmp/temp_task_result.json', 'w') as f:
    json.dump(result, f)
EOF

python3 /tmp/db_dump.py

# Inject end time and screenshot info
jq ".task_end = $TASK_END | .screenshot_exists = true" /tmp/temp_task_result.json > /tmp/task_result.json

# Cleanup and permissions
rm /tmp/temp_task_result.json /tmp/db_dump.py
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="