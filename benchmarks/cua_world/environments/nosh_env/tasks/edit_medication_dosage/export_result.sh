#!/bin/bash
echo "=== Exporting Task Results ==="

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_MED_ID=$(cat /tmp/initial_med_id.txt 2>/dev/null || echo "0")

# 1. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Query Database for Final State
# We look for Lisinopril for Patient 3. 
# We fetch ID, Dosage, Sig, Active Date to verify changes.
echo "Querying database for final medication state..."

# Fetch as JSON-like string or CSV to parse in Python, or simple variables here.
# We fetch the row that matches the criteria.
RAW_RESULT=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e \
    "SELECT rxl_id, rxl_dosage, rxl_sig, rxl_frequency, rxl_date_active, rxl_date_old \
     FROM rx_list \
     WHERE pid=3 AND rxl_medication LIKE '%Lisinopril%' \
     ORDER BY rxl_id DESC LIMIT 1;" 2>/dev/null)

# Parse the result (Tab separated)
# If no result found, variables will be empty
read -r FINAL_ID FINAL_DOSAGE FINAL_SIG FINAL_FREQ FINAL_ACTIVE_DATE FINAL_UPDATE_DATE <<< "$RAW_RESULT"

echo "Found Record: ID=$FINAL_ID Dosage='$FINAL_DOSAGE' Sig='$FINAL_SIG'"

# 3. Check for specific success indicators locally to build the JSON
MED_EXISTS="false"
if [ -n "$FINAL_ID" ]; then
    MED_EXISTS="true"
fi

# Check if the record ID changed (did they edit the existing one or delete+create new?)
# Ideally, editing keeps ID or updates a history table. 
# In NOSH, editing might create a new row and archive the old one, or update in place.
# We export both IDs to let the python verifier decide the scoring logic.

# Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_med_id": "$INITIAL_MED_ID",
    "final_med_id": "$FINAL_ID",
    "med_exists": $MED_EXISTS,
    "final_dosage": "$(echo $FINAL_DOSAGE | sed 's/"/\\"/g')",
    "final_sig": "$(echo $FINAL_SIG | sed 's/"/\\"/g')",
    "final_frequency": "$(echo $FINAL_FREQ | sed 's/"/\\"/g')",
    "final_active_date": "$FINAL_ACTIVE_DATE",
    "final_update_date": "$FINAL_UPDATE_DATE",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete. Result:"
cat /tmp/task_result.json