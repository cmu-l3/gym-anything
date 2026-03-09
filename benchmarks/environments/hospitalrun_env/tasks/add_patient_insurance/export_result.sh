#!/bin/bash
echo "=== Exporting add_patient_insurance results ==="

source /workspace/scripts/task_utils.sh

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Get task timing
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
INITIAL_REV=$(cat /tmp/initial_rev.txt 2>/dev/null || echo "")

# Fetch the patient document from CouchDB
DOC_ID="patient_p1_000008"
echo "Fetching patient record for $DOC_ID..."
PATIENT_DOC=$(curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/${DOC_ID}")

# Check if file exists/curl worked
if [ -z "$PATIENT_DOC" ] || [ "$PATIENT_DOC" == "{}" ]; then
    DOC_EXISTS="false"
else
    DOC_EXISTS="true"
fi

# Create a clean JSON export for the verifier
# We wrap the raw CouchDB doc in our result structure
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_rev": "$INITIAL_REV",
    "doc_exists": $DOC_EXISTS,
    "patient_record": $PATIENT_DOC,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location with proper permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
echo "=== Export complete ==="