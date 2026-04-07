#!/bin/bash
echo "=== Exporting record_patient_lab_results task ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)
PATIENT_ID=$(cat /tmp/patient_id.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_end.png

echo "Taking post-task database snapshot..."
mysqldump -u freemed -pfreemed freemed --skip-extended-insert --no-create-info > /tmp/db_after.sql 2>/dev/null

echo "Analyzing database diff..."
# We only care about new or updated lines (starting with > in diff)
diff /tmp/db_before.sql /tmp/db_after.sql | grep "^> " > /tmp/db_diff.txt

# Safely look for modifications linked to the patient ID as a standalone SQL value
# This regex matches the ID preceded by a parenthesis/comma and followed by a comma/parenthesis
grep -E "[(,][[:space:]]*'?$PATIENT_ID'?[[:space:]]*[,)]" /tmp/db_diff.txt > /tmp/patient_diff.txt
PATIENT_ROWS=$(wc -l < /tmp/patient_diff.txt)

# Check for specific values in rows that ALSO contain the patient ID
LIPID_FOUND=$(grep -i "Lipid" /tmp/patient_diff.txt | wc -l)
VAL_185_FOUND=$(grep -E "\b185\b" /tmp/patient_diff.txt | wc -l)
VAL_55_FOUND=$(grep -E "\b55\b" /tmp/patient_diff.txt | wc -l)
VAL_110_FOUND=$(grep -E "\b110\b" /tmp/patient_diff.txt | wc -l)
VAL_100_FOUND=$(grep -E "\b100\b" /tmp/patient_diff.txt | wc -l)

# Check if the user entered it somewhere but failed to link it to the correct patient
ANY_LIPID_FOUND=$(grep -i "Lipid" /tmp/db_diff.txt | wc -l)

# Check if app is running
APP_RUNNING="false"
if pgrep -f "firefox" > /dev/null; then
    APP_RUNNING="true"
fi

# Create JSON result safely
TEMP_JSON=$(mktemp /tmp/lab_results.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "patient_id": "$PATIENT_ID",
    "patient_rows_modified": $PATIENT_ROWS,
    "patient_lipid_found": $LIPID_FOUND,
    "patient_185_found": $VAL_185_FOUND,
    "patient_55_found": $VAL_55_FOUND,
    "patient_110_found": $VAL_110_FOUND,
    "patient_100_found": $VAL_100_FOUND,
    "any_lipid_found": $ANY_LIPID_FOUND,
    "app_running": $APP_RUNNING
}
EOF

# Move to final location ensuring proper permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="