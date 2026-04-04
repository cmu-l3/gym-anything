#!/bin/bash
set -e
echo "=== Exporting task results: create_business_continuity_plan ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Gather Task Information
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_bc_count.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Convert task start to MySQL format for query comparison
TASK_START_MYSQL=$(date -d "@$TASK_START" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "2020-01-01 00:00:00")

# 3. Query Database for Evidence

# Check 1: Record Count
FINAL_COUNT=$(docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e "SELECT COUNT(*) FROM business_continuities;" 2>/dev/null || echo "0")

# Check 2: Get the specific record if it exists
# We look for records created after task start to avoid picking up old data
# We select relevant fields for verification
RECORD_JSON=$(docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -e "
SELECT title, description, created, modified, deleted 
FROM business_continuities 
WHERE created >= '$TASK_START_MYSQL' 
  AND (title LIKE '%Data Center Outage%' OR title LIKE '%Core Operations%')
ORDER BY created DESC LIMIT 1;" -B -r | \
python3 -c '
import sys, json, csv
reader = csv.DictReader(sys.stdin, delimiter="\t")
rows = list(reader)
print(json.dumps(rows[0] if rows else None))
' 2>/dev/null || echo "null")

# 4. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_count": $INITIAL_COUNT,
    "final_count": $FINAL_COUNT,
    "record_found": $RECORD_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 5. Save to final location with proper permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="