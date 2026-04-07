#!/bin/bash
echo "=== Exporting Weibull ALT Results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")
take_screenshot /tmp/task_final.png

# --- Define Paths ---
PARAMS_CSV="/home/ga/RProjects/output/insulation_weibull_params.csv"
PRED_CSV="/home/ga/RProjects/output/insulation_reliability_prediction.csv"
PLOT_PNG="/home/ga/RProjects/output/insulation_analysis_plots.png"
SCRIPT_PATH="/home/ga/RProjects/insulation_analysis.R"

# --- Analyze Params CSV ---
PARAMS_EXISTS=false
PARAMS_IS_NEW=false
PARAMS_DATA="[]"

if [ -f "$PARAMS_CSV" ]; then
    PARAMS_EXISTS=true
    MTIME=$(stat -c %Y "$PARAMS_CSV" 2>/dev/null || echo "0")
    [ "$MTIME" -gt "$TASK_START" ] && PARAMS_IS_NEW=true
    
    # Convert CSV to JSON for verifier
    PARAMS_DATA=$(python3 -c "
import csv, json
try:
    with open('$PARAMS_CSV', 'r') as f:
        reader = csv.DictReader(f)
        rows = list(reader)
        # normalize keys to lowercase
        normalized = [{k.lower(): v for k,v in r.items()} for r in rows]
        print(json.dumps(normalized))
except:
    print('[]')
")
fi

# --- Analyze Prediction CSV ---
PRED_EXISTS=false
PRED_IS_NEW=false
PRED_DATA="[]"

if [ -f "$PRED_CSV" ]; then
    PRED_EXISTS=true
    MTIME=$(stat -c %Y "$PRED_CSV" 2>/dev/null || echo "0")
    [ "$MTIME" -gt "$TASK_START" ] && PRED_IS_NEW=true
    
    PRED_DATA=$(python3 -c "
import csv, json
try:
    with open('$PRED_CSV', 'r') as f:
        reader = csv.DictReader(f)
        rows = list(reader)
        normalized = [{k.lower(): v for k,v in r.items()} for r in rows]
        print(json.dumps(normalized))
except:
    print('[]')
")
fi

# --- Analyze Plot ---
PLOT_EXISTS=false
PLOT_IS_NEW=false
PLOT_SIZE_BYTES=0

if [ -f "$PLOT_PNG" ]; then
    PLOT_EXISTS=true
    MTIME=$(stat -c %Y "$PLOT_PNG" 2>/dev/null || echo "0")
    [ "$MTIME" -gt "$TASK_START" ] && PLOT_IS_NEW=true
    PLOT_SIZE_BYTES=$(stat -c %s "$PLOT_PNG" 2>/dev/null || echo "0")
fi

# --- Analyze Script ---
SCRIPT_MODIFIED=false
if [ -f "$SCRIPT_PATH" ]; then
    MTIME=$(stat -c %Y "$SCRIPT_PATH" 2>/dev/null || echo "0")
    [ "$MTIME" -gt "$TASK_START" ] && SCRIPT_MODIFIED=true
fi

# --- Create Result JSON ---
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "params_csv": {
        "exists": $PARAMS_EXISTS,
        "is_new": $PARAMS_IS_NEW,
        "data": $PARAMS_DATA
    },
    "pred_csv": {
        "exists": $PRED_EXISTS,
        "is_new": $PRED_IS_NEW,
        "data": $PRED_DATA
    },
    "plot": {
        "exists": $PLOT_EXISTS,
        "is_new": $PLOT_IS_NEW,
        "size_bytes": $PLOT_SIZE_BYTES
    },
    "script_modified": $SCRIPT_MODIFIED
}
EOF

# Move to safe location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete."