#!/bin/bash
set -e

echo "=== Exporting Configure Campaign CRM Integration results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query the database for the final state of the campaign
echo "Querying database for campaign settings..."

# We use docker exec to run the query inside the container
# Output format: JSON-like or strict CSV for parsing
DB_RESULT=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -N -B -e "
SELECT web_form_address, web_form_target, dispo_call_url 
FROM vicidial_campaigns 
WHERE campaign_id='SALESTEAM';
" 2>/dev/null)

# Parse the tab-separated result
# IFS is tab
IFS=$'\t' read -r WEB_FORM_ADDR WEB_FORM_TARGET DISPO_URL <<< "$DB_RESULT"

# Escape for JSON (basic escaping for quotes and backslashes)
WEB_FORM_ADDR_ESC=$(echo "$WEB_FORM_ADDR" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g')
WEB_FORM_TARGET_ESC=$(echo "$WEB_FORM_TARGET" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g')
DISPO_URL_ESC=$(echo "$DISPO_URL" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g')

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "campaign_id": "SALESTEAM",
    "web_form_address": "$WEB_FORM_ADDR_ESC",
    "web_form_target": "$WEB_FORM_TARGET_ESC",
    "dispo_call_url": "$DISPO_URL_ESC",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location with proper permissions
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Exported data:"
cat /tmp/task_result.json
echo "=== Export complete ==="