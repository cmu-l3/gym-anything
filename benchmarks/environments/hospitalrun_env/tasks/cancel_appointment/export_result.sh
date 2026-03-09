#!/bin/bash
echo "=== Exporting cancel_appointment result ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot
take_screenshot /tmp/cancel_appointment_final.png

# 2. Get the target appointment document from CouchDB
TARGET_ID=$(cat /tmp/target_appt_id.txt 2>/dev/null || echo "appointment_p1_tbaker_checkup")
echo "Fetching document: $TARGET_ID"

DOC_CONTENT=$(curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/${TARGET_ID}")

# 3. Check if document exists (curl returns error json if not found)
DOC_EXISTS="false"
if echo "$DOC_CONTENT" | grep -q "\"_id\":\"$TARGET_ID\""; then
    DOC_EXISTS="true"
fi

# 4. Save result to JSON
# We save the raw doc content to let Python verifier parse fields safely
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $(cat /tmp/task_start_time.txt 2>/dev/null || echo "0"),
    "export_time": $(date +%s),
    "doc_exists": $DOC_EXISTS,
    "doc_content": $DOC_CONTENT,
    "screenshot_path": "/tmp/cancel_appointment_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"