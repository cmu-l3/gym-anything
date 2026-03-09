#!/bin/bash
# Export script for Renew Prescription task
# Extracts database state to JSON for verifier

echo "=== Exporting Renew Prescription Result ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final_screenshot.png

# 2. Load Context
INITIAL_MAX_ID=$(cat /tmp/initial_drugs_max_id 2>/dev/null || echo "0")
DEMO_NO=$(cat /tmp/task_patient_id 2>/dev/null || echo "0")
TASK_START_TIMESTAMP=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

echo "Checking for new prescriptions for Patient $DEMO_NO (ID > $INITIAL_MAX_ID)..."

# 3. Query for New Prescription
# We look for a drug record for this patient created after the task started (ID > Initial Max)
# We expect Metformin
NEW_RX_JSON=$(docker exec oscar-db mysql -u oscar -poscar oscar -e "
SELECT 
    id, 
    gn, 
    dosage, 
    quantity, 
    repeat_rx as repeats, 
    rx_date, 
    archived 
FROM drugs 
WHERE demographic_no='$DEMO_NO' 
  AND id > $INITIAL_MAX_ID 
ORDER BY id DESC LIMIT 1
" -B --json 2>/dev/null)

# 4. Query for Old Prescription (Preservation Check)
# We check if the old record (ID <= Initial Max) still exists and is active
# Note: OSCAR usually archives old ones or keeps them. We just want to ensure history wasn't wiped.
OLD_RX_COUNT=$(oscar_query "SELECT COUNT(*) FROM drugs WHERE demographic_no='$DEMO_NO' AND id <= $INITIAL_MAX_ID AND gn LIKE '%Metformin%'")

# 5. Format Output JSON
# If no new rx found, NEW_RX_JSON might be empty or just brackets
if [ -z "$NEW_RX_JSON" ] || [ "$NEW_RX_JSON" == "[]" ]; then
    NEW_RX_OBJ="null"
else
    # Extract the object from the array [ { ... } ]
    NEW_RX_OBJ=$(echo "$NEW_RX_JSON" | python3 -c "import sys, json; print(json.dumps(json.load(sys.stdin)[0]))" 2>/dev/null || echo "null")
fi

TEMP_JSON=$(mktemp /tmp/renew_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_timestamp": $TASK_START_TIMESTAMP,
    "initial_max_id": $INITIAL_MAX_ID,
    "patient_id": "$DEMO_NO",
    "new_prescription": $NEW_RX_OBJ,
    "old_prescription_count": $OLD_RX_COUNT,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# 6. Save to shared location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Exported Data:"
cat /tmp/task_result.json
echo ""
echo "=== Export Complete ==="