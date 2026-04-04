#!/bin/bash
echo "=== Exporting record_compliance_effectiveness result ==="

# Source utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Query the Database for the result
echo "Querying database..."
# We join tables to ensure we get the correct item
# We fetch: status, findings, next_review, modified timestamp
SQL_QUERY="SELECT ca.compliance_status, ca.findings, ca.next_review, UNIX_TIMESTAMP(ca.modified) \
           FROM compliance_analysis ca \
           JOIN compliance_package_items cpi ON ca.compliance_package_item_id = cpi.id \
           WHERE cpi.name = 'A.11.2.8 Clear Desk and Clear Screen' \
           LIMIT 1;"

DB_RESULT=$(docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e "$SQL_QUERY" 2>/dev/null)

# Parse result (tab separated)
# Example output: 1    Verified GPO...    2026-06-30    170928392
STATUS=$(echo "$DB_RESULT" | cut -f1)
FINDINGS=$(echo "$DB_RESULT" | cut -f2)
REVIEW_DATE=$(echo "$DB_RESULT" | cut -f3)
MODIFIED_TS=$(echo "$DB_RESULT" | cut -f4)

# 3. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
jq -n \
    --arg status "$STATUS" \
    --arg findings "$FINDINGS" \
    --arg review_date "$REVIEW_DATE" \
    --arg modified_ts "$MODIFIED_TS" \
    --arg task_start "$TASK_START" \
    --arg task_end "$TASK_END" \
    '{
        status: $status,
        findings: $findings,
        review_date: $review_date,
        modified_timestamp: $modified_ts,
        task_start_time: $task_start,
        task_end_time: $task_end,
        screenshot_path: "/tmp/task_final.png"
    }' > "$TEMP_JSON"

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete. Result:"
cat /tmp/task_result.json