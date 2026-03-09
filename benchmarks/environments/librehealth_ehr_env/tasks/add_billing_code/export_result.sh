#!/bin/bash
echo "=== Exporting Add Billing Code Result ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Get Task Metadata
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_cpt4_count 2>/dev/null || echo "0")
TARGET_CODE="99458"

# 3. Query Database for the specific code
# We join with code_types to verify the type is CPT4
# We use JSON_OBJECT (if available in MariaDB 10.2+) or construct JSON manually if older.
# LibreHealth/OpenEMR usually runs on MariaDB. We'll output raw fields and construct JSON in bash to be safe.

# Query fields: code, fee, code_text, active, code_type_key
DB_RESULT=$(librehealth_query "SELECT c.code, c.fee, c.code_text, c.active, ct.ct_key 
FROM codes c 
LEFT JOIN code_types ct ON c.code_type = ct.ct_id 
WHERE c.code = '$TARGET_CODE'" 2>/dev/null)

# Query final count
FINAL_COUNT=$(librehealth_query "SELECT COUNT(*) FROM codes c JOIN code_types ct ON c.code_type = ct.ct_id WHERE ct.ct_key = 'CPT4'" 2>/dev/null || echo "0")

# 4. Parse DB Result
CODE_EXISTS="false"
ACTUAL_CODE=""
ACTUAL_FEE="0"
ACTUAL_TEXT=""
ACTUAL_ACTIVE="0"
ACTUAL_TYPE=""

if [ -n "$DB_RESULT" ]; then
    CODE_EXISTS="true"
    # Read tab-separated values
    read -r ACTUAL_CODE ACTUAL_FEE ACTUAL_TEXT ACTUAL_ACTIVE ACTUAL_TYPE <<< "$DB_RESULT"
fi

# 5. Check if application was running
APP_RUNNING=$(pgrep -f "firefox" > /dev/null && echo "true" || echo "false")

# 6. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_timestamp": $TASK_START,
    "initial_cpt4_count": $INITIAL_COUNT,
    "final_cpt4_count": $FINAL_COUNT,
    "code_exists": $CODE_EXISTS,
    "actual_code": "$ACTUAL_CODE",
    "actual_fee": "$ACTUAL_FEE",
    "actual_text": "$(echo $ACTUAL_TEXT | sed 's/"/\\"/g')",
    "actual_active": "$ACTUAL_ACTIVE",
    "actual_type": "$ACTUAL_TYPE",
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 7. Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="