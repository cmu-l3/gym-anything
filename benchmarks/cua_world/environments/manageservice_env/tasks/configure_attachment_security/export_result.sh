#!/bin/bash
# Export script for "configure_attachment_security" task
# Queries SDP database for security settings and exports to JSON.

set -e
echo "=== Exporting Configure Attachment Security results ==="

source /workspace/scripts/task_utils.sh

# 1. Record timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 2. Take final screenshot (evidence of UI state)
take_screenshot /tmp/task_final.png

# 3. Query Database for Security Configuration
# SDP stores these settings in GlobalConfig or distinct Security tables depending on version.
# We query broad patterns to catch the setting.
echo "Querying database for attachment settings..."

# Query 1: GlobalConfig (Common for system settings)
# We look for params like 'RestrictedExtensions', 'BlockedFileTypes', 'SecuritySettings'
DB_CONFIG_DUMP=$(sdp_db_exec "SELECT paramname, paramvalue FROM globalconfig WHERE category LIKE '%Security%' OR paramname LIKE '%Attachment%' OR paramname LIKE '%Extension%' OR paramname LIKE '%File%';" 2>/dev/null)

# Query 2: FileTypeDefinition or similar (if exists)
DB_FILETYPES=$(sdp_db_exec "SELECT * FROM filetypedefinition;" 2>/dev/null || echo "")

# 4. Check if we found the relevant extensions in the DB dump
# We grep for them to flag existence in the raw dump
FOUND_EXE="false"
FOUND_BAT="false"
FOUND_SH="false"

if echo "$DB_CONFIG_DUMP" | grep -iq "exe"; then FOUND_EXE="true"; fi
if echo "$DB_CONFIG_DUMP" | grep -iq "bat"; then FOUND_BAT="true"; fi
if echo "$DB_CONFIG_DUMP" | grep -iq "sh"; then FOUND_SH="true"; fi

# 5. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "db_config_dump": $(echo "$DB_CONFIG_DUMP" | jq -R -s '.' 2>/dev/null || echo "\"$DB_CONFIG_DUMP\""),
    "found_exe_in_db": $FOUND_EXE,
    "found_bat_in_db": $FOUND_BAT,
    "found_sh_in_db": $FOUND_SH,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 6. Save result with permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="