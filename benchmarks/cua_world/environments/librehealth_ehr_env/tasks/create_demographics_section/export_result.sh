#!/bin/bash
echo "=== Exporting Create Demographics Section Results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# --- Database Verification ---

# 1. Check if Group 'RPM' exists in demographics (form_id='DEM')
# layout_group_properties: grp_id, form_id, grp_title
GRP_INFO=$(librehealth_query "SELECT grp_id, grp_title FROM layout_group_properties WHERE grp_title = 'RPM' AND form_id = 'DEM' LIMIT 1" 2>/dev/null)
GRP_ID=$(echo "$GRP_INFO" | awk '{print $1}')
GRP_TITLE=$(echo "$GRP_INFO" | awk '{$1=""; print $0}' | sed 's/^[ \t]*//')

if [ -n "$GRP_ID" ]; then
    GROUP_FOUND="true"
else
    GROUP_FOUND="false"
fi

# 2. Check if Field 'rpm_device_serial' exists
# layout_options: field_id, form_id, title, group_id, data_type
# Note: field_id is usually the column name in the form table
FIELD_INFO=$(librehealth_query "SELECT field_id, title, group_id, data_type FROM layout_options WHERE (field_id = 'rpm_device_serial' OR title = 'Device Serial Number') AND form_id = 'DEM' LIMIT 1" 2>/dev/null)
FIELD_ID_FOUND=$(echo "$FIELD_INFO" | awk '{print $1}')
FIELD_TITLE_FOUND=$(echo "$FIELD_INFO" | awk '{print $2, $3, $4}' | sed 's/[0-9]*$//' | sed 's/[ \t]*$//') # rough parsing
FIELD_GRP_ID=$(echo "$FIELD_INFO" | awk '{print $(NF-1)}')
FIELD_DATA_TYPE=$(echo "$FIELD_INFO" | awk '{print $NF}')

if [ -n "$FIELD_ID_FOUND" ]; then
    FIELD_FOUND="true"
else
    FIELD_FOUND="false"
fi

# 3. Check linkage
FIELD_IN_CORRECT_GROUP="false"
if [ "$GROUP_FOUND" = "true" ] && [ "$FIELD_FOUND" = "true" ]; then
    if [ "$GRP_ID" = "$FIELD_GRP_ID" ]; then
        FIELD_IN_CORRECT_GROUP="true"
    fi
fi

# 4. Check Data Type (1 is usually Text/String in OpenEMR/LibreHealth layouts)
# 1 = Text, 2 = Textbox, 3 = Date, etc.
FIELD_TYPE_CORRECT="false"
if [ "$FIELD_DATA_TYPE" = "1" ] || [ "$FIELD_DATA_TYPE" = "2" ]; then
    FIELD_TYPE_CORRECT="true"
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "group_found": $GROUP_FOUND,
    "group_id": "$GRP_ID",
    "group_title": "$GRP_TITLE",
    "field_found": $FIELD_FOUND,
    "field_id": "$FIELD_ID_FOUND",
    "field_title": "$FIELD_TITLE_FOUND",
    "field_in_correct_group": $FIELD_IN_CORRECT_GROUP,
    "field_data_type": "$FIELD_DATA_TYPE",
    "field_type_correct": $FIELD_TYPE_CORRECT,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="