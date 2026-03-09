#!/bin/bash
echo "=== Exporting Billing Correction Results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Retrieve Task Data
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TARGET_BILL_ID=$(cat /tmp/target_bill_id.txt 2>/dev/null || echo "")

echo "Analyzing Bill ID: $TARGET_BILL_ID"

if [ -z "$TARGET_BILL_ID" ]; then
    echo "CRITICAL: Target Bill ID not found. Verification may be compromised."
    # Fallback: Try to find the bill by attributes (Maria Santos, Yesterday)
    TARGET_BILL_ID=$(oscar_query "
        SELECT bm.id FROM billing_master bm
        JOIN demographic d ON bm.demographic_no = d.demographic_no
        WHERE d.first_name='Maria' AND d.last_name='Santos'
        AND bm.service_date = DATE_SUB(CURDATE(), INTERVAL 1 DAY)
        ORDER BY bm.id DESC LIMIT 1
    ")
    echo "Fallback Bill ID: $TARGET_BILL_ID"
fi

# 3. Query Current State of the Target Bill
# We fetch: Status, Diagnosis, LastUpdateDate, and count of bills for this patient/date (to check for duplicates)

QUERY="
SELECT 
    bm.id,
    bm.status,
    bi.diagnosis_code,
    UNIX_timestamp(bm.lastUpdateDate) as update_ts,
    (SELECT COUNT(*) FROM billing_master bm2 
     WHERE bm2.demographic_no = bm.demographic_no 
     AND bm2.service_date = bm.service_date) as bill_count
FROM billing_master bm
JOIN billing_item bi ON bm.id = bi.billing_master_id
WHERE bm.id = '$TARGET_BILL_ID';
"

RESULT_ROW=$(oscar_query "$QUERY")

# Parse Result (Tab separated: id, status, diagnosis, update_ts, bill_count)
# Example: 154  B   250   1715432000   1

BILL_ID=""
STATUS=""
DIAGNOSIS=""
UPDATE_TS="0"
BILL_COUNT="0"

if [ -n "$RESULT_ROW" ]; then
    BILL_ID=$(echo "$RESULT_ROW" | awk '{print $1}')
    STATUS=$(echo "$RESULT_ROW" | awk '{print $2}')
    DIAGNOSIS=$(echo "$RESULT_ROW" | awk '{print $3}')
    UPDATE_TS=$(echo "$RESULT_ROW" | awk '{print $4}')
    BILL_COUNT=$(echo "$RESULT_ROW" | awk '{print $5}')
fi

# 4. Generate JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "target_bill_id": "${TARGET_BILL_ID}",
    "found_bill_id": "${BILL_ID}",
    "status": "${STATUS}",
    "diagnosis_code": "${DIAGNOSIS}",
    "last_update_ts": ${UPDATE_TS:-0},
    "bill_count_for_date": ${BILL_COUNT:-0},
    "task_start_ts": ${TASK_START},
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location with permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Exported Data:"
cat /tmp/task_result.json
echo "=== Export Complete ==="