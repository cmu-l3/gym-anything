#!/bin/bash
echo "=== Exporting Configure Manual Preview Campaign Result ==="

source /workspace/scripts/task_utils.sh

# Record task end
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Query Campaign Configuration
# We use docker exec to query the database directly
echo "Querying Campaign settings..."
CAMPAIGN_JSON=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -N -e "
SELECT JSON_OBJECT(
    'dial_method', dial_method,
    'manual_dial_preview', manual_dial_preview,
    'lead_order', lead_order,
    'auto_alt_dial', auto_alt_dial,
    'active', active
)
FROM vicidial_campaigns
WHERE campaign_id = 'VIP_DIAL';
" 2>/dev/null || echo "{}")

# 2. Query List Data (Validation of Import)
echo "Querying List 9500 data..."
LIST_COUNT=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -N -e "SELECT COUNT(*) FROM vicidial_list WHERE list_id='9500';" 2>/dev/null || echo "0")

# Get a sample row to verify mapping
# We want to check if 'Gov_ID' mapped to 'vendor_lead_code', etc.
SAMPLE_ROW_JSON=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -N -e "
SELECT JSON_OBJECT(
    'phone_number', phone_number,
    'first_name', first_name,
    'vendor_lead_code', vendor_lead_code,
    'state', state
)
FROM vicidial_list
WHERE list_id = '9500' AND vendor_lead_code != ''
LIMIT 1;
" 2>/dev/null || echo "{}")

# 3. Check file access (did they use the file?)
FILE_USED="false"
# Simple check: Firefox download/upload history is hard to check reliably in docker, 
# but we can check if the file still exists and is readable (it should).
if [ -f "/home/ga/Documents/VicidialData/vendor_senators_vip.csv" ]; then
    FILE_USED="true" # Assumption based on successful DB load
fi

# Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "campaign_config": $CAMPAIGN_JSON,
    "list_count": $LIST_COUNT,
    "sample_row": $SAMPLE_ROW_JSON,
    "file_available": $FILE_USED,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="