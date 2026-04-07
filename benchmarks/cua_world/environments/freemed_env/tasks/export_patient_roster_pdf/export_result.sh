#!/bin/bash
echo "=== Exporting export_patient_roster_pdf result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TARGET_FILE="/home/ga/Documents/patient_roster.pdf"

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check if target file exists and get metadata
OUTPUT_EXISTS="false"
OUTPUT_SIZE="0"
FILE_CREATED_DURING_TASK="false"

if [ -f "$TARGET_FILE" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$TARGET_FILE" 2>/dev/null || echo "0")
    
    OUTPUT_MTIME=$(stat -c %Y "$TARGET_FILE" 2>/dev/null || echo "0")
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Copy PDF to /tmp for easy retrieval by the host verifier
    cp "$TARGET_FILE" /tmp/exported_roster.pdf
    chmod 666 /tmp/exported_roster.pdf
fi

# Extract up to 50 patient names from the DB to pass to the verifier
# This creates a JSON array of strings: ["First Last", "First Last"]
PATIENTS_JSON=$(freemed_query "SELECT CONCAT('\"', ptfname, ' ', ptlname, '\"') FROM patient LIMIT 50" 2>/dev/null | tr '\n' ',' | sed 's/,$//')
if [ -z "$PATIENTS_JSON" ]; then
    PATIENTS_JSON="[]"
else
    PATIENTS_JSON="[$PATIENTS_JSON]"
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/export_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "output_exists": $OUTPUT_EXISTS,
    "output_size_bytes": $OUTPUT_SIZE,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "db_patients": $PATIENTS_JSON
}
EOF

# Move to final location securely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/task_result.json"
cat /tmp/task_result.json

echo "=== Export complete ==="