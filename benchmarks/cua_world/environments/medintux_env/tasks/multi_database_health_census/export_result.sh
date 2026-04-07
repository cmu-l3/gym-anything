#!/bin/bash
echo "=== Exporting multi_database_health_census result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

REPORT_PATH="/home/ga/Documents/medintux_data_census.txt"
GROUND_TRUTH_DIR="/tmp/census_ground_truth"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check report existence and timestamp
REPORT_EXISTS="false"
REPORT_CREATED_DURING_TASK="false"
REPORT_CONTENT=""

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    # Read content (limit to 50KB to avoid JSON bloat)
    REPORT_CONTENT=$(head -c 50000 "$REPORT_PATH" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')
    
    # Check timestamp
    FILE_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        REPORT_CREATED_DURING_TASK="true"
    fi
else
    REPORT_CONTENT="\"\""
fi

# Read Ground Truths into variables for JSON
GT_DRTUX_COUNT=$(cat "$GROUND_TRUTH_DIR/DrTuxTest_table_count.txt" 2>/dev/null || echo 0)
GT_MEDICA_COUNT=$(cat "$GROUND_TRUTH_DIR/MedicaTuxTest_table_count.txt" 2>/dev/null || echo 0)
GT_CIM10_COUNT=$(cat "$GROUND_TRUTH_DIR/CIM10Test_table_count.txt" 2>/dev/null || echo 0)
GT_CCAM_COUNT=$(cat "$GROUND_TRUTH_DIR/CCAMTest_table_count.txt" 2>/dev/null || echo 0)
GT_PATIENT_COUNT=$(cat "$GROUND_TRUTH_DIR/patient_count.txt" 2>/dev/null || echo 0)
GT_CIM10_CODES=$(cat "$GROUND_TRUTH_DIR/cim10_count.txt" 2>/dev/null || echo 0)
GT_CCAM_CODES=$(cat "$GROUND_TRUTH_DIR/ccam_count.txt" 2>/dev/null || echo 0)

# Read lists as JSON arrays
GT_TOP5=$(cat "$GROUND_TRUTH_DIR/top_5_tables.txt" 2>/dev/null | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().splitlines()))')
GT_FCHPAT_COLS=$(cat "$GROUND_TRUTH_DIR/fchpat_columns.txt" 2>/dev/null | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().splitlines()))')
GT_ALL_ROWS=$(cat "$GROUND_TRUTH_DIR/all_table_rows.txt" 2>/dev/null | python3 -c 'import json,sys; rows=[l.split("\t") for l in sys.stdin.read().splitlines() if "\t" in l]; print(json.dumps(rows))')

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "report_exists": $REPORT_EXISTS,
    "report_created_during_task": $REPORT_CREATED_DURING_TASK,
    "report_content": $REPORT_CONTENT,
    "ground_truth": {
        "table_counts": {
            "DrTuxTest": $GT_DRTUX_COUNT,
            "MedicaTuxTest": $GT_MEDICA_COUNT,
            "CIM10Test": $GT_CIM10_COUNT,
            "CCAMTest": $GT_CCAM_COUNT
        },
        "patient_count": $GT_PATIENT_COUNT,
        "cim10_codes": $GT_CIM10_CODES,
        "ccam_codes": $GT_CCAM_CODES,
        "top_5_tables": $GT_TOP5,
        "fchpat_columns": $GT_FCHPAT_COLS,
        "all_table_rows": $GT_ALL_ROWS
    },
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save result
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
echo "=== Export complete ==="