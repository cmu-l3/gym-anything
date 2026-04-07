#!/bin/bash
# Export script for Create Custom Dashboard task

echo "=== Exporting Create Custom Dashboard Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_screenshot.png
echo "Final screenshot saved"

# Get timestamps
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Get initial state
INITIAL_MAX_ID=$(cat /tmp/initial_max_dashboard_id 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_dashboard_count 2>/dev/null || echo "0")

# Query current state
CURRENT_COUNT=$(matomo_query "SELECT COUNT(*) FROM matomo_user_dashboard" 2>/dev/null || echo "0")
echo "Dashboard count: Initial=$INITIAL_COUNT, Current=$CURRENT_COUNT"

# Search for the specific dashboard
EXPECTED_NAME="Weekly Marketing Review"
echo "Searching for dashboard: $EXPECTED_NAME"

# We select columns: iddashboard, name, layout (JSON)
# We filter by name case-insensitive
DASHBOARD_DATA=$(matomo_query "SELECT iddashboard, name, layout 
    FROM matomo_user_dashboard 
    WHERE LOWER(name)=LOWER('$EXPECTED_NAME') 
    ORDER BY iddashboard DESC LIMIT 1" 2>/dev/null)

FOUND="false"
DASH_ID=""
DASH_NAME=""
DASH_LAYOUT=""
IS_NEW="false"

if [ -n "$DASHBOARD_DATA" ]; then
    FOUND="true"
    DASH_ID=$(echo "$DASHBOARD_DATA" | cut -f1)
    DASH_NAME=$(echo "$DASHBOARD_DATA" | cut -f2)
    # The layout is JSON and might contain tabs/newlines, so we need to be careful with cut.
    # SQL output from matomo_query uses tab separation. 
    # Layout is the 3rd column.
    DASH_LAYOUT=$(echo "$DASHBOARD_DATA" | cut -f3-)

    echo "Dashboard Found! ID: $DASH_ID, Name: $DASH_NAME"
    
    # Check if it's a new dashboard (ID > Initial Max ID)
    if [ "$DASH_ID" -gt "$INITIAL_MAX_ID" ]; then
        IS_NEW="true"
        echo "Verified: Dashboard was created during this task (ID $DASH_ID > $INITIAL_MAX_ID)"
    else
        echo "Warning: Dashboard ID $DASH_ID <= Initial Max $INITIAL_MAX_ID. Likely pre-existing."
    fi
else
    echo "Dashboard not found in database."
fi

# Escape layout JSON for valid JSON output
# 1. Escape backslashes
# 2. Escape double quotes
DASH_LAYOUT_ESC=$(echo "$DASH_LAYOUT" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/ /g; s/\r//g; s/\n//g')
DASH_NAME_ESC=$(echo "$DASH_NAME" | sed 's/\\/\\\\/g; s/"/\\"/g')

# Create result JSON
TEMP_JSON=$(mktemp /tmp/dashboard_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "dashboard_found": $FOUND,
    "dashboard_is_new": $IS_NEW,
    "dashboard": {
        "id": "$DASH_ID",
        "name": "$DASH_NAME_ESC",
        "layout_json": "$DASH_LAYOUT_ESC"
    },
    "screenshot_path": "/tmp/task_final_screenshot.png",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Save result with permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/task_result.json"
echo "=== Export Complete ==="