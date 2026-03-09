#!/bin/bash
echo "=== Exporting Configure Automated Report Schedule results ==="

source /workspace/scripts/task_utils.sh

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Query System Settings for enabled status
# Returns "1" or "0"
SYSTEM_SETTING_ENABLED=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -N -s -e \
    "SELECT enable_scheduled_reports FROM system_settings LIMIT 1;" 2>/dev/null || echo "0")

# Query the specific scheduled report
# We output as JSON-like string lines to parse in Python later, or just raw fields
# Fields: report_id, run_time, email_to, report_id, notes, email_subject
REPORT_DATA=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -N -s -e \
    "SELECT report_id, run_time, email_to, notes, email_subject FROM vicidial_scheduled_reports WHERE scheduled_id='DAILY_LOG' LIMIT 1;" 2>/dev/null || echo "")

# Parse the MySQL output (tab separated)
# If empty, the record doesn't exist
REPORT_EXISTS="false"
REPORT_ID=""
RUN_TIME=""
EMAIL_TO=""
NOTES=""
EMAIL_SUBJECT=""

if [ -n "$REPORT_DATA" ]; then
    REPORT_EXISTS="true"
    REPORT_ID=$(echo "$REPORT_DATA" | awk -F'\t' '{print $1}')
    RUN_TIME=$(echo "$REPORT_DATA" | awk -F'\t' '{print $2}')
    EMAIL_TO=$(echo "$REPORT_DATA" | awk -F'\t' '{print $3}')
    NOTES=$(echo "$REPORT_DATA" | awk -F'\t' '{print $4}')
    EMAIL_SUBJECT=$(echo "$REPORT_DATA" | awk -F'\t' '{print $5}')
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "system_setting_enabled": "$SYSTEM_SETTING_ENABLED",
    "report_exists": $REPORT_EXISTS,
    "report_data": {
        "report_id": "$REPORT_ID",
        "run_time": "$RUN_TIME",
        "email_to": "$EMAIL_TO",
        "notes": "$NOTES",
        "email_subject": "$EMAIL_SUBJECT"
    },
    "timestamp": "$(date +%s)"
}
EOF

# Move to safe location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json