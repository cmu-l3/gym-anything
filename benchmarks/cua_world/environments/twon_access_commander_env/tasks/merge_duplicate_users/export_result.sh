#!/bin/bash
echo "=== Exporting merge_duplicate_users result ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Authenticate
ac_login > /dev/null 2>&1

# 3. Dump the full user objects for anyone named "Zhang"
echo "Extracting Zhang records from API..."
ZHANG_USER_IDS=$(ac_api GET "/users" | jq -r '.[] | select(.lastName=="Zhang" or .lastName=="zhang") | .id' 2>/dev/null)

echo "[" > /tmp/zhang_users.json
FIRST="true"
for uid in $ZHANG_USER_IDS; do
    if [ "$FIRST" = "true" ]; then FIRST="false"; else echo "," >> /tmp/zhang_users.json; fi
    # Fetch full user details (which reliably includes nested credential data)
    ac_api GET "/users/$uid" >> /tmp/zhang_users.json
done
echo "]" >> /tmp/zhang_users.json

# 4. Gather system-wide stats
FINAL_COUNT=$(ac_api GET "/users" | jq 'length' 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_user_count.txt 2>/dev/null || echo "0")
START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 5. Check for the audit report
REPORT_PATH="/home/ga/Documents/merge_report.txt"
REPORT_EXISTS="false"
REPORT_MTIME=0

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    # Copy securely for the verifier to read
    cp "$REPORT_PATH" /tmp/merge_report.txt
    chmod 666 /tmp/merge_report.txt 2>/dev/null || true
fi

# 6. Build the metadata JSON
cat > /tmp/task_result.json << EOF
{
    "initial_user_count": $INITIAL_COUNT,
    "final_user_count": $FINAL_COUNT,
    "report_exists": $REPORT_EXISTS,
    "report_mtime": $REPORT_MTIME,
    "start_time": $START_TIME
}
EOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
chmod 666 /tmp/zhang_users.json 2>/dev/null || true

echo "=== Export complete ==="