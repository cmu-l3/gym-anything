#!/bin/bash
echo "=== Exporting upload_referral_letter result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Verify Application State (Firefox running)
APP_RUNNING=$(pgrep -f firefox > /dev/null && echo "true" || echo "false")

# 3. Export Patient Data from CouchDB
# We need to fetch the document for Hiroshi Tanaka to check attachments
PATIENT_ID="patient_p1_00555"
PATIENT_DATA=$(curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/${PATIENT_ID}")

# 4. Check File System (Sanity check that the source file still exists)
SOURCE_FILE="/home/ga/Documents/referral_letter.pdf"
SOURCE_EXISTS="false"
if [ -f "$SOURCE_FILE" ]; then
    SOURCE_EXISTS="true"
fi

# 5. Construct JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "source_file_exists": $SOURCE_EXISTS,
    "patient_doc": $PATIENT_DATA,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location with permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
echo "=== Export complete ==="