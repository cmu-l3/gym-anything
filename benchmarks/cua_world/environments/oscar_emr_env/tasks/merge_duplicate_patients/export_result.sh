#!/bin/bash
echo "=== Exporting Merge Task Results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot for VLM verification
take_screenshot /tmp/task_final.png

# 1. Check status of PRIMARY record (10001) - Should be 'AC'
STATUS_10001=$(oscar_query "SELECT patient_status FROM demographic WHERE demographic_no=10001" 2>/dev/null || echo "MISSING")

# 2. Check status of DUPLICATE record (10002) - Should be 'MR', 'IN', or record missing
STATUS_10002=$(oscar_query "SELECT patient_status FROM demographic WHERE demographic_no=10002" 2>/dev/null || echo "MISSING")

# 3. Check total active records for this person
ACTIVE_COUNT=$(oscar_query "SELECT COUNT(*) FROM demographic WHERE last_name='Smith' AND date_of_birth='1965-05-20' AND patient_status='AC'" 2>/dev/null || echo "0")

# 4. Check for merge evidence in demographic_merged table
MERGE_RECORD_EXISTS=$(oscar_query "SELECT COUNT(*) FROM demographic_merged WHERE demographic_no=10002 OR merged_to=10001" 2>/dev/null || echo "0")

# 5. Check logs for merge activity
LOG_MERGE_COUNT=$(oscar_query "SELECT COUNT(*) FROM log WHERE action LIKE '%merge%' AND (content LIKE '%10001%' OR content LIKE '%10002%')" 2>/dev/null || echo "0")

# 6. Check if Allergy was transferred to 10001
ALLERGY_TRANSFERRED=$(oscar_query "SELECT COUNT(*) FROM allergies WHERE demographic_no='10001' AND description LIKE '%PENICILLIN%'" 2>/dev/null || echo "0")

# Get task timings
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "primary_status": "$STATUS_10001",
    "duplicate_status": "$STATUS_10002",
    "active_patient_count": $ACTIVE_COUNT,
    "merge_table_count": $MERGE_RECORD_EXISTS,
    "log_merge_count": $LOG_MERGE_COUNT,
    "allergy_transferred": $ALLERGY_TRANSFERRED,
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location (handle permissions)
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="