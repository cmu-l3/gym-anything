#!/bin/bash
echo "=== Exporting mark_patient_deceased result ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Capture Task Timing
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 3. Retrieve the patient document from CouchDB
PATIENT_ID="patient_p1_eleanor"
echo "Fetching patient document for $PATIENT_ID..."

# Fetch doc directly from CouchDB
# We use the helper or raw curl
DOC_JSON=$(curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/${PATIENT_ID}")

# 4. Create Export JSON
# We embed the fetched doc into our result structure
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "patient_doc": $DOC_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location with proper permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="