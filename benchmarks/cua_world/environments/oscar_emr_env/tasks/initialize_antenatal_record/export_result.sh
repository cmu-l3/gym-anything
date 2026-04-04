#!/bin/bash
# Export script for Initialize Antenatal Record task
echo "=== Exporting Antenatal Record Results ==="

source /workspace/scripts/task_utils.sh

# Load context from setup
DEMO_NO=$(cat /tmp/task_patient_id.txt 2>/dev/null || echo "")
TARGET_LMP=$(cat /tmp/target_lmp.txt 2>/dev/null || echo "")
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

echo "Checking for Antenatal Record 1 for Demographic No: $DEMO_NO"

# Query the formAR1 table
# We are looking for a record created/modified recently for this patient
# Common fields: id, demographic_no, LMP, EDD, form_date (or similar timestamp)

# Note: Table structure might vary slightly by Oscar version, but formAR1 is standard.
# We select the most recent record.
# Using 'form_date' or 'created' depending on schema. We'll fetch all likely columns.
# We prioritize ID desc to get the newest.

QUERY="SELECT id, demographic_no, LMP, EDD, form_date FROM formAR1 WHERE demographic_no='$DEMO_NO' ORDER BY id DESC LIMIT 1"
RESULT=$(oscar_query "$QUERY")

FOUND="false"
RECORD_ID=""
RECORD_LMP=""
RECORD_EDD=""
RECORD_DATE=""

if [ -n "$RESULT" ]; then
    FOUND="true"
    RECORD_ID=$(echo "$RESULT" | awk '{print $1}')
    # Skip column 2 (demo_no)
    RECORD_LMP=$(echo "$RESULT" | awk '{print $3}')
    RECORD_EDD=$(echo "$RESULT" | awk '{print $4}')
    RECORD_DATE=$(echo "$RESULT" | awk '{print $5}')
    
    echo "Found Record ID: $RECORD_ID"
    echo "LMP: $RECORD_LMP"
    echo "EDD: $RECORD_EDD"
    echo "Date: $RECORD_DATE"
else
    echo "No Antenatal Record found in formAR1 table."
fi

# Check timestamps
# If form_date is just YYYY-MM-DD, we can't be precise about seconds, 
# but we can check if it matches today.
CURRENT_DATE_STR=$(date +%Y-%m-%d)
CREATED_TODAY="false"

# Simple string comparison for date
if [[ "$RECORD_DATE" == *"$CURRENT_DATE_STR"* ]] || [[ "$RECORD_DATE" == "$CURRENT_DATE_STR" ]]; then
    CREATED_TODAY="true"
fi

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_ts": $TASK_START,
    "task_end_ts": $TASK_END,
    "target_lmp": "$TARGET_LMP",
    "record_found": $FOUND,
    "record_id": "${RECORD_ID:-0}",
    "record_lmp": "${RECORD_LMP:-}",
    "record_edd": "${RECORD_EDD:-}",
    "record_date": "${RECORD_DATE:-}",
    "created_today": $CREATED_TODAY,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Save to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "=== Export Complete ==="
cat /tmp/task_result.json