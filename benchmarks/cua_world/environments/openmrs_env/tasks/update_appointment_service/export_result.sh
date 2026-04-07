#!/bin/bash
set -e
echo "=== Exporting update_appointment_service result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# ── Query Database for Service State ─────────────────────────────────────────
# We fetch specific fields to verify the update
# We also fetch unix_timestamp(date_changed) to verify recency

# Construct SQL query
SQL="SELECT duration_mins, description, UNIX_TIMESTAMP(date_changed), UNIX_TIMESTAMP(date_created) \
     FROM appointment_service \
     WHERE name = 'Dermatology Consult' AND voided = 0 LIMIT 1;"

# Run query via helper
# Result format depends on mariadb client but usually tab separated
RESULT_LINE=$(omrs_db_query "$SQL")

# Parse result (handling potential empty results if service deleted)
DURATION=""
DESCRIPTION=""
DATE_CHANGED="0"
DATE_CREATED="0"
SERVICE_EXISTS="false"

if [ -n "$RESULT_LINE" ]; then
    SERVICE_EXISTS="true"
    # Read tab-separated values
    # Note: Description might contain spaces, so we use read with specific delimiter if needed,
    # but omrs_db_query output format needs care. simpler to fetch individually if parsing is complex,
    # but here we'll try read.
    # Using python to safely parse the tab-separated line helps handle spaces in description
    
    # Export vars for python script
    export RES_LINE="$RESULT_LINE"
    
    eval $(python3 -c "
import os, sys
try:
    line = os.environ['RES_LINE']
    parts = line.split('\t')
    # Pad with empty strings if missing
    while len(parts) < 4: parts.append('')
    
    print(f'DURATION=\"{parts[0]}\"')
    # Escape quotes in description for shell safety
    desc = parts[1].replace('\"', '\\\"')
    print(f'DESCRIPTION=\"{desc}\"')
    
    # Handle NULL timestamps (which come as 'NULL' or empty depending on client)
    dc = parts[2] if parts[2] not in ['NULL', 'None', ''] else '0'
    print(f'DATE_CHANGED=\"{dc}\"')
    
    dcr = parts[3] if parts[3] not in ['NULL', 'None', ''] else '0'
    print(f'DATE_CREATED=\"{dcr}\"')
except Exception as e:
    print('error parsing')
")
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "service_exists": $SERVICE_EXISTS,
    "duration_mins": "${DURATION:-0}",
    "description": "${DESCRIPTION}",
    "date_changed_ts": ${DATE_CHANGED:-0},
    "date_created_ts": ${DATE_CREATED:-0},
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="