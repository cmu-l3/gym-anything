#!/bin/bash
echo "=== Exporting upload_employee_profile_photos results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Check Database for Photos
# We need to verify that hs_hr_emp_picture has rows for James Carter and Linda Chen

check_photo() {
    local fname="$1"
    local lname="$2"
    
    # Get emp_number
    local emp_num
    emp_num=$(orangehrm_db_query "SELECT emp_number FROM hs_hr_employee WHERE emp_firstname='$fname' AND emp_lastname='$lname' AND purged_at IS NULL LIMIT 1;" 2>/dev/null | tr -d '[:space:]')
    
    if [ -z "$emp_num" ]; then
        echo "0 0" # Not found
        return
    fi
    
    # Check photo existence and size
    # Returns: count size
    orangehrm_db_query "SELECT COUNT(*), COALESCE(LENGTH(picture), 0) FROM hs_hr_emp_picture WHERE emp_number=$emp_num;" 2>/dev/null
}

read james_count james_size <<< $(check_photo "James" "Carter")
read linda_count linda_size <<< $(check_photo "Linda" "Chen")

echo "James Carter: Count=$james_count, Size=$james_size"
echo "Linda Chen: Count=$linda_count, Size=$linda_size"

# 3. Check App State
APP_RUNNING=$(pgrep -f "firefox" > /dev/null && echo "true" || echo "false")
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 4. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "james_carter": {
        "photo_exists": $([ "$james_count" -gt 0 ] && echo "true" || echo "false"),
        "photo_size_bytes": ${james_size:-0}
    },
    "linda_chen": {
        "photo_exists": $([ "$linda_count" -gt 0 ] && echo "true" || echo "false"),
        "photo_size_bytes": ${linda_size:-0}
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "=== Export complete ==="