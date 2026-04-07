#!/bin/bash
echo "=== Exporting Task Results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

REPORT_PATH="/home/ga/invalid_phones.csv"

# 1. check report file
REPORT_EXISTS="false"
REPORT_CREATED_DURING_TASK="false"
REPORT_CONTENT=""
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_CREATED_DURING_TASK="true"
    fi
    # Read first 10 lines of report for verification
    REPORT_CONTENT=$(head -n 10 "$REPORT_PATH" | base64 -w 0)
fi

# 2. Database State Verification (Run Queries)

# Check for remaining separators (Should be 0)
REMAINING_SEPARATORS=$(mysql -u root DrTuxTest -N -e "SELECT COUNT(*) FROM fchpat WHERE FchPat_Tel1 LIKE '% %' OR FchPat_Tel1 LIKE '%.%' OR FchPat_Tel1 LIKE '%-%' OR FchPat_Tel1 LIKE '%/%'" 2>/dev/null || echo "ERROR")

# Check for valid 10-digit numbers
CURRENT_VALID_COUNT=$(mysql -u root DrTuxTest -N -e "SELECT COUNT(*) FROM fchpat WHERE FchPat_Tel1 REGEXP '^[0-9]{10}$'" 2>/dev/null || echo "0")

# Check specific test cases to verify transformation logic
# We select the GUID and the current phone value
TEST_CASES_JSON=$(mysql -u root DrTuxTest -N -e "SELECT FchPat_GUID_Doss, FchPat_Tel1 FROM fchpat WHERE FchPat_GUID_Doss LIKE 'TEST-GUID-%'" | \
    python3 -c '
import sys, json
results = {}
for line in sys.stdin:
    parts = line.strip().split("\t")
    if len(parts) >= 2:
        results[parts[0]] = parts[1]
print(json.dumps(results))
')

# 3. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "report_exists": $REPORT_EXISTS,
    "report_created_during_task": $REPORT_CREATED_DURING_TASK,
    "report_content_base64": "$REPORT_CONTENT",
    "db_state": {
        "remaining_separators": $REMAINING_SEPARATORS,
        "valid_10digit_count": $CURRENT_VALID_COUNT
    },
    "test_cases": $TEST_CASES_JSON
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

# Final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

echo "Result exported to /tmp/task_result.json"