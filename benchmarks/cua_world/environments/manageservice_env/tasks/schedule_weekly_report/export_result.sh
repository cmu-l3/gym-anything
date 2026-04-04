#!/bin/bash
# Export script for "schedule_weekly_report" task
# verification strategy:
# 1. Capture final screenshot for VLM.
# 2. Query SDP database for the created schedule record.

echo "=== Exporting Schedule Weekly Report Result ==="
source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# 1. Capture final state screenshot
take_screenshot /tmp/task_final.png

# 2. Query Database for Verification
# We need to check if a schedule with the specific name and recipient exists.
# Note: Table names in SDP are generally lowercase in Postgres.

# Query for the specific schedule task by name
# We select columns that might exist (schema varies slightly by version, so we cast wide net)
# Typical tables: reportscheduletask (holds name), reportschedule_email (holds recipient)

echo "Querying database for schedule..."

# Check for the Schedule Task
SCHEDULE_TASK_JSON=$(sdp_db_exec "
    SELECT row_to_json(t) FROM (
        SELECT schedule_name, report_format, description 
        FROM reportscheduletask 
        WHERE schedule_name = 'Weekly Executive Summary'
    ) t;
" 2>/dev/null || echo "")

# Check for the Email Recipient linked to this task
# Since joining is complex without exact schema knowledge, we query for the email separately
# to confirm it exists in the email schedule table.
EMAIL_CONFIG_JSON=$(sdp_db_exec "
    SELECT row_to_json(e) FROM (
        SELECT mail_to, subject, content 
        FROM reportschedule_email 
        WHERE mail_to LIKE '%director@example.com%' 
        ORDER BY created_time DESC LIMIT 1
    ) e;
" 2>/dev/null || echo "")

# Get current total count
CURRENT_COUNT=$(sdp_db_exec "SELECT COUNT(*) FROM reportscheduletask;" 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_schedule_count.txt 2>/dev/null || echo "0")

# 3. Construct Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $(cat /tmp/task_start_time.txt 2>/dev/null || echo 0),
    "export_time": $(date +%s),
    "initial_count": ${INITIAL_COUNT:-0},
    "current_count": ${CURRENT_COUNT:-0},
    "schedule_task_found": $([ -n "$SCHEDULE_TASK_JSON" ] && echo "true" || echo "false"),
    "schedule_task_data": ${SCHEDULE_TASK_JSON:-null},
    "email_config_found": $([ -n "$EMAIL_CONFIG_JSON" ] && echo "true" || echo "false"),
    "email_config_data": ${EMAIL_CONFIG_JSON:-null},
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 4. Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="