#!/bin/bash
set -e
echo "=== Exporting batch_nir_correction results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 1. Export Database State for specific patients
# We select the fields needed for verification
echo "Exporting database state..."
mysql -u root DrTuxTest -e "
SELECT 
    i.FchGnrl_NomDos as nom,
    i.FchGnrl_Prenom as prenom,
    f.FchPat_NumSS as ssn
FROM IndexNomPrenom i
JOIN fchpat f ON i.FchGnrl_IDDos = f.FchPat_GUID_Doss
WHERE i.FchGnrl_NomDos IN ('MARTIN', 'DURAND', 'PETIT', 'LEGRAND', 'MOREL')
" > /tmp/db_export.txt

# Convert MySQL output to JSON-like structure or just read raw in Python
# We'll use a python one-liner to create a proper JSON object from the query result
python3 -c "
import sys, json, csv
lines = sys.stdin.readlines()
result = {}
# Skip header
for line in lines[1:]:
    parts = line.strip().split('\t')
    if len(parts) >= 3:
        key = f'{parts[0]}_{parts[1]}'
        result[key] = parts[2]
print(json.dumps(result))
" < /tmp/db_export.txt > /tmp/db_state.json

# 2. Check Log File
LOG_FILE="/home/ga/Documents/missing_patients_log.txt"
LOG_EXISTS="false"
LOG_CONTENT=""
LOG_CREATED_DURING="false"

if [ -f "$LOG_FILE" ]; then
    LOG_EXISTS="true"
    LOG_CONTENT=$(cat "$LOG_FILE" | head -c 1000) # Limit size
    
    # Check creation time
    FILE_MTIME=$(stat -c %Y "$LOG_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        LOG_CREATED_DURING="true"
    fi
fi

# 3. Take Final Screenshot
take_screenshot /tmp/task_final.png

# 4. Construct Final JSON
# Use a temp file to avoid permission issues
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "db_state": $(cat /tmp/db_state.json),
    "log_file": {
        "exists": $LOG_EXISTS,
        "content": $(echo "$LOG_CONTENT" | jq -R .),
        "created_during_task": $LOG_CREATED_DURING
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move and set permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "=== Export complete ==="