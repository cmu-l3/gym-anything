#!/bin/bash
# Export script for document_patient_expiration task

echo "=== Exporting document_patient_expiration result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
PATIENT_ID=$(cat /tmp/target_patient_id.txt 2>/dev/null || echo "0")

if [ -z "$PATIENT_ID" ] || [ "$PATIENT_ID" == "0" ]; then
    echo "ERROR: Target patient ID not found."
fi

# Take final screenshot
take_screenshot /tmp/task_final.png

# Export the raw patient record row to a text file for the python verifier
freemed_query "SELECT * FROM patient WHERE id=$PATIENT_ID" > /tmp/patient_record.txt 2>/dev/null || true

# Export any patient notes or annotations to a text file for the python verifier
freemed_query "SELECT * FROM pnotes WHERE patient=$PATIENT_ID" > /tmp/patient_notes.txt 2>/dev/null || true
freemed_query "SELECT * FROM annotation WHERE patient=$PATIENT_ID" >> /tmp/patient_notes.txt 2>/dev/null || true

# Prepare result JSON indicating where files are located and metadata
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $(date +%s),
    "patient_id": "$PATIENT_ID",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Handle file permissions safely so python verifier can read it
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Results successfully exported."
echo "=== Export Complete ==="