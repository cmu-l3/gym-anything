#!/bin/bash
# Export script for Install eForm Template task
set -e

echo "=== Exporting Install eForm Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Get Task Start Time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_eform_count.txt 2>/dev/null || echo "0")

# 3. Query Database for the uploaded eForm
# We look for the most recently created form with the specific name
echo "Querying database for 'Rapid Pain Assessment'..."

# Get ID, Status, Created Date
FORM_INFO=$(oscar_query "SELECT fid, status, fdid, form_name FROM eform WHERE form_name='Rapid Pain Assessment' ORDER BY fid DESC LIMIT 1" 2>/dev/null)

FORM_FOUND="false"
FORM_ID=""
FORM_STATUS=""
SECURE_CHECK_FOUND="false"
CONTENT_SNIPPET=""

if [ -n "$FORM_INFO" ]; then
    FORM_FOUND="true"
    FORM_ID=$(echo "$FORM_INFO" | awk '{print $1}')
    FORM_STATUS=$(echo "$FORM_INFO" | awk '{print $2}')
    
    echo "Form found! ID: $FORM_ID, Status: $FORM_STATUS"
    
    # Check the content of the form body for our secure string
    # We use a separate query because the body can be large
    # 'RPA_2024_SECURE_CHECK' was embedded in the setup script
    CHECK_CONTENT=$(oscar_query "SELECT COUNT(*) FROM eform WHERE fid='$FORM_ID' AND form_body LIKE '%RPA_2024_SECURE_CHECK%'" 2>/dev/null || echo "0")
    
    if [ "$CHECK_CONTENT" -gt "0" ]; then
        SECURE_CHECK_FOUND="true"
        echo "Secure content verification string found in form body."
    else
        echo "WARNING: Secure content verification string NOT found."
        # Grab a snippet for debugging (first 100 chars)
        CONTENT_SNIPPET=$(oscar_query "SELECT LEFT(form_body, 100) FROM eform WHERE fid='$FORM_ID'" 2>/dev/null)
    fi
else
    echo "Form 'Rapid Pain Assessment' not found in database."
fi

# 4. Get Final Count (Anti-gaming check)
FINAL_COUNT=$(oscar_query "SELECT COUNT(*) FROM eform" 2>/dev/null || echo "0")

# 5. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "initial_count": $INITIAL_COUNT,
    "final_count": $FINAL_COUNT,
    "form_found": $FORM_FOUND,
    "form_id": "${FORM_ID:-0}",
    "form_status": "${FORM_STATUS:-0}",
    "secure_content_verified": $SECURE_CHECK_FOUND,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="