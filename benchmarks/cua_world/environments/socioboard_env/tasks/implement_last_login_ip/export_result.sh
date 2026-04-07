#!/bin/bash
echo "=== Exporting implement_last_login_ip result ==="

source /workspace/scripts/task_utils.sh

# Take a final screenshot
take_screenshot /tmp/task_final.png

# 1. Check Database Schema
log "Querying database for last_login_ip column..."
DB_COL_TYPE=$(mysql -u root socioboard -N -s -e "SELECT column_type FROM information_schema.columns WHERE table_schema='socioboard' AND table_name='user_details' AND column_name='last_login_ip';" 2>/dev/null | tr -d '\n' | tr '[:upper:]' '[:lower:]')

# 2. Check Sequelize Model File
MODEL_PATH="/opt/socioboard/socioboard-api/library/sequelize-cli/models/user_details.js"
FILE_MODIFIED="false"
FILE_HAS_IP_FIELD="false"
FILE_HAS_DATATYPE="false"

if [ -f "$MODEL_PATH" ]; then
    TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$MODEL_PATH" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
    
    if grep -q "last_login_ip" "$MODEL_PATH"; then
        FILE_HAS_IP_FIELD="true"
    fi
    
    if grep -q "DataTypes.STRING" "$MODEL_PATH"; then
        FILE_HAS_DATATYPE="true"
    fi
fi

# 3. Check PM2 Microservices Status
log "Fetching PM2 microservices status..."
PM2_JSON=$(su - ga -c "pm2 jlist 2>/dev/null" || echo "[]")

# Create JSON Export safely using Python to avoid quoting issues
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
python3 << EOF
import json

try:
    pm2_data = json.loads('''$PM2_JSON''')
except Exception:
    pm2_data = []

result = {
    "db_column_type": "$DB_COL_TYPE",
    "file_modified_during_task": "$FILE_MODIFIED" == "true",
    "file_has_ip_field": "$FILE_HAS_IP_FIELD" == "true",
    "file_has_datatype": "$FILE_HAS_DATATYPE" == "true",
    "pm2_status": pm2_data,
    "task_start_time": $(cat /tmp/task_start_time.txt 2>/dev/null || echo 0),
    "export_time": $(date +%s)
}

with open('$TEMP_JSON', 'w') as f:
    json.dump(result, f, indent=2)
EOF

# Move temp file to final destination securely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/task_result.json"
cat /tmp/task_result.json

echo "=== Export Complete ==="