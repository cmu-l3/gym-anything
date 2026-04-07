#!/bin/bash
set -euo pipefail

echo "=== Setting up review_activity_logs task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task start time
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Ensure SEB Server is accessible
wait_for_seb_server 120

# Clean up stale temp files
rm -f /home/ga/Documents/activity_audit.txt 2>/dev/null || true
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# ============================================================
# Generate known activity log entries via API
# ============================================================
echo "=== Generating known activity log entries ==="

# Get OAuth token
TOKEN_RESPONSE=$(curl -s -X POST "http://localhost:8080/oauth/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "grant_type=password&username=super-admin&password=admin&client_id=guiClient&client_secret=somePW" \
    2>/dev/null || echo "{}")

ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('access_token',''))" 2>/dev/null || echo "")

if [ -n "$ACCESS_TOKEN" ]; then
    echo "Got API access token. Generating activities..."

    # CREATE action (Exam Configuration)
    curl -s -X POST "http://localhost:8080/admin-api/v1/exam-configuration" \
        -H "Authorization: Bearer $ACCESS_TOKEN" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "name=AuditTestConfig&description=Created+for+audit+verification&institutionId=1" \
        2>/dev/null || true
    sleep 1

    # MODIFY action (Institution)
    curl -s -X PUT "http://localhost:8080/admin-api/v1/institution/1" \
        -H "Authorization: Bearer $ACCESS_TOKEN" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "name=State+University&urlSuffix=state-uni" \
        2>/dev/null || true
    sleep 1

    # CREATE action (User)
    curl -s -X POST "http://localhost:8080/admin-api/v1/useraccount" \
        -H "Authorization: Bearer $ACCESS_TOKEN" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "name=audit-test-user&surname=AuditUser&username=audituser&newPassword=TestPass123!&email=audit@example.com&language=en&timezone=UTC&roles=EXAM_SUPPORTER&institutionId=1" \
        2>/dev/null || true
    sleep 2

    echo "API activity generation complete."
else
    echo "WARNING: Could not get API token, proceeding with existing log data."
fi

# ============================================================
# Record ground truth from database
# ============================================================
echo "=== Recording ground truth ==="
sleep 3

# Try to find the exact log table SEB uses
LOG_TABLE=$(docker exec seb-server-mariadb mysql -u root -psebserver123 SEBServer -N -e "SHOW TABLES LIKE '%log%';" 2>/dev/null | grep -E "user_log|activity_log" | head -n 1 || echo "user_log")
if [ -z "$LOG_TABLE" ]; then LOG_TABLE="user_log"; fi

TOTAL_ACTIVITIES=$(docker exec seb-server-mariadb mysql -u root -psebserver123 SEBServer -N -e "SELECT COUNT(*) FROM $LOG_TABLE;" 2>/dev/null | tr -d '[:space:]' || echo "0")

# Determine column name for action/type
COL_NAME=$(docker exec seb-server-mariadb mysql -u root -psebserver123 SEBServer -N -e "SHOW COLUMNS FROM $LOG_TABLE;" 2>/dev/null | grep -iE "action|type|activity" | awk '{print $1}' | head -n 1 || echo "action_type")

CREATE_COUNT=$(docker exec seb-server-mariadb mysql -u root -psebserver123 SEBServer -N -e "SELECT COUNT(*) FROM $LOG_TABLE WHERE $COL_NAME='CREATE';" 2>/dev/null | tr -d '[:space:]' || echo "0")
MODIFY_COUNT=$(docker exec seb-server-mariadb mysql -u root -psebserver123 SEBServer -N -e "SELECT COUNT(*) FROM $LOG_TABLE WHERE $COL_NAME='MODIFY' OR $COL_NAME='UPDATE';" 2>/dev/null | tr -d '[:space:]' || echo "0")

# Store ground truth
cat > /tmp/ground_truth_activity.json << EOF
{
    "total_activities": ${TOTAL_ACTIVITIES:-0},
    "create_count": ${CREATE_COUNT:-0},
    "modify_count": ${MODIFY_COUNT:-0},
    "table_used": "$LOG_TABLE",
    "col_used": "$COL_NAME",
    "recorded_at": "$(date -Iseconds)"
}
EOF
chmod 644 /tmp/ground_truth_activity.json

echo "Ground truth recorded: total=$TOTAL_ACTIVITIES, create=$CREATE_COUNT, modify=$MODIFY_COUNT"

# ============================================================
# Launch Firefox
# ============================================================
launch_firefox "http://localhost:8080"
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="