#!/bin/bash
set -e
echo "=== Exporting Task Results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Retrieve Patient Info
# We need to know who the target was to query the DB
if [ -f /tmp/task_patient_info.txt ]; then
    PATIENT_NAME=$(cat /tmp/task_patient_info.txt)
    # Get PID based on name (assuming uniqueness for this setup or just taking the first match which is fine for verification)
    FNAME=$(echo "$PATIENT_NAME" | awk '{print $1}')
    LNAME=$(echo "$PATIENT_NAME" | awk '{print $2}')
    PID=$(librehealth_query "SELECT pid FROM patient_data WHERE fname='${FNAME}' AND lname='${LNAME}' LIMIT 1" 2>/dev/null)
else
    echo "Error: Patient info not found"
    PID=""
fi

TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")
CURRENT_TIME=$(date +%s)

# 3. Query Database for Results
# We output a JSON structure directly using jq or python construction would be cleaner,
# but here we'll build it manually to ensure no dependency issues if jq isn't perfect.

if [ -n "$PID" ]; then
    # Check Medication: Look for Lisinopril with an END DATE set
    # We select the enddate of the Lisinopril entry.
    # Note: 'activity' might still be 1 depending on how EHR handles logic, but enddate is the key field.
    MED_DATA=$(librehealth_query "SELECT id, enddate, comments FROM lists WHERE pid=${PID} AND type='medication' AND title LIKE '%Lisinopril%' ORDER BY id DESC LIMIT 1" 2>/dev/null)
    
    MED_ID=$(echo "$MED_DATA" | awk '{print $1}')
    MED_ENDDATE=$(echo "$MED_DATA" | awk '{print $2}')
    MED_COMMENTS=$(echo "$MED_DATA" | cut -d' ' -f3-) # Rough cut for comments
    
    # Check Allergy: Look for new Lisinopril allergy
    # We check date > task start time approx (or just date=today)
    ALLERGY_DATA=$(librehealth_query "SELECT id, title, diagnosis, date FROM lists WHERE pid=${PID} AND type='allergy' AND (title LIKE '%Lisinopril%' OR title LIKE '%ACE%') ORDER BY id DESC LIMIT 1" 2>/dev/null)
    
    ALLERGY_ID=$(echo "$ALLERGY_DATA" | awk '{print $1}')
    ALLERGY_TITLE=$(echo "$ALLERGY_DATA" | awk '{print $2}')
    ALLERGY_REACTION=$(echo "$ALLERGY_DATA" | awk '{print $3}') # Diagnosis/Reaction column
    ALLERGY_DATE=$(echo "$ALLERGY_DATA" | awk '{print $4}')

else
    MED_ID=""
    ALLERGY_ID=""
fi

# 4. Create JSON Result
cat > /tmp/task_result.json << EOF
{
    "task_start_time": ${TASK_START},
    "task_end_time": ${CURRENT_TIME},
    "patient_pid": "${PID}",
    "medication_check": {
        "id": "${MED_ID}",
        "end_date": "${MED_ENDDATE}",
        "comments": "${MED_COMMENTS}"
    },
    "allergy_check": {
        "id": "${ALLERGY_ID}",
        "title": "${ALLERGY_TITLE}",
        "reaction": "${ALLERGY_REACTION}",
        "date": "${ALLERGY_DATE}"
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

echo "Exported JSON:"
cat /tmp/task_result.json

# 5. Permission fix (so the host verifier can read it via copy_from_env if needed, though usually root works)
chmod 644 /tmp/task_result.json 2>/dev/null || true