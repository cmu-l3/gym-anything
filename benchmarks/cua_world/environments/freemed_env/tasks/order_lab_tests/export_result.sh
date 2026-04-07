#!/bin/bash
# Export task: order_lab_tests
# Diffs the database to definitively prove new clinical orders were created.

echo "=== Exporting order_lab_tests result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_state.png
sleep 1

# Retrieve patient ID
PATIENT_ID=$(cat /tmp/marcus_patient_id.txt 2>/dev/null || echo "UNKNOWN")

# Capture final database state
echo "Capturing final database state for diff..."
mysqldump -u freemed -pfreemed --skip-extended-insert --order-by-primary freemed > /tmp/freemed_after.sql

# Diff the SQL dumps to isolate NEWly inserted or modified rows
# comm -13 outputs lines unique to FILE2 (the after state)
echo "Generating database diff..."
comm -13 <(sort /tmp/freemed_before.sql) <(sort /tmp/freemed_after.sql) > /tmp/freemed_diff.sql

# Analyze the diff for required clinical markers
# We search the isolated new rows for keywords proving the task was accomplished
DIFF_TOTAL_LINES=$(wc -l < /tmp/freemed_diff.sql)
DIFF_HAS_PATIENT=$(grep -i "marcus\|vance\|'${PATIENT_ID}'" /tmp/freemed_diff.sql | wc -l)
DIFF_HAS_LIPID=$(grep -i "lipid\|80061\|cholesterol" /tmp/freemed_diff.sql | wc -l)
DIFF_HAS_A1C=$(grep -i "a1c\|hemoglobin\|83036" /tmp/freemed_diff.sql | wc -l)

echo "Diff Analysis:"
echo "New rows modified/inserted: $DIFF_TOTAL_LINES"
echo "Rows containing patient refs: $DIFF_HAS_PATIENT"
echo "Rows containing Lipid refs: $DIFF_HAS_LIPID"
echo "Rows containing A1c refs: $DIFF_HAS_A1C"

# Package results into JSON using a temporary file to prevent permission/corruption issues
TEMP_JSON=$(mktemp /tmp/order_lab_tests_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "patient_id": "$PATIENT_ID",
    "diff_total_lines": $DIFF_TOTAL_LINES,
    "diff_has_patient": $DIFF_HAS_PATIENT,
    "diff_has_lipid": $DIFF_HAS_LIPID,
    "diff_has_a1c": $DIFF_HAS_A1C,
    "screenshot_path": "/tmp/task_final_state.png",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move to final destination
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/task_result.json"
cat /tmp/task_result.json

echo ""
echo "=== Export Complete ==="