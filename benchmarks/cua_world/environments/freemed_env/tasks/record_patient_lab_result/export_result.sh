#!/bin/bash
# Export script for record_patient_lab_result task

echo "=== Exporting record_patient_lab_result task ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_lab_end.png

# We do a full database dump with --skip-extended-insert to put every row on its own line.
# This makes it very reliable to grep for the accession number and check if the analytes are in the same record.
echo "Dumping FreeMED database for verification..."
mysqldump -u freemed -pfreemed --skip-extended-insert freemed > /tmp/freemed_dump.sql 2>/dev/null

# Extract the line(s) containing the unique accession number
grep "ACC-88492-LP" /tmp/freemed_dump.sql > /tmp/freemed_lab_records.txt || true

# Check if accession number was found at all
if [ -s /tmp/freemed_lab_records.txt ]; then
    ACCESSION_FOUND="true"
else
    ACCESSION_FOUND="false"
fi

# Check for specific analyte values
# We check BOTH the specific record line AND the entire DB dump as a fallback (in case they split records)
if grep -q "195" /tmp/freemed_lab_records.txt; then
    CHOL_FOUND="true"
elif grep -q "195" /tmp/freemed_dump.sql; then
    CHOL_FOUND="partial"
else
    CHOL_FOUND="false"
fi

if grep -q "120" /tmp/freemed_lab_records.txt; then
    TRIG_FOUND="true"
elif grep -q "120" /tmp/freemed_dump.sql; then
    TRIG_FOUND="partial"
else
    TRIG_FOUND="false"
fi

if grep -q "45" /tmp/freemed_lab_records.txt; then
    HDL_FOUND="true"
elif grep -q "45" /tmp/freemed_dump.sql; then
    HDL_FOUND="partial"
else
    HDL_FOUND="false"
fi

if grep -q "126" /tmp/freemed_lab_records.txt; then
    LDL_FOUND="true"
elif grep -q "126" /tmp/freemed_dump.sql; then
    LDL_FOUND="partial"
else
    LDL_FOUND="false"
fi

# Create JSON output
TEMP_JSON=$(mktemp /tmp/record_lab_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "accession_found": $ACCESSION_FOUND,
    "cholesterol_found": "$CHOL_FOUND",
    "triglycerides_found": "$TRIG_FOUND",
    "hdl_found": "$HDL_FOUND",
    "ldl_found": "$LDL_FOUND",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Ensure safe movement and permissions
rm -f /tmp/record_lab_result.json 2>/dev/null || sudo rm -f /tmp/record_lab_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/record_lab_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/record_lab_result.json
chmod 666 /tmp/record_lab_result.json 2>/dev/null || sudo chmod 666 /tmp/record_lab_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/record_lab_result.json"
cat /tmp/record_lab_result.json

echo ""
echo "=== Export Complete ==="