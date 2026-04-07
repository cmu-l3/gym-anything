#!/bin/bash
echo "=== Exporting assign_study_role result ==="

source /workspace/scripts/task_utils.sh

# Capture final visual evidence
take_screenshot /tmp/task_end_screenshot.png 2>/dev/null || true

# Safely extract variables
CV_STUDY_ID=$(cat /tmp/target_study_id.txt 2>/dev/null || oc_query "SELECT study_id FROM study WHERE unique_identifier = 'CV-REG-2023' LIMIT 1")
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
AUDIT_LOG_COUNT=$(get_recent_audit_count 60 2>/dev/null || echo "0")
AUDIT_BASELINE_COUNT=$(cat /tmp/audit_baseline_count 2>/dev/null || echo "0")
NONCE=$(cat /tmp/result_nonce 2>/dev/null || echo "")

# Query the user role assignments directly from the database
ROLE_DATA=$(oc_query "SELECT role_name, status_id, EXTRACT(EPOCH FROM date_created)::bigint FROM study_user_role WHERE user_name = 'monitor_user' AND study_id = $CV_STUDY_ID ORDER BY study_user_role_id DESC LIMIT 1" 2>/dev/null || echo "")

ROLE_EXISTS="false"
ROLE_NAME=""
STATUS_ID=0
DATE_CREATED=0

if [ -n "$ROLE_DATA" ]; then
    ROLE_EXISTS="true"
    ROLE_NAME=$(echo "$ROLE_DATA" | cut -d'|' -f1)
    STATUS_ID=$(echo "$ROLE_DATA" | cut -d'|' -f2)
    DATE_CREATED=$(echo "$ROLE_DATA" | cut -d'|' -f3)
fi

# Optional JSON escape fallback if not in task_utils
json_escape() { echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g' | tr -d '\n' | tr -d '\r'; }

# Create robust JSON payload via temp file
TEMP_JSON=$(mktemp /tmp/assign_study_role_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "role_exists": $ROLE_EXISTS,
    "role_name": "$(json_escape "${ROLE_NAME:-}")",
    "status_id": ${STATUS_ID:-0},
    "date_created": ${DATE_CREATED:-0},
    "task_start_time": ${TASK_START_TIME:-0},
    "audit_log_count": ${AUDIT_LOG_COUNT:-0},
    "audit_baseline_count": ${AUDIT_BASELINE_COUNT:-0},
    "result_nonce": "$NONCE"
}
EOF

# Carefully move json out, managing permissions
rm -f /tmp/assign_study_role_result.json 2>/dev/null || sudo rm -f /tmp/assign_study_role_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/assign_study_role_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/assign_study_role_result.json
chmod 666 /tmp/assign_study_role_result.json 2>/dev/null || sudo chmod 666 /tmp/assign_study_role_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "=== Export complete ==="