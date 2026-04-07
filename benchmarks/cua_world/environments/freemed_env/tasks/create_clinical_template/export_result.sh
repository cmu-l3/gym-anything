#!/bin/bash
echo "=== Exporting Create Clinical Template Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot showing end state
take_screenshot /tmp/task_template_end.png

# Dump database to check final occurrences of the template text
mysqldump -u freemed -pfreemed freemed > /tmp/freemed_final_dump.sql 2>/dev/null || true

# Count occurrences of the phrases in the final database state
FINAL_HEENT_COUNT=$(grep -o "Normocephalic, atraumatic, PERRLA" /tmp/freemed_final_dump.sql 2>/dev/null | wc -l)
FINAL_CV_COUNT=$(grep -o "no murmurs, rubs, or gallops" /tmp/freemed_final_dump.sql 2>/dev/null | wc -l)
FINAL_TITLE_COUNT=$(grep -o "Normal Physical Exam" /tmp/freemed_final_dump.sql 2>/dev/null | wc -l)

# Read initial counts saved during setup
INITIAL_HEENT_COUNT=$(cat /tmp/initial_heent_count 2>/dev/null || echo "0")
INITIAL_CV_COUNT=$(cat /tmp/initial_cv_count 2>/dev/null || echo "0")
INITIAL_TITLE_COUNT=$(cat /tmp/initial_title_count 2>/dev/null || echo "0")

# Write to JSON using a temp file for atomic writing and permission handling
TEMP_JSON=$(mktemp /tmp/template_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "initial_heent_count": $INITIAL_HEENT_COUNT,
    "final_heent_count": $FINAL_HEENT_COUNT,
    "initial_cv_count": $INITIAL_CV_COUNT,
    "final_cv_count": $FINAL_CV_COUNT,
    "initial_title_count": $INITIAL_TITLE_COUNT,
    "final_title_count": $FINAL_TITLE_COUNT,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move JSON to expected destination with appropriate permissions
rm -f /tmp/template_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/template_result.json
chmod 666 /tmp/template_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/template_result.json"
cat /tmp/template_result.json
echo "=== Export complete ==="