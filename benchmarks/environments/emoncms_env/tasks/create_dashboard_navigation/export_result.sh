#!/bin/bash
# Export script for Create Dashboard Navigation task
set -e

source /workspace/scripts/task_utils.sh

echo "=== Exporting Dashboard Navigation Results ==="

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Read the IDs we stored during setup
if [ -f /tmp/dashboard_ids.json ]; then
    LANDING_ID=$(jq -r '.landing_id' /tmp/dashboard_ids.json)
    HVAC_ID=$(jq -r '.targets.HVAC' /tmp/dashboard_ids.json)
    LIGHTING_ID=$(jq -r '.targets.Lighting' /tmp/dashboard_ids.json)
    SOLAR_ID=$(jq -r '.targets.Solar' /tmp/dashboard_ids.json)
else
    # Fallback lookup if temp file lost
    LANDING_ID=$(db_query "SELECT id FROM dashboard WHERE name='Facility Overview'" | head -1)
    HVAC_ID=$(db_query "SELECT id FROM dashboard WHERE name='HVAC Detail'" | head -1)
    LIGHTING_ID=$(db_query "SELECT id FROM dashboard WHERE name='Lighting Detail'" | head -1)
    SOLAR_ID=$(db_query "SELECT id FROM dashboard WHERE name='Solar Detail'" | head -1)
fi

echo "Checking content of Landing Dashboard ID: $LANDING_ID"

# Fetch content from DB
# Emoncms stores dashboard widgets in the 'content' column as a JSON array
RAW_CONTENT=$(db_query "SELECT content FROM dashboard WHERE id=$LANDING_ID")

# Fetch modification time (if available, otherwise rely on content check)
# Emoncms doesn't strictly track 'last_modified' column in older versions, 
# so we mostly rely on content difference from '[]'.

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "landing_dashboard_id": "$LANDING_ID",
    "target_ids": {
        "hvac": "$HVAC_ID",
        "lighting": "$LIGHTING_ID",
        "solar": "$SOLAR_ID"
    },
    "dashboard_content": $(echo "$RAW_CONTENT" | jq -R .),
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
echo "=== Export Complete ==="