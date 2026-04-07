#!/bin/bash
# Post-task export for audit_tiu_definitions
set -e

echo "=== Exporting Task Results ==="

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)
REPORT_PATH="/home/ga/Documents/tiu_titles_report.txt"

# 1. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Analyze Report File
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
LINE_COUNT=0

if [ -f "$REPORT_PATH" ]; then
    FILE_EXISTS="true"
    FILE_MTIME=$(stat -c %Y "$REPORT_PATH")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Count non-empty lines
    LINE_COUNT=$(grep -cve '^\s*$' "$REPORT_PATH" || echo "0")
fi

# 3. Extract Ground Truth from VistA (to verify user's IENs)
# We will dump ALL TIU titles (Type=TL) to a JSON structure for the verifier
# Using a temporary M script inside the container
echo "Querying VistA for Ground Truth..."

# Create a safe temp file for the query result inside the container
docker exec -u vehu vista-vehu bash -c "mkdir -p /tmp/export"

# Query logic: Iterate ^TIU(8925.1), check piece 4 for 'TL', output IEN^NAME
# We limit to first 200 matches to keep JSON manageable, or just specific ones if user file existed (but we can't easily parse user file inside bash robustly to feed to M)
# Better: Just dump a good sample of Titles.
QUERY_CMD='S U="^",X=0,C=0 W "{" F  S X=$O(^TIU(8925.1,X)) Q:X=""  S N0=$G(^TIU(8925.1,X,0)) I $P(N0,U,4)="TL" W:C>0 "," W "\""_X_"\":\""_$P(N0,U,1)_"\"" S C=C+1'
QUERY_CMD="${QUERY_CMD} W \"}\""

# Execute query and capture output
VALID_TITLES_JSON=$(docker exec -u vehu vista-vehu bash -c "source /home/vehu/etc/env && yottadb -run %XCMD '$QUERY_CMD'" 2>/dev/null || echo "{}")

# 4. Check App Status
APP_RUNNING="false"
if pgrep -f firefox > /dev/null; then
    APP_RUNNING="true"
fi

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "line_count": $LINE_COUNT,
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png",
    "report_path_in_container": "$REPORT_PATH",
    "valid_titles_map": $VALID_TITLES_JSON
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"