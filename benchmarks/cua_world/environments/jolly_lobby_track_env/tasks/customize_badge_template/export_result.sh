#!/bin/bash
echo "=== Exporting customize_badge_template results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
RESULT_JSON="/tmp/task_result.json"

# 1. Capture Final Screenshot (Evidence of state)
take_screenshot /tmp/task_final.png

# 2. Check for User's Screenshot (Evidence of completion)
USER_SCREENSHOT="/home/ga/Documents/badge_template_screenshot.png"
SCREENSHOT_EXISTS="false"
SCREENSHOT_VALID="false"

if [ -f "$USER_SCREENSHOT" ]; then
    SCREENSHOT_EXISTS="true"
    # Check timestamp
    SS_MTIME=$(stat -c %Y "$USER_SCREENSHOT" 2>/dev/null || echo "0")
    # Check size (> 5KB)
    SS_SIZE=$(stat -c %s "$USER_SCREENSHOT" 2>/dev/null || echo "0")
    
    if [ "$SS_MTIME" -gt "$TASK_START" ] && [ "$SS_SIZE" -gt 5000 ]; then
        SCREENSHOT_VALID="true"
    fi
fi

# 3. Check for Modified/Created Template Files
# This proves the agent actually saved changes in the software
TEMPLATE_MODIFIED="false"
MODIFIED_FILES=""
FOUND_STRINGS_VISITOR="false"
FOUND_STRINGS_TECHVISION="false"

# Search for relevant extensions modified after task start
# We scan the whole drive_c because save location can vary
find /home/ga/.wine/drive_c -type f \( -iname "*.btf" -o -iname "*.bdg" -o -iname "*.badge" -o -iname "*.xml" -o -iname "*.btp" \) -newermt "@$TASK_START" 2>/dev/null > /tmp/modified_templates.txt || true

if [ -s /tmp/modified_templates.txt ]; then
    TEMPLATE_MODIFIED="true"
    MODIFIED_FILES=$(cat /tmp/modified_templates.txt | tr '\n' ',' | sed 's/,$//')
    
    # 4. Content Verification (Grepping binary/xml files for strings)
    # Note: .btf files might be binary, but often contain plain text strings for fields
    while IFS= read -r file; do
        if grep -ia "VISITOR PASS" "$file" >/dev/null; then
            FOUND_STRINGS_VISITOR="true"
        fi
        if grep -ia "TechVision" "$file" >/dev/null; then
            FOUND_STRINGS_TECHVISION="true"
        fi
    done < /tmp/modified_templates.txt
fi

# 5. Check if App is still running
APP_RUNNING="false"
if pgrep -f "LobbyTrack" >/dev/null || pgrep -f "Lobby" >/dev/null; then
    APP_RUNNING="true"
fi

# Create JSON Result
cat > "$RESULT_JSON" << EOF
{
    "task_start": $TASK_START,
    "user_screenshot_exists": $SCREENSHOT_EXISTS,
    "user_screenshot_valid": $SCREENSHOT_VALID,
    "template_modified": $TEMPLATE_MODIFIED,
    "modified_files": "$MODIFIED_FILES",
    "found_visitor_pass_string": $FOUND_STRINGS_VISITOR,
    "found_techvision_string": $FOUND_STRINGS_TECHVISION,
    "app_running": $APP_RUNNING
}
EOF

# Ensure permissions
chmod 666 "$RESULT_JSON" 2>/dev/null || true

echo "Export complete. Result:"
cat "$RESULT_JSON"