#!/bin/bash
echo "=== Exporting update_org_branding results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Query Database for Organization Details
echo "Querying OrganizationDetails table..."
# We fetch specific columns to make parsing easier: Name, Address, Email, Phone, LogoName
DB_RESULT=$(sdp_db_exec "SELECT organizationname, address, email, phone, logoname FROM organizationdetails LIMIT 1;" 2>/dev/null)
echo "DB Result: $DB_RESULT"

# 2. Check for Logo File Update
# SDP usually stores custom logos in [SDP_HOME]/custom/images or [SDP_HOME]/webapps/ManageEngine/images
# We check if a new file was created in likely directories after task start
LOGO_DIR_1="/opt/ManageEngine/ServiceDesk/custom/images"
LOGO_DIR_2="/opt/ManageEngine/ServiceDesk/webapps/ManageEngine/images"

NEW_LOGO_FOUND="false"
NEW_LOGO_FILE=""

# Find files modified/created after task start
if [ -d "$LOGO_DIR_1" ]; then
    FOUND=$(find "$LOGO_DIR_1" -type f -newermt "@$TASK_START" 2>/dev/null | head -n 1)
    if [ -n "$FOUND" ]; then
        NEW_LOGO_FOUND="true"
        NEW_LOGO_FILE="$FOUND"
    fi
fi

if [ "$NEW_LOGO_FOUND" = "false" ] && [ -d "$LOGO_DIR_2" ]; then
    FOUND=$(find "$LOGO_DIR_2" -type f -newermt "@$TASK_START" 2>/dev/null | head -n 1)
    if [ -n "$FOUND" ]; then
        NEW_LOGO_FOUND="true"
        NEW_LOGO_FILE="$FOUND"
    fi
fi

# 3. Capture final screenshot
take_screenshot /tmp/task_final.png

# 4. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "db_record_raw": "$(echo "$DB_RESULT" | sed 's/"/\\"/g')",
    "new_logo_file_found": $NEW_LOGO_FOUND,
    "new_logo_path": "$NEW_LOGO_FILE",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="