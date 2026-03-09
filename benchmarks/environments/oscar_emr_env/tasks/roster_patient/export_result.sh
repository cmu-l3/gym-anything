#!/bin/bash
echo "=== Exporting Roster Patient Results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final state screenshot
take_screenshot /tmp/task_final.png

# 2. Query Database for Michael Chang's current status
echo "Querying database..."

# Fetch columns: roster_status, roster_date, provider_no
# Use simple separator that won't appear in data
RESULT=$(oscar_query "SELECT roster_status, roster_date, provider_no, lastUpdateDate FROM demographic WHERE first_name='Michael' AND last_name='Chang' LIMIT 1")

# Default values if query fails
ROSTER_STATUS=""
ROSTER_DATE=""
PROVIDER_NO=""
LAST_UPDATE=""

if [ -n "$RESULT" ]; then
    ROSTER_STATUS=$(echo "$RESULT" | awk '{print $1}')
    ROSTER_DATE=$(echo "$RESULT" | awk '{print $2}')
    PROVIDER_NO=$(echo "$RESULT" | awk '{print $3}')
    # lastUpdateDate might have time, capture full string if possible, but awk default split is space
    # simplified extraction for the JSON
fi

# 3. Get timestamps
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_START_DATE=$(cat /tmp/task_start_date.txt 2>/dev/null || date +%Y-%m-%d)
CURRENT_DATE=$(date +%Y-%m-%d)

# 4. Create JSON result
# Use a temp file and move it to avoid permission issues
TEMP_JSON=$(mktemp /tmp/roster_result.XXXXXX.json)

cat > "$TEMP_JSON" << EOF
{
    "patient_found": $([ -n "$RESULT" ] && echo "true" || echo "false"),
    "roster_status": "$ROSTER_STATUS",
    "roster_date": "$ROSTER_DATE",
    "provider_no": "$PROVIDER_NO",
    "task_start_date": "$TASK_START_DATE",
    "current_date": "$CURRENT_DATE",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location with broad permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="