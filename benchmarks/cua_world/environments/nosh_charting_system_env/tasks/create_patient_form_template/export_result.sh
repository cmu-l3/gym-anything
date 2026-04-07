#!/bin/bash
echo "=== Exporting create_patient_form_template results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# ==============================================================================
# 1. Database Verification (The "Dump & Grep" Method)
# ==============================================================================
# Because custom form schemas vary wildly (EAV, JSON, separate tables), 
# dumping the DB and searching for the *structure* is the most robust 
# generic verification for "did the user create X".

echo "Dumping database to check for new form..."
DUMP_FILE="/tmp/nosh_final_dump.sql"
docker exec nosh-db mysqldump -uroot -prootpassword nosh --skip-extended-insert > "$DUMP_FILE" 2>/dev/null

# Check if the Form Title exists
FORM_FOUND="false"
FORM_CONTEXT=""

if grep -qi "COVID-19 Screening" "$DUMP_FILE"; then
    FORM_FOUND="true"
    # Extract 20 lines of context around the title to find fields
    FORM_CONTEXT=$(grep -C 20 -i "COVID-19 Screening" "$DUMP_FILE" | base64 -w 0)
    echo "Form title found in database."
else
    echo "Form title NOT found in database."
fi

# ==============================================================================
# 2. Application State Check
# ==============================================================================
APP_RUNNING="false"
if pgrep -f firefox > /dev/null; then
    APP_RUNNING="true"
fi

# ==============================================================================
# 3. Evidence Collection
# ==============================================================================
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# ==============================================================================
# 4. JSON Export
# ==============================================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "form_found": $FORM_FOUND,
    "form_context_base64": "$FORM_CONTEXT",
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location with permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete. Result saved to /tmp/task_result.json"