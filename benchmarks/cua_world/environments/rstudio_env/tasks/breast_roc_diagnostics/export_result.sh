#!/bin/bash
echo "=== Exporting breast_roc_diagnostics results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_DIR="/home/ga/RProjects/output"

# Take final screenshot
take_screenshot /tmp/task_final.png

# --- Helper to check file status ---
check_file() {
    local f="$1"
    local exists="false"
    local is_new="false"
    local size="0"
    
    if [ -f "$f" ]; then
        exists="true"
        size=$(stat -c %s "$f")
        mtime=$(stat -c %Y "$f")
        if [ "$mtime" -gt "$TASK_START" ]; then
            is_new="true"
        fi
    fi
    echo "{\"exists\": $exists, \"is_new\": $is_new, \"size\": $size}"
}

# --- Check Deliverable 1: Individual ROC CSV ---
F1="$OUTPUT_DIR/breast_roc_individual.csv"
S1=$(check_file "$F1")
# Parse content if exists
D1_DATA="[]"
if [ -f "$F1" ]; then
    # Convert CSV to JSON array using python
    D1_DATA=$(python3 -c "
import csv, json
try:
    with open('$F1', 'r') as f:
        reader = csv.DictReader(f)
        data = list(reader)
        # Sanitize numeric values
        for row in data:
            for k, v in row.items():
                try: row[k] = float(v)
                except: pass
        print(json.dumps(data))
except: print('[]')
")
fi

# --- Check Deliverable 2: Comparison CSV ---
F2="$OUTPUT_DIR/breast_auc_comparison.csv"
S2=$(check_file "$F2")
D2_DATA="[]"
if [ -f "$F2" ]; then
    D2_DATA=$(python3 -c "
import csv, json
try:
    with open('$F2', 'r') as f:
        reader = csv.DictReader(f)
        print(json.dumps(list(reader)))
except: print('[]')
")
fi

# --- Check Deliverable 3: Combined Model CSV ---
F3="$OUTPUT_DIR/breast_combined_model.csv"
S3=$(check_file "$F3")
D3_DATA="{}"
if [ -f "$F3" ]; then
    D3_DATA=$(python3 -c "
import csv, json
try:
    with open('$F3', 'r') as f:
        reader = csv.DictReader(f)
        rows = list(reader)
        if rows: print(json.dumps(rows[0]))
        else: print('{}')
except: print('{}')
")
fi

# --- Check Deliverable 4: Plot ---
F4="$OUTPUT_DIR/breast_roc_analysis.png"
S4=$(check_file "$F4")
IMG_DIMS="0x0"
if [ -f "$F4" ]; then
    IMG_DIMS=$(identify -format "%wx%h" "$F4" 2>/dev/null || echo "0x0")
fi

# --- Check R Script ---
SCRIPT="/home/ga/RProjects/breast_roc_analysis.R"
SCRIPT_S=$(check_file "$SCRIPT")
SCRIPT_CONTENT=""
if [ -f "$SCRIPT" ]; then
    SCRIPT_CONTENT=$(cat "$SCRIPT" | base64 -w 0)
fi

# --- Compile Result JSON ---
# Using a python script to compose the final JSON reliably
python3 -c "
import json
import os

result = {
    'timestamp': '$TASK_START',
    'files': {
        'individual_csv': $S1,
        'comparison_csv': $S2,
        'combined_csv': $S3,
        'plot': $S4,
        'script': $SCRIPT_S
    },
    'data': {
        'individual_roc': $D1_DATA,
        'auc_comparison': $D2_DATA,
        'combined_model': $D3_DATA
    },
    'plot_dims': '$IMG_DIMS',
    'script_content_b64': '$SCRIPT_CONTENT'
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f)
"

# Handle permissions
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
echo "=== Export complete ==="