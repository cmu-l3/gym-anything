#!/bin/bash
# Export results for "configure_silent_log_source_alert" task

echo "=== Exporting task results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# Take final screenshot for VLM verification
take_screenshot /tmp/task_final.png

# Capture Task Timing
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Query Database for the Alert Profile
# We query multiple potential tables since schemas can vary by version, 
# capturing as much info as possible to JSON.

echo "Querying database for created alert..."

# Helper to escape JSON strings
json_escape() {
    echo -n "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()).strip("\""))'
}

# 1. Query AlertProfile (Standard ELA table for profiles)
# Columns of interest: PROFILE_NAME, TIME_INTERVAL, TYPE, DESCRIPTION
DB_PROFILE_DATA=$(ela_db_query "SELECT PROFILE_NAME, TIME_INTERVAL, TYPE, DESCRIPTION FROM AlertProfile WHERE PROFILE_NAME = 'Critical_Log_Gap_Alert'")

# 2. Query Notification Profile (Email settings often linked)
# This is harder to join blindly, so we'll check if we can find the email in the Notification tables linked to this profile
# Often tables are AlertNotificationProfile or similar.
# For simplicity, we'll check matching strings in the relevant tables or text dump.
EMAIL_CHECK=$(ela_db_query "SELECT * FROM NotificationProfile WHERE PROFILE_NAME = 'Critical_Log_Gap_Alert' OR MAIL_TO LIKE '%soc_team@example.com%'" 2>/dev/null || echo "")

# 3. Alternative: LAAlertProfile (Log Analysis Alerts)
LA_PROFILE_DATA=$(ela_db_query "SELECT PROFILE_NAME, ALERT_INTERVAL FROM LAAlertProfile WHERE PROFILE_NAME = 'Critical_Log_Gap_Alert'" 2>/dev/null || echo "")

# Construct JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

# Parse DB output (pipe separated by ela_db_query)
# Format: PROFILE_NAME|TIME_INTERVAL|TYPE|DESCRIPTION
PROFILE_NAME=""
TIME_INTERVAL=""
TYPE=""

if [ -n "$DB_PROFILE_DATA" ]; then
    PROFILE_NAME=$(echo "$DB_PROFILE_DATA" | cut -d'|' -f1)
    TIME_INTERVAL=$(echo "$DB_PROFILE_DATA" | cut -d'|' -f2)
    TYPE=$(echo "$DB_PROFILE_DATA" | cut -d'|' -f3)
elif [ -n "$LA_PROFILE_DATA" ]; then
    PROFILE_NAME=$(echo "$LA_PROFILE_DATA" | cut -d'|' -f1)
    TIME_INTERVAL=$(echo "$LA_PROFILE_DATA" | cut -d'|' -f2)
fi

# Check if email is found in any config
EMAIL_FOUND="false"
if echo "$EMAIL_CHECK" | grep -q "soc_team@example.com"; then
    EMAIL_FOUND="true"
fi

cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "profile_found": $([ -n "$PROFILE_NAME" ] && echo "true" || echo "false"),
    "profile_name": "$(json_escape "$PROFILE_NAME")",
    "time_interval": "$(json_escape "$TIME_INTERVAL")",
    "profile_type": "$(json_escape "$TYPE")",
    "email_configured": $EMAIL_FOUND,
    "db_raw_profile": "$(json_escape "$DB_PROFILE_DATA")",
    "db_raw_la_profile": "$(json_escape "$LA_PROFILE_DATA")",
    "db_raw_email": "$(json_escape "$EMAIL_CHECK")"
}
EOF

# Save to final location
rm -f /tmp/task_result.json
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete. Result:"
cat /tmp/task_result.json