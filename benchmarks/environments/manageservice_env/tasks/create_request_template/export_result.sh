#!/bin/bash
# Export script for "create_request_template" task
# Queries the SDP database for the created template and exports details.

set -e
source /workspace/scripts/task_utils.sh

echo "=== Exporting task results ==="

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Get verification data
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_template_count.txt 2>/dev/null || echo "0")
FINAL_COUNT=$(sdp_db_exec "SELECT COUNT(*) FROM requesttemplate WHERE isdeleted=false;" 2>/dev/null || echo "0")

# 3. Search for the specific template by name
# We look for the most recently created one matching the name
TEMPLATE_NAME="Network Outage Report"
echo "Searching for template: $TEMPLATE_NAME"

# Get Template ID
TEMPLATE_ID=$(sdp_db_exec "SELECT templateid FROM requesttemplate WHERE templatename ILIKE '$TEMPLATE_NAME' AND isdeleted=false ORDER BY templateid DESC LIMIT 1;" 2>/dev/null || echo "")

TEMPLATE_FOUND="false"
TEMPLATE_SUBJECT=""
TEMPLATE_DESC=""
PRIORITY_NAME=""
CATEGORY_NAME=""

if [ -n "$TEMPLATE_ID" ]; then
    TEMPLATE_FOUND="true"
    echo "Found Template ID: $TEMPLATE_ID"

    # Extract Subject (often in 'subject' or 'templatename' depending on version, sometimes separate column)
    # We try standard columns. Note: 'description' might be in a separate definition table in some versions, 
    # but 'requesttemplate' usually has the basics.
    
    # Get raw row data for description and subject
    # We use '|' as delimiter to avoid issues with text content
    TEMPLATE_DATA=$(sdp_db_exec "SELECT subject || '|' || description FROM requesttemplate WHERE templateid=$TEMPLATE_ID;" 2>/dev/null || echo "")
    
    TEMPLATE_SUBJECT=$(echo "$TEMPLATE_DATA" | awk -F'|' '{print $1}')
    TEMPLATE_DESC=$(echo "$TEMPLATE_DATA" | awk -F'|' '{print $2}')
    
    # Try to find default values (Priority, Category)
    # These are often stored in 'requesttemplatedefault' or 'workorder' (as a template instance)
    # We will try to join with prioritydefinition and categorydefinition if possible, 
    # or just dump the default value IDs and look them up.
    
    # Attempt to find priority ID linked to this template
    # This query assumes a standard SDP schema structure for defaults
    PRIORITY_ID=$(sdp_db_exec "SELECT priorityid FROM requesttemplatedefault WHERE templateid=$TEMPLATE_ID LIMIT 1;" 2>/dev/null || echo "")
    if [ -n "$PRIORITY_ID" ] && [ "$PRIORITY_ID" != "0" ]; then
        PRIORITY_NAME=$(sdp_db_exec "SELECT priorityname FROM prioritydefinition WHERE priorityid=$PRIORITY_ID;" 2>/dev/null || echo "")
    fi
    
    CATEGORY_ID=$(sdp_db_exec "SELECT categoryid FROM requesttemplatedefault WHERE templateid=$TEMPLATE_ID LIMIT 1;" 2>/dev/null || echo "")
    if [ -n "$CATEGORY_ID" ] && [ "$CATEGORY_ID" != "0" ]; then
        CATEGORY_NAME=$(sdp_db_exec "SELECT categoryname FROM categorydefinition WHERE categoryid=$CATEGORY_ID;" 2>/dev/null || echo "")
    fi
else
    echo "Template not found in database."
fi

# 4. Check if app was running
APP_RUNNING="false"
if pgrep -f "wrapper" >/dev/null || pgrep -f "java" >/dev/null; then
    APP_RUNNING="true"
fi

# 5. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "initial_count": $INITIAL_COUNT,
    "final_count": $FINAL_COUNT,
    "template_found": $TEMPLATE_FOUND,
    "template_id": "$TEMPLATE_ID",
    "template_name": "$TEMPLATE_NAME",
    "actual_subject": $(echo "$TEMPLATE_SUBJECT" | jq -R .),
    "actual_description": $(echo "$TEMPLATE_DESC" | jq -R .),
    "actual_priority": "$PRIORITY_NAME",
    "actual_category": "$CATEGORY_NAME",
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 6. Save result safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="