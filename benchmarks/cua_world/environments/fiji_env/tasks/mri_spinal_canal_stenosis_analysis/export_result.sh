#!/bin/bash
echo "=== Exporting Spinal Canal Stenosis Results ==="

# Get task start timestamp
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

# Paths
RESULTS_DIR="/home/ga/Fiji_Data/results/stenosis"
CSV_PATH="$RESULTS_DIR/canal_measurements.csv"
DIAGNOSIS_PATH="$RESULTS_DIR/diagnosis.txt"
EVIDENCE_PATH="$RESULTS_DIR/segmentation_evidence.png"
JSON_OUTPUT="/tmp/stenosis_result.json"

# Capture final state screenshot
DISPLAY=:1 scrot /tmp/task_final_state.png 2>/dev/null || true

# Initialize JSON fields
CSV_EXISTS="false"
CSV_MODIFIED="false"
CSV_ROWS=0
CSV_CONTENT=""

DIAG_EXISTS="false"
DIAG_MODIFIED="false"
DIAG_CONTENT=""

EVIDENCE_EXISTS="false"
EVIDENCE_MODIFIED="false"

# 1. Check CSV
if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    MTIME=$(stat -c %Y "$CSV_PATH")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        CSV_MODIFIED="true"
    fi
    # Count data rows (excluding header)
    CSV_ROWS=$(grep -cve '^\s*$' "$CSV_PATH")
    # Read content for verifier to parse
    CSV_CONTENT=$(cat "$CSV_PATH" | base64 -w 0)
fi

# 2. Check Diagnosis File
if [ -f "$DIAGNOSIS_PATH" ]; then
    DIAG_EXISTS="true"
    MTIME=$(stat -c %Y "$DIAGNOSIS_PATH")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        DIAG_MODIFIED="true"
    fi
    DIAG_CONTENT=$(cat "$DIAGNOSIS_PATH" | head -n 1 | tr -d '\n\r')
fi

# 3. Check Evidence Screenshot
if [ -f "$EVIDENCE_PATH" ]; then
    EVIDENCE_EXISTS="true"
    MTIME=$(stat -c %Y "$EVIDENCE_PATH")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        EVIDENCE_MODIFIED="true"
    fi
fi

# Construct JSON using python for safety against escaping issues
python3 -c "
import json
import os

result = {
    'task_start': $TASK_START,
    'csv_exists': $CSV_EXISTS,
    'csv_modified_after_start': $CSV_MODIFIED,
    'csv_row_count': $CSV_ROWS,
    'csv_content_base64': '$CSV_CONTENT',
    'diagnosis_exists': $DIAG_EXISTS,
    'diagnosis_modified_after_start': $DIAG_MODIFIED,
    'diagnosis_content': '$DIAG_CONTENT',
    'evidence_exists': $EVIDENCE_EXISTS,
    'evidence_modified_after_start': $EVIDENCE_MODIFIED
}

with open('$JSON_OUTPUT', 'w') as f:
    json.dump(result, f)
"

echo "Export complete. Result saved to $JSON_OUTPUT"
cat "$JSON_OUTPUT"